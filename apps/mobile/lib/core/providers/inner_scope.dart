import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_scope_controller.dart';

/// Token that scopes domain providers to the Inner ProviderScope.
///
/// Domain providers must `ref.watch(domainScopeToken)` so that they
/// live in the Inner container and get destroyed on key rotation.
/// The token value equals the current [AppScopeController] rotation key.
final domainScopeToken = Provider<int>((ref) {
  throw UnimplementedError(
    'domainScopeToken must be overridden in InnerScope',
  );
});

/// Widget that creates a rotatable Inner ProviderScope.
///
/// When [AppScopeController.rotate()] is called (e.g. during logout),
/// the key changes, destroying all domain-level providers inside this scope
/// while keeping the Outer scope (SessionScope, LogoutController) intact.
///
/// Domain providers that watch [domainScopeToken] are scoped to this
/// container and will be reset on rotation.
class InnerScope extends ConsumerWidget {
  const InnerScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rotationKey = ref.watch(appScopeControllerProvider);
    return ProviderScope(
      key: ValueKey('inner_scope_$rotationKey'),
      overrides: [
        domainScopeToken.overrideWithValue(rotationKey),
      ],
      child: child,
    );
  }
}
