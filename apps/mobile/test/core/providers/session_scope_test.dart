import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meleo/core/providers/session_scope.dart';

void main() {
  group('SessionScope', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state is unauthenticated', () {
      final state = container.read(sessionScopeProvider);
      expect(state.userId, isNull);
      expect(state.isAuthenticated, isFalse);
      expect(state.logoutInProgress, isFalse);
      expect(state.sessionEpoch, 0);
    });

    test('login sets userId, isAuthenticated and increments epoch', () {
      container.read(sessionScopeProvider.notifier).login('user-123');
      final state = container.read(sessionScopeProvider);

      expect(state.userId, 'user-123');
      expect(state.isAuthenticated, isTrue);
      expect(state.logoutInProgress, isFalse);
      expect(state.sessionEpoch, 1);
    });

    test('beginLogout sets logoutInProgress without clearing userId', () {
      container.read(sessionScopeProvider.notifier).login('user-123');
      container.read(sessionScopeProvider.notifier).beginLogout();
      final state = container.read(sessionScopeProvider);

      expect(state.userId, 'user-123');
      expect(state.isAuthenticated, isTrue);
      expect(state.logoutInProgress, isTrue);
      expect(state.sessionEpoch, 1);
    });

    test('completeLogout clears state and increments epoch', () {
      container.read(sessionScopeProvider.notifier).login('user-123');
      container.read(sessionScopeProvider.notifier).beginLogout();
      container.read(sessionScopeProvider.notifier).completeLogout();
      final state = container.read(sessionScopeProvider);

      expect(state.userId, isNull);
      expect(state.isAuthenticated, isFalse);
      expect(state.logoutInProgress, isFalse);
      expect(state.sessionEpoch, 2); // login +1, completeLogout +1
    });

    test('full login-logout-login cycle produces correct epochs', () {
      final notifier = container.read(sessionScopeProvider.notifier);

      // First login
      notifier.login('user-A');
      expect(container.read(sessionScopeProvider).sessionEpoch, 1);

      // Logout
      notifier.beginLogout();
      notifier.completeLogout();
      expect(container.read(sessionScopeProvider).sessionEpoch, 2);

      // Second login as different user
      notifier.login('user-B');
      final state = container.read(sessionScopeProvider);
      expect(state.userId, 'user-B');
      expect(state.isAuthenticated, isTrue);
      expect(state.sessionEpoch, 3);
    });

    test('updateAuth sets auth state without changing epoch', () {
      container
          .read(sessionScopeProvider.notifier)
          .updateAuth(isAuthenticated: true, userId: 'user-X');
      final state = container.read(sessionScopeProvider);

      expect(state.userId, 'user-X');
      expect(state.isAuthenticated, isTrue);
      expect(state.sessionEpoch, 0); // unchanged
    });
  });
}
