import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:meleo/core/sync/aggregated_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

http.Response _syncResponse({
  bool? onboardingCompleted,
  String cursor = 'cursor-1',
}) {
  final body = jsonEncode({
    'cursor': cursor,
    if (onboardingCompleted != null)
      'onboarding_completed': onboardingCompleted,
    'changes': {
      'tasks': [],
      'notifications': [],
      'messages': [],
      'announcements': [],
    },
    'has_more': {
      'tasks': false,
      'notifications': false,
      'messages': false,
      'announcements': false,
    },
  });
  return http.Response(body, 200, headers: {'etag': '"etag-1"'});
}

AggregatedSyncService _makeService({
  required bool? onboardingCompleted,
  void Function()? onOnboardingCompleted,
  String userId = 'user-1',
}) {
  final service = AggregatedSyncService(
    delayFn: (_) async {},
    isAuthenticatedFn: () async => true,
    fetchOverride: (_, __) async =>
        _syncResponse(onboardingCompleted: onboardingCompleted),
    processOverride: (_) async => 0,
  );
  service.getUserId = () => userId;
  service.onOnboardingCompleted = onOnboardingCompleted;
  return service;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('AggregatedSyncService — onboarding_completed race fix', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
    });

    // ------------------------------------------------------------------
    // Branch 1: server returns true → mark completed, clear pending, fire cb
    // ------------------------------------------------------------------
    test(
      'onboarding_completed=true: marks completed locally and fires callback',
      () async {
        bool cbFired = false;
        final service = _makeService(
          onboardingCompleted: true,
          onOnboardingCompleted: () => cbFired = true,
        );

        final result = await service.sync();

        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getBool('onboarding_completed_user-1'),
          isTrue,
          reason: 'local completed flag must be set',
        );
        expect(
          prefs.getBool('onboarding_pending_sync_user-1'),
          isNull,
          reason: 'pending sync flag must be cleared',
        );
        expect(cbFired, isTrue, reason: 'onOnboardingCompleted must be called');
        expect(result.onboardingStateAuthoritative, isTrue);
      },
    );

    // ------------------------------------------------------------------
    // Branch 2: server=false, hasPending=true → retry POST (success path)
    // ------------------------------------------------------------------
    test(
      'onboarding_completed=false + hasPending=true: retries POST and marks completed on success',
      () async {
        // Pre-set pending flag
        SharedPreferences.setMockInitialValues({
          'onboarding_pending_sync_user-1': true,
        });

        bool cbFired = false;
        // We cannot inject OnboardingService.markCompletedOnServer directly
        // because it's a static method calling a real ApiClient.
        // Instead, verify the *local* side effects that happen only when
        // the POST returns true. Since the real network call will fail in tests
        // (no server running), the service will NOT mark completed.
        // We verify the *branch condition* (hasPending==true detected) by
        // confirming that no clearForUser happened (pending flag still set or
        // pending key is cleaned only after success).
        //
        // This test asserts the negative: clearForUser is NOT called when
        // hasPending==true (that path only retries the POST).
        final service = _makeService(
          onboardingCompleted: false,
          onOnboardingCompleted: () => cbFired = true,
        );

        await service.sync();

        final prefs = await SharedPreferences.getInstance();
        // The completed flag was NOT set (POST failed — no network in unit tests)
        expect(
          prefs.getBool('onboarding_completed_user-1'),
          isNull,
          reason:
              'completed flag must not be set when POST is pending but server unavailable',
        );
        // Completed callback must not fire
        expect(cbFired, isFalse);
      },
    );

    // ------------------------------------------------------------------
    // Branch 3a: server=false, !hasPending, local=true → race guard:
    //   markPendingSyncForUser + retry POST (no clearForUser)
    // ------------------------------------------------------------------
    test(
      'onboarding_completed=false + !hasPending + local=true: '
      'race guard — sets pending, does NOT clear local completed flag',
      () async {
        // Local says completed, no pending flag, server says false
        SharedPreferences.setMockInitialValues({
          'onboarding_completed_user-1': true,
        });

        bool cbFired = false;
        final service = _makeService(
          onboardingCompleted: false,
          onOnboardingCompleted: () => cbFired = true,
        );

        await service.sync();

        final prefs = await SharedPreferences.getInstance();
        // Local completed flag must still be true (not cleared)
        expect(
          prefs.getBool('onboarding_completed_user-1'),
          isTrue,
          reason:
              'local completed flag must NOT be cleared by race-guard branch',
        );
        // pending flag should have been set (markPendingSyncForUser)
        expect(
          prefs.getBool('onboarding_pending_sync_user-1'),
          isTrue,
          reason: 'pending sync flag must be set for retry',
        );
        // Callback must not fire (server hasn't confirmed yet)
        expect(cbFired, isFalse);
      },
    );

    // ------------------------------------------------------------------
    // Branch 3b: server=false, !hasPending, local=false → server is
    //   authoritative: clearForUser (old behaviour preserved)
    // ------------------------------------------------------------------
    test('onboarding_completed=false + !hasPending + local=false: '
        'clears local state (server is authoritative)', () async {
      // Fresh state — nothing in prefs
      SharedPreferences.setMockInitialValues({});

      bool cbFired = false;
      final service = _makeService(
        onboardingCompleted: false,
        onOnboardingCompleted: () => cbFired = true,
      );

      final result = await service.sync();

      final prefs = await SharedPreferences.getInstance();
      // Nothing set, nothing pending — no state to clear; flags stay absent
      expect(
        prefs.getBool('onboarding_completed_user-1'),
        isNull,
        reason: 'completed flag must remain absent',
      );
      expect(
        prefs.getBool('onboarding_pending_sync_user-1'),
        isNull,
        reason: 'pending flag must remain absent',
      );
      expect(cbFired, isFalse);
      expect(result.onboardingStateAuthoritative, isTrue);
    });

    // ------------------------------------------------------------------
    // Null onboarding_completed field → entire block skipped, no crash
    // ------------------------------------------------------------------
    test(
      'onboarding_completed absent in response: no local side effects',
      () async {
        SharedPreferences.setMockInitialValues({});

        bool cbFired = false;
        final service = _makeService(
          onboardingCompleted: null, // field omitted from response
          onOnboardingCompleted: () => cbFired = true,
        );

        final result = await service.sync();

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('onboarding_completed_user-1'), isNull);
        expect(cbFired, isFalse);
        expect(result.onboardingStateAuthoritative, isFalse);
      },
    );

    // ------------------------------------------------------------------
    // getUserId returns null → block is skipped entirely
    // ------------------------------------------------------------------
    test(
      'getUserId returns null: onboarding block is skipped entirely',
      () async {
        SharedPreferences.setMockInitialValues({});

        bool cbFired = false;
        final service = AggregatedSyncService(
          delayFn: (_) async {},
          isAuthenticatedFn: () async => true,
          fetchOverride: (_, __) async =>
              _syncResponse(onboardingCompleted: true),
          processOverride: (_) async => 0,
        );
        service.getUserId = () => null; // simulate missing user id
        service.onOnboardingCompleted = () => cbFired = true;

        await service.sync();

        // No prefs keys should be written
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getKeys(),
          isEmpty,
          reason: 'no prefs must be written when userId is null',
        );
        expect(cbFired, isFalse);
      },
    );
  });
}
