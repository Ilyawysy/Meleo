import 'package:flutter/foundation.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

import 'env.dart';

/// Product analytics service using PostHog.
///
/// Tracks user behavior, screen views, and custom events.
/// - Privacy: IP tracking disabled, no PII sent
/// - Auto screen tracking via NavigatorObserver
/// - User identity linked to Supabase user_id after login
class AnalyticsService {
  static final AnalyticsService _instance = AnalyticsService._internal();
  factory AnalyticsService() => _instance;
  AnalyticsService._internal();

  bool _initialized = false;

  /// Returns true if PostHog should be enabled.
  /// Enabled when POSTHOG_API_KEY is set (works in all build modes).
  static bool get isEnabled => Env.posthogApiKey.isNotEmpty;

  /// Initialize PostHog with project configuration.
  /// Call this once during app startup in main.dart.
  Future<void> initialize() async {
    if (!isEnabled || _initialized) return;

    try {
      final config = PostHogConfig(Env.posthogApiKey);
      config.host = Env.posthogHost;
      config.captureApplicationLifecycleEvents = false;
      config.debug = false;

      await Posthog().setup(config);

      _initialized = true;

      await trackEvent('app_opened', properties: {
        'environment': Env.environment,
        'platform': defaultTargetPlatform.toString(),
      });
    } catch (e, stackTrace) {
      debugPrint('POSTHOG: init failed: $e\n$stackTrace');
    }
  }

  /// Identify user after successful login.
  /// Links all future events to this user_id.
  ///
  /// [userId] - Supabase user UUID
  /// [properties] - Optional user properties (e.g., email, name, plan_type)
  ///                WARNING: Do NOT send PII (email, phone) for privacy
  Future<void> identifyUser(
    String userId, {
    Map<String, dynamic>? properties,
  }) async {
    if (!isEnabled || !_initialized) return;

    try {
      await Posthog().identify(
        userId: userId,
        userProperties: properties?.cast<String, Object>(),
      );
    } catch (e, stackTrace) {
      debugPrint('POSTHOG: identifyUser failed: $e\n$stackTrace');
    }
  }

  /// Reset user identity after logout.
  /// Creates a new anonymous session.
  Future<void> resetUser() async {
    if (!isEnabled || !_initialized) return;

    try {
      await Posthog().reset();
    } catch (e) {
      debugPrint('POSTHOG: resetUser failed: $e');
    }
  }

  /// Track a custom event.
  ///
  /// [eventName] - Event name (e.g., 'task_created', 'focus_session_started')
  /// [properties] - Optional event metadata
  ///
  /// Example:
  /// ```dart
  /// AnalyticsService().trackEvent('task_created', properties: {
  ///   'task_id': '123',
  ///   'title': 'My task',
  /// });
  /// ```
  Future<void> trackEvent(
    String eventName, {
    Map<String, dynamic>? properties,
  }) async {
    if (!isEnabled || !_initialized) return;

    try {
      await Posthog().capture(
        eventName: eventName,
        properties: properties?.cast<String, Object>(),
      );
    } catch (e, stackTrace) {
      debugPrint('POSTHOG: trackEvent failed: $e\n$stackTrace');
    }
  }

  /// Track screen view manually (optional).
  /// Auto screen tracking is handled by PosthogObserver in MaterialApp.
  ///
  /// Use this only if you need custom screen tracking logic.
  Future<void> trackScreen(
    String screenName, {
    Map<String, dynamic>? properties,
  }) async {
    if (!isEnabled || !_initialized) return;

    try {
      await Posthog().screen(
        screenName: screenName,
        properties: properties?.cast<String, Object>(),
      );

    } catch (e) {
      debugPrint('POSTHOG: trackScreen failed: $e');
    }
  }
}
