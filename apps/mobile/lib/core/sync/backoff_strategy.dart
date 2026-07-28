import 'dart:math';

/// Exponential backoff with jitter for sync error handling.
///
/// Delay = min(2^failureCount * 2s, 5 min) +/- 20% jitter.
/// Prevents thundering-herd when the server is under pressure.
class BackoffStrategy {
  int _failureCount = 0;
  static const _baseDelay = Duration(seconds: 2);
  static const _maxDelay = Duration(minutes: 5);
  static const _jitterFactor = 0.2; // +/- 20%

  int get failureCount => _failureCount;

  Duration getNextDelay() {
    if (_failureCount == 0) return Duration.zero;

    // Exponential: 2^n seconds (2s, 4s, 8s...), capped at 5 minutes.
    final exponentialMs =
        _baseDelay.inMilliseconds * (1 << min(_failureCount - 1, 10));
    final cappedMs = min(exponentialMs, _maxDelay.inMilliseconds);

    // Jitter +/- 20%
    final jitterRange = cappedMs * _jitterFactor;
    final jitterMs = Random().nextDouble() * jitterRange * 2 - jitterRange;
    final finalMs = (cappedMs + jitterMs).toInt();

    return Duration(milliseconds: max(0, finalMs));
  }

  void onSuccess() {
    _failureCount = 0;
  }

  void onFailure() {
    _failureCount++;
  }

  void reset() {
    _failureCount = 0;
  }
}
