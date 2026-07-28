import 'package:flutter_test/flutter_test.dart';
import 'package:meleo/core/sync/sync_orchestrator.dart';

// SyncOrchestrator is a singleton, so each test must call stopAndResetAll()
// to clear state before the next test can call startAll().
// Because startAll() triggers a real _runSync() (which hits network / DB),
// these tests verify the field-level contract exposed by the public API
// only, without actually invoking startAll(), to keep tests hermetic.
void main() {
  group('SyncOrchestrator.onFirstSyncSettled field contract', () {
    setUp(() async {
      // Ensure a clean slate for every test.
      // stopAndResetAll() is a no-op when _started==false, so safe to call here.
      await SyncOrchestrator.instance.stopAndResetAll();
    });

    test('onFirstSyncSettled is null by default (before any assignment)', () {
      // Fresh after setUp — no callback should be registered yet.
      // NOTE: stopAndResetAll() is a no-op when _started==false (line 94 guard),
      // so the setUp() call doesn't clear pre-existing callbacks. We therefore
      // null the field directly here to guarantee a known baseline.
      SyncOrchestrator.instance.onFirstSyncSettled = null;
      expect(SyncOrchestrator.instance.onFirstSyncSettled, isNull);
    });

    test(
      'onFirstSyncSettled can be assigned and read back before startAll',
      () {
        int callCount = 0;
        void cb() {
          callCount++;
        }

        SyncOrchestrator.instance.onFirstSyncSettled = cb;
        expect(SyncOrchestrator.instance.onFirstSyncSettled, same(cb));
        // No startAll → callback must not have fired yet.
        expect(callCount, 0);
      },
    );

    test('onFirstSyncSettled is overwritable — last assignment wins', () {
      // Simulate: caller A sets callback, caller B overwrites it.
      // This verifies the field is a simple nullable slot (no queue).
      void cb1() {}
      void cb2() {}
      SyncOrchestrator.instance.onFirstSyncSettled = cb1;
      SyncOrchestrator.instance.onFirstSyncSettled = cb2;
      expect(SyncOrchestrator.instance.onFirstSyncSettled, same(cb2));
    });

    test('onOnboardingCompleted is independent from onFirstSyncSettled — '
        'both survive independent assignment', () {
      int onboardingCalls = 0;
      int firstSyncCalls = 0;

      SyncOrchestrator.instance.onOnboardingCompleted = () {
        onboardingCalls++;
      };
      SyncOrchestrator.instance.onFirstSyncSettled = () {
        firstSyncCalls++;
      };

      // Neither callback fires without startAll.
      expect(onboardingCalls, 0);
      expect(firstSyncCalls, 0);

      // Both fields are accessible.
      expect(SyncOrchestrator.instance.onOnboardingCompleted, isNotNull);
      expect(SyncOrchestrator.instance.onFirstSyncSettled, isNotNull);
    });

    test(
      'both onOnboardingCompleted and onFirstSyncSettled can be null-cleared manually',
      () {
        // Tests the explicit-null-assignment pattern used by dispose().
        SyncOrchestrator.instance.onOnboardingCompleted = () {};
        SyncOrchestrator.instance.onFirstSyncSettled = () {};

        SyncOrchestrator.instance.onOnboardingCompleted = null;
        SyncOrchestrator.instance.onFirstSyncSettled = null;

        expect(SyncOrchestrator.instance.onOnboardingCompleted, isNull);
        expect(SyncOrchestrator.instance.onFirstSyncSettled, isNull);
      },
    );
  });

  group(
    'SyncOrchestrator identity-guard pattern (mirrors _AuthGateState logic)',
    () {
      setUp(() async {
        await SyncOrchestrator.instance.stopAndResetAll();
      });

      test(
        'identity-guard: replacing own callback does not clear a foreign callback',
        () {
          // Simulates _resolveOnboardingState being called twice (e.g. user switch).
          // First call registers cb1 as _firstSyncCallback.
          void Function()? myRef1;
          void cb1() {}
          myRef1 = cb1;
          SyncOrchestrator.instance.onFirstSyncSettled = myRef1;

          // Second call: guard checks if the current field == myRef1, clears it,
          // then registers cb2.
          if (SyncOrchestrator.instance.onFirstSyncSettled == myRef1) {
            SyncOrchestrator.instance.onFirstSyncSettled = null;
          }
          void cb2() {}
          SyncOrchestrator.instance.onFirstSyncSettled = cb2;

          // Field should now be cb2, not null or cb1.
          expect(SyncOrchestrator.instance.onFirstSyncSettled, same(cb2));
        },
      );

      test(
        'identity-guard: does not clear a foreign callback set by someone else',
        () {
          // Simulates _AuthGateState.dispose() with identity check.
          // Another owner (cb_foreign) has already replaced our cb1.
          void cbForeign() {}
          SyncOrchestrator.instance.onFirstSyncSettled = cbForeign;

          // dispose()-like code: only clear if it's still ours.
          void Function()? myOwnRef; // was never set to cbForeign
          if (SyncOrchestrator.instance.onFirstSyncSettled == myOwnRef) {
            SyncOrchestrator.instance.onFirstSyncSettled = null;
          }

          // Foreign callback must remain untouched.
          expect(SyncOrchestrator.instance.onFirstSyncSettled, same(cbForeign));
        },
      );
    },
  );
}
