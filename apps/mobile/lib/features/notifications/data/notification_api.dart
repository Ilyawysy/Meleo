import 'dart:convert';
import '../../../core/api_client.dart';
import '../../../core/api_http_exception.dart';
import '../models/notification.dart';
import '../models/notification_mapper.dart';

class NotificationApi {
  final _client = ApiClient();
  static const int defaultLimit = 50;

  Future<List<Notification>> list({int limit = NotificationApi.defaultLimit, int offset = 0}) async {
    final uri = _client.uri("/api/v1/notifications/", {"limit": limit, "offset": offset});
    final r = await _client.send('GET', uri);
    if (r.statusCode != 200) {
      throw ApiHttpException(
        method: 'GET',
        path: '/api/v1/notifications/',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
    final body = json.decode(r.body) as Map<String, dynamic>;
    final items = (body["items"] as List?) ?? const [];
    return items
        .map((e) => notificationFromApiJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Notification> create({
    required String title,
    required DateTime time,
    String recurrence = "none",
  }) async {
    final r = await _client.send(
      'POST',
      _client.uri("/api/v1/notifications/"),
      body: {
        "title": title,
        "time": time.toIso8601String(),
        "recurrence": recurrence,
      },
    );
    if (r.statusCode != 201 && r.statusCode != 200) {
      throw ApiHttpException(
        method: 'POST',
        path: '/api/v1/notifications/',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
    final obj = json.decode(r.body) as Map<String, dynamic>;
    return notificationFromApiJson(obj);
  }

  Future<Notification> update(
    String id, {
    String? title,
    DateTime? time,
    String? recurrence,
  }) async {
    final r = await _client.send(
      'PATCH',
      _client.uri("/api/v1/notifications/$id"),
      body: {
        if (title != null) "title": title,
        if (time != null) "time": time.toIso8601String(),
        if (recurrence != null) "recurrence": recurrence,
      },
    );
    if (r.statusCode != 200) {
      throw ApiHttpException(
        method: 'PATCH',
        path: '/api/v1/notifications/$id',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
    final obj = json.decode(r.body) as Map<String, dynamic>;
    return notificationFromApiJson(obj);
  }

  Future<void> delete(String id) async {
    final r = await _client.send('DELETE', _client.uri("/api/v1/notifications/$id"));
    if (r.statusCode != 204) {
      throw ApiHttpException(
        method: 'DELETE',
        path: '/api/v1/notifications/$id',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
  }
}
