import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Session state visible from both Outer and Inner ProviderScope.
///
/// Lives in the Outer (non-rotated) scope so it survives Inner scope
/// key rotation during logout.
class SessionState {
  const SessionState({
    this.userId,
    this.isAuthenticated = false,
    this.logoutInProgress = false,
    this.sessionEpoch = 0,
  });

  final String? userId;
  final bool isAuthenticated;
  final bool logoutInProgress;
  final int sessionEpoch;

  SessionState copyWith({
    String? Function()? userId,
    bool? isAuthenticated,
    bool? logoutInProgress,
    int? sessionEpoch,
  }) {
    return SessionState(
      userId: userId != null ? userId() : this.userId,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      logoutInProgress: logoutInProgress ?? this.logoutInProgress,
      sessionEpoch: sessionEpoch ?? this.sessionEpoch,
    );
  }
}

class SessionScopeNotifier extends Notifier<SessionState> {
  @override
  SessionState build() => const SessionState();

  void login(String userId) {
    state = state.copyWith(
      userId: () => userId,
      isAuthenticated: true,
      logoutInProgress: false,
      sessionEpoch: state.sessionEpoch + 1,
    );
  }

  void beginLogout() {
    state = state.copyWith(logoutInProgress: true);
  }

  void completeLogout() {
    state = state.copyWith(
      userId: () => null,
      isAuthenticated: false,
      logoutInProgress: false,
      sessionEpoch: state.sessionEpoch + 1,
    );
  }

  void updateAuth({required bool isAuthenticated, String? userId}) {
    state = state.copyWith(
      isAuthenticated: isAuthenticated,
      userId: () => userId,
    );
  }
}

final sessionScopeProvider =
    NotifierProvider<SessionScopeNotifier, SessionState>(
  SessionScopeNotifier.new,
);
