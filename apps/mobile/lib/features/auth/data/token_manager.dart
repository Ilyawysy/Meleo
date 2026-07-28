import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'models/token_response.dart';
import 'auth_exception.dart';

class TokenManager {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static const String _tokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _userIdKey = 'user_id';

  // Callback, зарегистрированный снаружи (например, в main.dart).
  // Должен быть установлен до первого вызова refreshTokenIfNeeded().
  static Future<TokenResponse> Function()? onNeedRefresh;

  // Блокировка для предотвращения одновременных обновлений токена
  static Completer<TokenResponse>? _refreshCompleter;
  static bool _authFailureHandled = false;
  static int _sessionEpoch = 0;

  /// Сохранить токен и user_id
  static Future<void> saveToken(TokenResponse tokenResponse) async {
    try {
      await _storage.write(key: _tokenKey, value: tokenResponse.accessToken);
      await _storage.write(key: _userIdKey, value: tokenResponse.userId);

      // Сохраняем refresh token, если он есть
      if (tokenResponse.refreshToken != null) {
        await _storage.write(
          key: _refreshTokenKey,
          value: tokenResponse.refreshToken,
        );
      }

      _sessionEpoch++;
      _authFailureHandled = false;
      debugPrint('Token saved successfully');
    } catch (e) {
      debugPrint('Error saving token: $e');
      throw Exception('Failed to save authentication token');
    }
  }

  /// Получить сохраненный токен
  static Future<String?> get token async {
    return await _storage.read(key: _tokenKey);
  }

  /// Получить сохраненный refresh token
  static Future<String?> get refreshToken async {
    return await _storage.read(key: _refreshTokenKey);
  }

  /// Получить сохраненный user_id
  static Future<String?> get userId async {
    return await _storage.read(key: _userIdKey);
  }

  /// Проверить, авторизован ли пользователь
  ///
  /// Возвращает true если:
  /// - Access token валиден (не истек), ИЛИ
  /// - Access token истек, но есть refresh token для обновления
  ///
  /// Использовать эту функцию для проверки авторизации во всех частях приложения.
  static Future<bool> get isAuthenticated async {
    final token = await TokenManager.token;
    if (token == null || token.isEmpty) {
      return false;
    }
    // Проверяем, не истек ли токен
    try {
      if (JwtDecoder.isExpired(token)) {
        // Токен истек, но пользователь может быть авторизован (если есть refresh token)
        final refreshToken = await TokenManager.refreshToken;
        return refreshToken != null && refreshToken.isNotEmpty;
      }
      return true;
    } catch (e) {
      debugPrint('Error checking token expiration: $e');
      return false;
    }
  }

  /// Очистить токен (logout)
  static Future<void> clearToken() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _userIdKey);
    debugPrint('Token cleared');
  }

  /// Обновить токен с блокировкой для предотвращения concurrent operations
  /// Если токен уже обновляется другим запросом, ждет завершения этого обновления
  /// [forceRefresh] - если true, обновляет токен даже если он не истек локально
  static Future<TokenResponse?> refreshTokenIfNeeded({
    bool forceRefresh = false,
  }) async {
    // Проверяем и устанавливаем блокировку атомарно через _refreshCompleter
    // Если completer уже существует - другой запрос выполняет refresh, ждем его
    if (_refreshCompleter != null) {
      debugPrint(
        '⏳ [TokenManager] Token refresh already in progress, waiting...',
      );
      try {
        return await _refreshCompleter!.future;
      } catch (e) {
        debugPrint('❌ [TokenManager] Error waiting for token refresh: $e');
        return null;
      }
    }

    // Устанавливаем блокировку (completer как lock)
    _refreshCompleter = Completer<TokenResponse>();

    // Проверяем наличие refresh token
    final refreshToken = await TokenManager.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      debugPrint('⚠️ [TokenManager] No refresh token available');
      _refreshCompleter = null;
      return null;
    }

    // Если не принудительное обновление, проверяем, нужен ли refresh
    if (!forceRefresh) {
      final token = await TokenManager.token;
      if (token == null || token.isEmpty) {
        _refreshCompleter = null;
        return null;
      }

      try {
        // Если токен не истек, обновление не нужно
        if (!JwtDecoder.isExpired(token)) {
          debugPrint(
            'ℹ️ [TokenManager] Token is still valid, refresh not needed',
          );
          _refreshCompleter = null;
          return null;
        }
      } catch (e) {
        debugPrint('⚠️ [TokenManager] Error checking token expiration: $e');
        // Если не можем проверить, продолжаем с обновлением
      }
    }

    try {
      debugPrint('🔄 [TokenManager] Starting token refresh...');
      if (onNeedRefresh == null) {
        debugPrint('❌ [TokenManager] onNeedRefresh callback is not set');
        _refreshCompleter!.completeError(
          Exception('TokenManager.onNeedRefresh is not set'),
        );
        return null;
      }
      final newTokenResponse = await onNeedRefresh!();

      _refreshCompleter!.complete(newTokenResponse);
      debugPrint('✅ [TokenManager] Token refreshed successfully');
      return newTokenResponse;
    } catch (e) {
      debugPrint('❌ [TokenManager] Failed to refresh token: $e');
      _refreshCompleter!.completeError(e);
      return null;
    } finally {
      _refreshCompleter = null;
    }
  }

  /// Заголовки для аутентифицированных запросов
  static Future<Map<String, String>> get authHeaders async {
    final token = await TokenManager.token;
    if (token == null || token.isEmpty) {
      return {};
    }

    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  /// Определить, является ли ошибка аутентификационной (401/invalid token)
  static bool isAuthError(Object error) {
    if (error is AuthException) return true;
    final msg = error.toString();
    if (msg.contains('failed: 401')) return true;
    if (msg.contains('Invalid token')) return true;
    if (msg.contains('Token has expired')) return true;
    if (msg.contains('Missing bearer token')) return true;
    return false;
  }

  static Future<void> handleAuthFailure(Object error) async {
    if (!isAuthError(error)) return;
    if (_authFailureHandled) return;
    final epochAtStart = _sessionEpoch;
    _authFailureHandled = true;
    // If a new token was saved while we were processing, abort —
    // the new session is valid, don't wipe its token.
    if (epochAtStart != _sessionEpoch) return;
    await clearToken();
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
  }
}
