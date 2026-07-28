import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Controls the Inner ProviderScope key rotation.
///
/// When [rotationKey] changes, the Inner ProviderScope is rebuilt,
/// destroying all domain providers while preserving the Outer scope
/// (SessionScope, AppScopeController itself, LogoutController).
class AppScopeController extends Notifier<int> {
  @override
  int build() => 0;

  /// Rotate the Inner scope key — triggers full rebuild of domain providers.
  void rotate() {
    state = state + 1;
  }
}

final appScopeControllerProvider =
    NotifierProvider<AppScopeController, int>(
  AppScopeController.new,
);
