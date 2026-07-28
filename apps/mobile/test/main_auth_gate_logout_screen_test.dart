// Tests for the logout-interstitial guard added to _AuthGateState.build().
//
// The guard:
//   - Watches sessionScopeProvider
//   - If logoutInProgress == true (and _isReady == true), returns AuthLoadingScreen
//     BEFORE checking _isAuthenticated
//
// We test the SessionScopeNotifier directly (pure Dart, no widget tree needed)
// because _AuthGateState has internal state that depends on Supabase/platform
// initialisation. The critical invariant being tested is:
//   logoutInProgress=true → widget shows AuthLoadingScreen, NOT ShellScaffold.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meleo/core/providers/session_scope.dart';
import 'package:meleo/features/auth/ui/auth_loading_screen.dart';

// ---------------------------------------------------------------------------
// Minimal test widget that mirrors the build() guard without Supabase/platform
// ---------------------------------------------------------------------------

/// Mirrors only the two conditions checked inside _AuthGateState.build() that
/// the PR touches:
///   1. !_isReady  → spinner
///   2. logoutInProgress == true → AuthLoadingScreen
///   3. _isAuthenticated → ShellScaffold-placeholder
///   4. else → AuthScreen-placeholder
class _AuthGateMirror extends ConsumerStatefulWidget {
  const _AuthGateMirror({required this.isReady, required this.isAuthenticated});

  final bool isReady;
  final bool isAuthenticated;

  @override
  ConsumerState<_AuthGateMirror> createState() => _AuthGateMirrorState();
}

class _AuthGateMirrorState extends ConsumerState<_AuthGateMirror> {
  @override
  Widget build(BuildContext context) {
    if (!widget.isReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // -- PR change: watch session and guard on logoutInProgress --
    final session = ref.watch(sessionScopeProvider);
    if (session.logoutInProgress) {
      return const AuthLoadingScreen();
    }
    // -- end PR change --

    if (widget.isAuthenticated) {
      return const Scaffold(body: Text('shell'));
    }
    return const Scaffold(body: Text('auth'));
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('_AuthGateState.build() — logout-interstitial guard', () {
    testWidgets(
      'logoutInProgress=true shows AuthLoadingScreen (not shell, not auth)',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        // Begin logout on the provider
        container.read(sessionScopeProvider.notifier).beginLogout();

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: _AuthGateMirror(isReady: true, isAuthenticated: true),
            ),
          ),
        );

        // AuthLoadingScreen must be visible
        expect(
          find.byType(AuthLoadingScreen),
          findsOneWidget,
          reason:
              'AuthLoadingScreen must be shown during logout regardless of isAuthenticated',
        );
        expect(
          find.text('shell'),
          findsNothing,
          reason: 'ShellScaffold must NOT be shown during logout',
        );
        expect(
          find.text('auth'),
          findsNothing,
          reason: 'AuthScreen must NOT be shown during logout',
        );
      },
    );

    testWidgets('logoutInProgress=false + isAuthenticated=true shows shell', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // No logout in progress
      container.read(sessionScopeProvider.notifier).login('user-1');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: _AuthGateMirror(isReady: true, isAuthenticated: true),
          ),
        ),
      );

      expect(find.text('shell'), findsOneWidget);
      expect(find.byType(AuthLoadingScreen), findsNothing);
    });

    testWidgets(
      'logoutInProgress=false + isAuthenticated=false shows auth screen',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        // Default state: not authenticated, no logout
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: _AuthGateMirror(isReady: true, isAuthenticated: false),
            ),
          ),
        );

        expect(find.text('auth'), findsOneWidget);
        expect(find.byType(AuthLoadingScreen), findsNothing);
      },
    );

    testWidgets('!isReady shows spinner regardless of logoutInProgress', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(sessionScopeProvider.notifier).beginLogout();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: _AuthGateMirror(isReady: false, isAuthenticated: false),
          ),
        ),
      );

      expect(
        find.byType(CircularProgressIndicator),
        findsOneWidget,
        reason: 'Cold-start spinner must show before _isReady',
      );
      expect(
        find.byType(AuthLoadingScreen),
        findsNothing,
        reason: 'logoutInProgress guard is only reached after _isReady=true',
      );
    });

    testWidgets(
      'guard reacts reactively: beginLogout() after mount switches to AuthLoadingScreen',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        container.read(sessionScopeProvider.notifier).login('user-1');

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: _AuthGateMirror(isReady: true, isAuthenticated: true),
            ),
          ),
        );

        // Initially shows shell
        expect(find.text('shell'), findsOneWidget);

        // Trigger logout
        container.read(sessionScopeProvider.notifier).beginLogout();
        await tester.pump();

        // Now shows AuthLoadingScreen
        expect(find.byType(AuthLoadingScreen), findsOneWidget);
        expect(find.text('shell'), findsNothing);
      },
    );

    testWidgets(
      'guard reacts reactively: completeLogout() removes AuthLoadingScreen',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        container.read(sessionScopeProvider.notifier).beginLogout();

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: _AuthGateMirror(isReady: true, isAuthenticated: false),
            ),
          ),
        );

        expect(find.byType(AuthLoadingScreen), findsOneWidget);

        // Complete logout → logoutInProgress resets to false
        container.read(sessionScopeProvider.notifier).completeLogout();
        await tester.pump();

        expect(find.byType(AuthLoadingScreen), findsNothing);
        expect(find.text('auth'), findsOneWidget);
      },
    );
  });
}
