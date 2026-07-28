import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthException;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'auth_exception.dart';
import 'models/token_response.dart';

class SupabaseAuthService {
  SupabaseClient get _client => Supabase.instance.client;

  /// Проверить signup OTP и получить сессию
  Future<TokenResponse> verifySignupOtp({
    required String email,
    required String token,
  }) async {
    try {
      debugPrint(
        '🔐 [SupabaseAuthService] Verifying signup OTP, email: $email, tokenLength: ${token.length}',
      );
      final response = await _client.auth.verifyOTP(
        type: OtpType.signup,
        email: email,
        token: token,
      );
      final session = response.session;
      if (session == null) {
        throw AuthException('Authentication failed');
      }
      debugPrint('✅ [SupabaseAuthService] Signup OTP verified, session ready');
      return TokenResponse(
        accessToken: session.accessToken,
        userId: session.user.id,
        refreshToken: session.refreshToken,
      );
    } on supabase.AuthException catch (e) {
      throw AuthException(e.message);
    } catch (e) {
      debugPrint('❌ [SupabaseAuthService] verifySignupOtp failed: $e');
      throw AuthException('OTP verification failed: $e');
    }
  }

  /// Повторно отправить signup OTP
  Future<void> resendSignupOtp({required String email}) async {
    try {
      debugPrint('📧 [SupabaseAuthService] Resending signup OTP to: $email');
      await _client.auth.resend(type: OtpType.signup, email: email);
      debugPrint('✅ [SupabaseAuthService] Signup OTP resend request accepted');
    } on supabase.AuthException catch (e) {
      throw AuthException(e.message);
    } catch (e) {
      debugPrint('❌ [SupabaseAuthService] resendSignupOtp failed: $e');
      throw AuthException('Failed to resend OTP: $e');
    }
  }

  /// Вход через email + пароль
  Future<TokenResponse> signInWithPassword({
    required String email,
    required String password,
  }) async {
    try {
      debugPrint('🔐 [SupabaseAuthService] signInWithPassword, email: $email');
      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final session = response.session;
      if (session == null) {
        throw AuthException('Authentication failed');
      }
      debugPrint('✅ [SupabaseAuthService] signInWithPassword succeeded');
      return TokenResponse(
        accessToken: session.accessToken,
        userId: session.user.id,
        refreshToken: session.refreshToken,
      );
    } on supabase.AuthException catch (e) {
      if (e.statusCode == '400' || e.code == 'invalid_credentials') {
        throw AuthException.invalidCredentials();
      }
      throw AuthException(e.message);
    } catch (e) {
      if (e is AuthException) rethrow;
      debugPrint('❌ [SupabaseAuthService] signInWithPassword failed: $e');
      throw AuthException('Sign in failed: $e');
    }
  }

  /// Авторизация через Google OAuth (браузерный flow)
  Future<void> signInWithGoogleOAuth({
    String? redirectTo,
  }) async {
    try {
      debugPrint('🔐 [SupabaseAuthService] Starting Google OAuth...');
      await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectTo,
      );
      debugPrint('✅ [SupabaseAuthService] OAuth flow opened in browser');
    } on supabase.AuthException catch (e) {
      throw AuthException(e.message);
    } catch (e) {
      debugPrint('❌ [SupabaseAuthService] signInWithGoogleOAuth failed: $e');
      throw AuthException('Google OAuth failed: $e');
    }
  }

  /// Обновить access token
  Future<TokenResponse> refreshAccessToken({String? refreshToken}) async {
    try {
      final response = await _client.auth.refreshSession(refreshToken);
      final session = response.session;
      if (session == null) {
        throw AuthException('Failed to refresh token');
      }
      return TokenResponse(
        accessToken: session.accessToken,
        userId: session.user.id,
        refreshToken: session.refreshToken,
      );
    } on supabase.AuthException catch (e) {
      throw AuthException(e.message);
    } on AuthException {
      rethrow;
    } catch (e) {
      debugPrint('❌ [SupabaseAuthService] refresh failed: $e');
      throw AuthException('Token refresh failed: $e');
    }
  }

  /// Выход пользователя
  Future<void> logout() async {
    await _client.auth.signOut();
  }
}
