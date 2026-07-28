import 'dart:io';

class ApiHttpException implements Exception {
  const ApiHttpException({
    required this.method,
    required this.path,
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  final String method;
  final String path;
  final int statusCode;
  final Map<String, String> headers;
  final String body;

  Duration? retryAfter() {
    final value = headers['retry-after'] ?? headers['Retry-After'];
    return parseRetryAfter(value);
  }

  /// Parse a Retry-After header value into a [Duration].
  ///
  /// Supports both delta-seconds ("120") and HTTP-date formats.
  /// Returns null if the value is absent, empty, or unparseable.
  static Duration? parseRetryAfter(String? value) {
    if (value == null || value.isEmpty) return null;

    final seconds = int.tryParse(value.trim());
    if (seconds != null && seconds > 0) {
      return Duration(seconds: seconds);
    }

    try {
      final retryAt = HttpDate.parse(value);
      final delay = retryAt.toUtc().difference(DateTime.now().toUtc());
      if (delay > Duration.zero) return delay;
    } catch (_) {
      return null;
    }

    return null;
  }

  @override
  String toString() => '$method $path failed: $statusCode $body';
}
