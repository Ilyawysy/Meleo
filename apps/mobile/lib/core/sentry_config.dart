import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'env.dart';

// Export SentryLevel for use in other files
export 'package:sentry_flutter/sentry_flutter.dart' show SentryLevel;

class SentryConfig {
  // App version - update this from pubspec.yaml
  static const String appVersion = '1.0.0';
  static const String buildNumber = '1';

  /// Returns the appropriate Sentry DSN based on ENVIRONMENT variable.
  /// - ENVIRONMENT=prod → SENTRY_DSN_PROD (mobile-prod project)
  /// - ENVIRONMENT=dev  → SENTRY_DSN_DEV (mobile-dev project)
  static String getDsn() => Env.isProd ? Env.sentryDsnProd : Env.sentryDsnDev;

  /// Returns true if Sentry should be enabled.
  /// Enable only in release/profile builds (NOT in debug hot-reload).
  /// - Debug mode (flutter run) → Sentry OFF
  /// - Dev profile/release builds → Sentry ON with DEV DSN
  /// - Prod release builds → Sentry ON with PROD DSN
  static bool shouldEnable() {
    final dsn = getDsn();
    // Enable in release or profile mode (not debug)
    final enabled = (kReleaseMode || kProfileMode) && dsn.isNotEmpty;
    return enabled;
  }

  /// Configures Sentry options based on environment (dev vs prod).
  static void configureOptions(SentryFlutterOptions options) {
    options.dsn = getDsn();
    options.environment = Env.isProd ? 'production' : 'development';

    // Release tag: app_version + build_number
    options.release = '$appVersion+$buildNumber';

    // PII settings
    options.sendDefaultPii = false;

    // Data scrubbing
    options.beforeSend = _beforeSend;
    options.beforeBreadcrumb = (breadcrumb, hint) =>
        breadcrumb != null ? _filterBreadcrumb(breadcrumb) : null;

    // Breadcrumbs limit
    options.maxBreadcrumbs = 100;

    // Auto session tracking
    options.enableAutoSessionTracking = true;
    // Note: sessionTrackingIntervalMillis removed in newer Sentry versions

    // Attach stack traces
    options.attachStacktrace = true;

    // Performance monitoring (APM) - different for dev/prod
    if (Env.isProd) {
      // PROD: low sampling to protect quotas
      options.tracesSampleRate = 0.01; // 1% of transactions
      // ignore: experimental_member_use
      options.profilesSampleRate = 0.0; // profiling OFF
      options.enableAutoPerformanceTracing = true;
    } else {
      // DEV: full sampling for testing
      options.tracesSampleRate = 1.0; // 100% of transactions
      // ignore: experimental_member_use
      options.profilesSampleRate = 1.0; // profiling ON (or 0.0 if not needed)
      options.enableAutoPerformanceTracing = true;
    }

    // Session replay: OFF for both (enable carefully later if needed)
    // options.experimental.replay.sessionSampleRate = 0.0;
    // options.experimental.replay.onErrorSampleRate = 0.0;

    // SDK debug logging
    options.debug = !Env.isProd; // verbose in dev, quiet in prod
  }

  /// Data scrubbing callback - removes/masks sensitive data before sending to Sentry.
  /// Filters:
  /// - Tokens (JWT, Bearer, access_token, refresh_token)
  /// - Emails
  /// - Note/task content (title, description, message text)
  /// - URL query params
  /// - Auth headers
  static SentryEvent? _beforeSend(SentryEvent event, Hint hint) {
    // Filter breadcrumbs
    final filteredBreadcrumbs = event.breadcrumbs?.map((breadcrumb) {
      return _filterBreadcrumb(breadcrumb);
    }).toList();

    // Filter contexts (contexts is non-nullable in current Sentry SDK)
    final filteredContexts = Contexts.fromJson(
      Map<String, dynamic>.from(event.contexts.toJson())
        ..removeWhere((key, value) => _isSensitiveKey(key)),
    );

    // Filter extra data
    // ignore: deprecated_member_use
    var filteredExtra = event.extra;
    if (filteredExtra != null) {
      filteredExtra = Map<String, dynamic>.from(filteredExtra);
      for (final key in filteredExtra.keys.toList()) {
        if (_isSensitiveKey(key)) {
          filteredExtra[key] = '[FILTERED]';
        } else if (filteredExtra[key] is String) {
          filteredExtra[key] = _maskSensitiveStrings(
            filteredExtra[key] as String,
          );
        }
      }
    }

    // Filter exception messages
    var filteredExceptions = event.exceptions;
    if (filteredExceptions != null) {
      filteredExceptions = filteredExceptions.map((exception) {
        var filteredValue = exception.value;
        if (filteredValue != null) {
          filteredValue = _maskSensitiveStrings(filteredValue);
        }
        exception.value = filteredValue;
        return exception;
      }).toList();
    }

    // Filter request data (URL query params, headers)
    var filteredRequest = event.request;
    if (filteredRequest != null) {
      // Remove query params from URL
      var filteredUrl = filteredRequest.url;
      if (filteredUrl != null && filteredUrl.contains('?')) {
        filteredUrl = '${filteredUrl.split('?')[0]}?[FILTERED]';
      }

      // Filter headers (headers is non-nullable in current Sentry SDK)
      final filteredHeaders = Map<String, String>.from(filteredRequest.headers);
      for (final key in filteredHeaders.keys.toList()) {
        if (_isSensitiveKey(key)) {
          filteredHeaders[key] = '[FILTERED]';
        }
      }

      filteredRequest.url = filteredUrl;
      filteredRequest.headers = filteredHeaders;
    }

    event.breadcrumbs = filteredBreadcrumbs;
    event.contexts = filteredContexts;
    // ignore: deprecated_member_use
    event.extra = filteredExtra;
    event.exceptions = filteredExceptions;
    event.request = filteredRequest;
    return event;
  }

  /// Filter individual breadcrumb
  static Breadcrumb _filterBreadcrumb(Breadcrumb breadcrumb) {
    var filteredData = breadcrumb.data;
    if (filteredData != null) {
      filteredData = Map<String, dynamic>.from(filteredData);
      for (final key in filteredData.keys.toList()) {
        if (_isSensitiveKey(key)) {
          filteredData[key] = '[FILTERED]';
        } else if (filteredData[key] is String) {
          filteredData[key] = _maskSensitiveStrings(
            filteredData[key] as String,
          );
        }
      }
    }

    // Filter message text
    var filteredMessage = breadcrumb.message;
    if (filteredMessage != null) {
      filteredMessage = _maskSensitiveStrings(filteredMessage);
    }

    breadcrumb.data = filteredData;
    breadcrumb.message = filteredMessage;
    return breadcrumb;
  }

  /// Check if key is sensitive (contains tokens, emails, passwords, etc.)
  static bool _isSensitiveKey(String key) {
    final lowerKey = key.toLowerCase();
    const sensitiveKeys = [
      'password',
      'token',
      'access_token',
      'refresh_token',
      'id_token',
      'authorization',
      'bearer',
      'api_key',
      'secret',
      'supabase_anon_key',
      'email',
      'title',
      'description',
      'message',
      'content',
      'text',
      'body',
      'note',
      'task',
    ];
    return sensitiveKeys.any((sensitive) => lowerKey.contains(sensitive));
  }

  /// Mask sensitive strings (JWT tokens, emails, etc.)
  static String _maskSensitiveStrings(String text) {
    var masked = text;

    // Filter JWT tokens (header.payload.signature pattern)
    masked = masked.replaceAllMapped(
      RegExp(r'eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'),
      (_) => '[JWT_FILTERED]',
    );

    // Filter Bearer tokens
    masked = masked.replaceAllMapped(
      RegExp(r'Bearer\s+[A-Za-z0-9._-]+', caseSensitive: false),
      (_) => 'Bearer [FILTERED]',
    );

    // Filter emails
    masked = masked.replaceAllMapped(
      RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b'),
      (_) => '[EMAIL_FILTERED]',
    );

    // Filter URL query params
    masked = masked.replaceAllMapped(
      RegExp(r'\?[^\s]+'),
      (_) => '?[PARAMS_FILTERED]',
    );

    return masked;
  }

  /// Sets user context in Sentry.
  /// Call this after successful authentication.
  /// User ID is sent directly (not hashed) for easy user lookup in Sentry.
  static Future<void> setUser(String userId) async {
    if (!shouldEnable()) return;

    await Sentry.configureScope((scope) {
      scope.setUser(SentryUser(id: userId));
    });
  }

  /// Clears user context in Sentry.
  /// Call this after logout.
  static Future<void> clearUser() async {
    if (!shouldEnable()) return;

    await Sentry.configureScope((scope) {
      scope.setUser(null);
    });
  }

  /// Adds a breadcrumb to Sentry.
  /// In PROD: only critical breadcrumbs (navigation, focus sessions, sync, critical network).
  /// In DEV: more detailed breadcrumbs allowed.
  static void addBreadcrumb({
    required String message,
    required String category,
    SentryLevel level = SentryLevel.info,
    Map<String, dynamic>? data,
    bool criticalOnly = false, // Set to true for prod-critical breadcrumbs
  }) {
    if (!shouldEnable()) return;

    // In PROD: skip non-critical breadcrumbs
    if (Env.isProd && !criticalOnly && !_isCriticalCategory(category)) {
      return;
    }

    Sentry.addBreadcrumb(
      Breadcrumb(
        message: message,
        category: category,
        level: level,
        data: data,
        timestamp: DateTime.now().toUtc(),
      ),
    );
  }

  /// Check if breadcrumb category is critical (should be logged in prod)
  static bool _isCriticalCategory(String category) {
    const criticalCategories = [
      'navigation',
      'focus',
      'sync',
      'network.critical',
      'auth',
      'error',
    ];
    return criticalCategories.any((critical) => category.startsWith(critical));
  }

  /// Captures an exception manually.
  static Future<void> captureException(
    dynamic exception,
    dynamic stackTrace, {
    String? hint,
  }) async {
    if (!shouldEnable()) return;

    await Sentry.captureException(
      exception,
      stackTrace: stackTrace,
      hint: hint != null ? Hint.withMap({'hint': hint}) : null,
    );
  }
}
