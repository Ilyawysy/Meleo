import 'dart:convert';
import 'package:http/http.dart' as http;
import 'env.dart';
import '../features/auth/data/token_manager.dart';

/// Shared HTTP client with automatic 401 retry via token refresh.
class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal();

  final String _base = Env.apiBase;
  static const Duration _defaultRequestTimeout = Duration(seconds: 10);

  Uri uri(String path, [Map<String, dynamic>? q]) =>
      Uri.parse('$_base$path').replace(
        queryParameters: q?.map((k, v) => MapEntry(k, '$v')),
      );

  /// Send an HTTP request with automatic 401 retry.
  ///
  /// Supports GET, POST, PUT, PATCH, DELETE methods.
  /// On 401, force-refreshes the token and retries once.
  Future<http.Response> send(
    String method,
    Uri url, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    var mergedHeaders = await TokenManager.authHeaders;
    if (headers != null) {
      mergedHeaders.addAll(headers);
    }
    final encodedBody = body == null ? null : json.encode(body);

    final effectiveTimeout = timeout ?? _defaultRequestTimeout;
    Future<http.Response> doRequest() {
      switch (method) {
        case 'POST':
          return http
              .post(url, headers: mergedHeaders, body: encodedBody)
              .timeout(effectiveTimeout);
        case 'PUT':
          return http
              .put(url, headers: mergedHeaders, body: encodedBody)
              .timeout(effectiveTimeout);
        case 'PATCH':
          return http
              .patch(url, headers: mergedHeaders, body: encodedBody)
              .timeout(effectiveTimeout);
        case 'DELETE':
          return http
              .delete(url, headers: mergedHeaders)
              .timeout(effectiveTimeout);
        case 'GET':
        default:
          return http
              .get(url, headers: mergedHeaders)
              .timeout(effectiveTimeout);
      }
    }

    var r = await doRequest();

    if (r.statusCode == 401) {
      final refreshed =
          await TokenManager.refreshTokenIfNeeded(forceRefresh: true);
      if (refreshed != null) {
        mergedHeaders = await TokenManager.authHeaders;
        if (headers != null) {
          mergedHeaders.addAll(headers);
        }
        r = await doRequest();
      }
    }

    return r;
  }
}
