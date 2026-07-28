import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meleo/core/providers/app_scope_controller.dart';
import 'package:meleo/core/providers/inner_scope.dart';
import 'package:meleo/core/providers/session_scope.dart';

/// A provider that watches [domainScopeToken] to live in the Inner scope.
/// When the Inner scope rotates, this provider is destroyed and recreated.
final _innerCounterProvider = StateProvider<int>(
  (ref) {
    ref.watch(domainScopeToken);
    return 0;
  },
  dependencies: [domainScopeToken],
);

void main() {
  group('AppScopeController', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('initial key is 0', () {
      expect(container.read(appScopeControllerProvider), 0);
    });

    test('rotate increments key', () {
      container.read(appScopeControllerProvider.notifier).rotate();
      expect(container.read(appScopeControllerProvider), 1);

      container.read(appScopeControllerProvider.notifier).rotate();
      expect(container.read(appScopeControllerProvider), 2);
    });
  });

  group('InnerScope key rotation widget test', () {
    testWidgets(
      'rotation rebuilds Inner scope while preserving Outer SessionScope',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            child: InnerScope(
              child: MaterialApp(
                home: Consumer(
                  builder: (context, ref, _) {
                    final session = ref.watch(sessionScopeProvider);
                    final innerCount = ref.watch(_innerCounterProvider);
                    return Column(
                      children: [
                        Text('epoch:${session.sessionEpoch}'),
                        Text('inner:$innerCount'),
                        ElevatedButton(
                          key: const Key('inc'),
                          onPressed: () =>
                              ref.read(_innerCounterProvider.notifier).state++,
                          child: const Text('Inc'),
                        ),
                        ElevatedButton(
                          key: const Key('rotate'),
                          onPressed: () => ref
                              .read(appScopeControllerProvider.notifier)
                              .rotate(),
                          child: const Text('Rotate'),
                        ),
                        ElevatedButton(
                          key: const Key('login'),
                          onPressed: () => ref
                              .read(sessionScopeProvider.notifier)
                              .login('user-1'),
                          child: const Text('Login'),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );

        // Initial state
        expect(find.text('epoch:0'), findsOneWidget);
        expect(find.text('inner:0'), findsOneWidget);

        // Login — sets epoch to 1 in Outer scope
        await tester.tap(find.byKey(const Key('login')));
        await tester.pumpAndSettle();
        expect(find.text('epoch:1'), findsOneWidget);

        // Increment inner counter
        await tester.tap(find.byKey(const Key('inc')));
        await tester.pumpAndSettle();
        expect(find.text('inner:1'), findsOneWidget);

        // Rotate Inner scope — inner counter resets, epoch stays
        await tester.tap(find.byKey(const Key('rotate')));
        await tester.pumpAndSettle();
        expect(find.text('inner:0'), findsOneWidget); // reset by scope rotation
        expect(find.text('epoch:1'), findsOneWidget); // preserved in Outer
      },
    );
  });
}
