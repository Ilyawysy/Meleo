import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase hide AuthException;
import '../../../core/env.dart';
import '../../../core/sentry_config.dart';
import '../../../core/analytics_service.dart';
import 'models/token_response.dart';
import 'models/register_result.dart';
import 'supabase_auth_service.dart';
import 'token_manager.dart';
import 'auth_exception.dart';

class AuthService {
  final SupabaseAuthService _supabaseAuthService = SupabaseAuthService();

  /// Регистрация нового пользователя через backend /api/v1/auth/register
  Future<RegisterResult> registerWithPassword({
    required String email,
    required String password,
  }) async {
    debugPrint('📝 [AuthService] registerWithPassword() called, email: $email');
    final uri = Uri.parse('${Env.apiBase}/api/v1/auth/register');
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return RegisterResult.fromJson(body);
      } else if (response.statusCode == 409) {
        throw AuthException.emailAlreadyRegistered();
      } else {
        String detail = 'Registration failed';
        try {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          if (body['detail'] != null) {
            detail = body['detail'].toString();
          }
        } catch (_) {}
        throw AuthException(detail);
      }
    } on AuthException {
      rethrow;
    } catch (e) {
      debugPrint('❌ [AuthService] registerWithPassword failed: $e');
      throw AuthException('Registration failed: $e');
    }
  }

  /// Проверить signup OTP и сохранить токены
  Future<TokenResponse> verifySignupOtp({
    required String email,
    required String token,
  }) async {
    debugPrint(
      '🔐 [AuthService] verifySignupOtp() called, email: $email, tokenLength: ${token.length}',
    );
    SentryConfig.addBreadcrumb(
      message: 'Signup OTP verification started',
      category: 'auth',
      criticalOnly: true,
      level: SentryLevel.info,
      data: {'email_hash': email.hashCode.toString()},
    );
    try {
      final tokenResponse = await _supabaseAuthService.verifySignupOtp(
        email: email,
        token: token,
      );
      await TokenManager.saveToken(tokenResponse);
      debugPrint('✅ [AuthService] Signup OTP verified, token saved');

      await AnalyticsService().identifyUser(
        tokenResponse.userId,
        properties: {'login_method': 'email_otp'},
      );

      SentryConfig.addBreadcrumb(
        message: 'Signup OTP verified successfully',
        category: 'auth',
        criticalOnly: true,
        level: SentryLevel.info,
        data: {'user_id': tokenResponse.userId},
      );
      return tokenResponse;
    } catch (e, stackTrace) {
      debugPrint('❌ [AuthService] Error in verifySignupOtp(): $e');
      debugPrint('❌ [AuthService] Stack trace: $stackTrace');
      SentryConfig.addBreadcrumb(
        message: 'Signup OTP verification failed',
        category: 'auth',
        criticalOnly: true,
        level: SentryLevel.error,
        data: {'error': e.toString()},
      );
      rethrow;
    }
  }

  /// Повторно отправить signup OTP
  Future<void> resendSignupOtp({required String email}) async {
    debugPrint('📧 [AuthService] resendSignupOtp() called, email: $email');
    try {
      await _supabaseAuthService.resendSignupOtp(email: email);
      debugPrint('✅ [AuthService] Signup OTP resent successfully');
    } catch (e, stackTrace) {
      debugPrint('❌ [AuthService] Error in resendSignupOtp(): $e');
      debugPrint('❌ [AuthService] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Вход через email + пароль
  Future<TokenResponse> signInWithPassword({
    required String email,
    required String password,
  }) async {
    debugPrint('🔐 [AuthService] signInWithPassword() called, email: $email');
    SentryConfig.addBreadcrumb(
      message: 'Password sign-in started',
      category: 'auth',
      criticalOnly: true,
      level: SentryLevel.info,
      data: {'email_hash': email.hashCode.toString()},
    );
    try {
      final tokenResponse = await _supabaseAuthService.signInWithPassword(
        email: email,
        password: password,
      );
      await TokenManager.saveToken(tokenResponse);
      debugPrint('✅ [AuthService] signInWithPassword succeeded, token saved');

      await AnalyticsService().identifyUser(
        tokenResponse.userId,
        properties: {'login_method': 'email_password'},
      );

      SentryConfig.addBreadcrumb(
        message: 'Password sign-in successful',
        category: 'auth',
        criticalOnly: true,
        level: SentryLevel.info,
        data: {'user_id': tokenResponse.userId},
      );
      return tokenResponse;
    } catch (e, stackTrace) {
      debugPrint('❌ [AuthService] Error in signInWithPassword(): $e');
      debugPrint('❌ [AuthService] Stack trace: $stackTrace');
      SentryConfig.addBreadcrumb(
        message: 'Password sign-in failed',
        category: 'auth',
        criticalOnly: true,
        level: SentryLevel.error,
        data: {'error': e.toString()},
      );
      rethrow;
    }
  }

  /// Выход пользователя
  ///
  /// Последовательность:
  /// 1. Backend logout (best-effort, игнорируем ошибки)
  /// 2. Supabase signOut (КРИТИЧНО - НЕ ловим ошибку)
  /// 3. Очистка локальных токенов (только если Supabase signOut успешен)
  ///
  /// Если Supabase signOut падает - пробрасываем ошибку наверх,
  /// токены НЕ очищаются, пользователь может повторить logout.
  Future<void> logout() async {
    debugPrint('🚪 [AuthService] Logging out...');
    SentryConfig.addBreadcrumb(
      message: 'Logout initiated',
      category: 'auth',
      level: SentryLevel.info,
      criticalOnly: true,
    );

    // Шаг 1: Сохраняем токен ДО signOut (после signOut он будет недоступен)
    final token = await TokenManager.token;
    final userId = await TokenManager.userId;

    // Шаг 2: Supabase signOut (КРИТИЧНО — делаем ПЕРВЫМ, пока токен валиден)
    // Это отправляет signedOut событие в onAuthStateChange → AuthGate перестроится
    await _supabaseAuthService.logout();
    debugPrint('✅ [AuthService] Supabase signOut successful');

    // Шаг 3: Backend logout (best-effort — после Supabase, токен мог быть уже отозван)
    if (token != null && token.isNotEmpty) {
      final uri = Uri.parse('${Env.apiBase}/api/v1/auth/logout');
      try {
        await http.post(uri, headers: {
          'Authorization': 'Bearer $token',
        });
        debugPrint('✅ [AuthService] Backend logout successful');
      } catch (e) {
        debugPrint('⚠️ [AuthService] Backend logout failed (ignored): $e');
        SentryConfig.addBreadcrumb(
          message: 'Backend logout failed (ignored)',
          category: 'auth',
          criticalOnly: true,
          level: SentryLevel.warning,
        );
      }
    }

    // Шаг 4: Analytics - reset user identity
    if (userId != null) {
      await AnalyticsService().resetUser();
    }

    // Шаг 4: Очистка локальных токенов (выполняется только если Supabase signOut успешен)
    await TokenManager.clearToken();
    debugPrint('✅ [AuthService] Logout successful - tokens cleared');
    SentryConfig.addBreadcrumb(
      message: 'Logout completed successfully',
      category: 'auth',
      criticalOnly: true,
      level: SentryLevel.info,
    );
  }

  /// Записать токены из Supabase Session
  // ignore: unused_parameter — kept for call-site compatibility
  Future<TokenResponse> persistSession(
    supabase.Session session, {
    bool trackLogin = false,
  }) async {
    final tokenResponse = TokenResponse(
      accessToken: session.accessToken,
      userId: session.user.id,
      refreshToken: session.refreshToken,
    );
    await TokenManager.saveToken(tokenResponse);

    // Analytics: identify user
    await AnalyticsService().identifyUser(
      tokenResponse.userId,
      properties: {
        'login_method': 'oauth',
      },
    );

    return tokenResponse;
  }

  /// Логин через Google OAuth (браузерный flow)
  Future<void> signInWithGoogleOAuth() async {
    debugPrint('🔐 [AuthService] signInWithGoogleOAuth() called');
    SentryConfig.addBreadcrumb(
      message: 'Google OAuth sign-in initiated',
      category: 'auth',
      criticalOnly: true,
      level: SentryLevel.info,
    );
    try {
      await _supabaseAuthService.signInWithGoogleOAuth(
        redirectTo: Env.supabaseRedirectUrl,
      );
      SentryConfig.addBreadcrumb(
        message: 'Google OAuth flow started',
        category: 'auth',
        criticalOnly: true,
        level: SentryLevel.info,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [AuthService] Google OAuth error: $e');
      debugPrint('❌ [AuthService] Stack trace: $stackTrace');
      SentryConfig.addBreadcrumb(
        message: 'Google OAuth sign-in failed',
        category: 'auth',
        criticalOnly: true,
        level: SentryLevel.error,
        data: {'error': e.toString()},
      );
      rethrow;
    }
  }

  /// Обновить access token используя refresh token
  Future<TokenResponse> refreshToken() async {
    try {
      debugPrint('🔄 [AuthService] Starting token refresh...');
      SentryConfig.addBreadcrumb(
        message: 'Token refresh started',
        category: 'auth',
        criticalOnly: true,
        level: SentryLevel.info,
      );
      final refreshToken = await TokenManager.refreshToken;
      if (refreshToken == null || refreshToken.isEmpty) {
        debugPrint('❌ [AuthService] No refresh token available');
        SentryConfig.addBreadcrumb(
          message: 'Token refresh failed: no refresh token',
          category: 'auth',
          criticalOnly: true,
          level: SentryLevel.error,
        );
        throw AuthException('No refresh token available');
      }

      debugPrint('✅ [AuthService] Refresh token found, length: ${refreshToken.length}');
      debugPrint('🔄 [AuthService] Calling Supabase refresh...');
      final tokenResponse = await _supabaseAuthService.refreshAccessToken(
        refreshToken: refreshToken,
      );
      debugPrint('✅ [AuthService] Token response received from Supabase');
      debugPrint('🔄 [AuthService] Saving token to TokenManager...');
      await TokenManager.saveToken(tokenResponse);
      debugPrint('✅ [AuthService] Token refreshed and saved successfully');
      SentryConfig.addBreadcrumb(
        message: 'Token refreshed successfully',
        category: 'auth',
        criticalOnly: true,
        level: SentryLevel.info,
        data: {'user_id': tokenResponse.userId},
      );
      return tokenResponse;
    } catch (e, stackTrace) {
      debugPrint('❌ [AuthService] Token refresh error: $e');
      debugPrint('❌ [AuthService] Stack trace: $stackTrace');
      SentryConfig.addBreadcrumb(
        message: 'Token refresh failed',
        category: 'auth',
        criticalOnly: true,
        level: SentryLevel.error,
        data: {'error': e.toString()},
      );
      throw AuthException('Token refresh failed: $e');
    }
  }
}
