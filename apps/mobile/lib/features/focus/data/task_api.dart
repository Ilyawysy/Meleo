import 'dart:convert';

import '../../../core/api_client.dart';
import '../../../core/api_http_exception.dart';
import '../models/task.dart';

class FocusTaskApi {
  final _client = ApiClient();

  Future<List<Task>> listForRoom(String roomId) async {
    final r = await _client.send(
      'GET',
      _client.uri('/api/v1/rooms/$roomId/tasks'),
    );
    if (r.statusCode != 200) {
      throw ApiHttpException(
        method: 'GET',
        path: '/api/v1/rooms/$roomId/tasks',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
    final list = json.decode(r.body) as List<dynamic>;
    return list
        .map((e) => Task.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Task> createInRoom(String roomId, Task task) async {
    final r = await _client.send(
      'POST',
      _client.uri('/api/v1/rooms/$roomId/tasks'),
      body: {
        'title': task.title,
        if (task.description != null && task.description!.isNotEmpty)
          'description': task.description,
        'sort_order': task.sortOrder,
      },
    );
    if (r.statusCode != 201 && r.statusCode != 200) {
      throw ApiHttpException(
        method: 'POST',
        path: '/api/v1/rooms/$roomId/tasks',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
    return Task.fromJson(json.decode(r.body) as Map<String, dynamic>);
  }

  Future<Task> updateTask(String id, Map<String, dynamic> patch) async {
    final r = await _client.send(
      'PATCH',
      _client.uri('/api/v1/tasks/$id'),
      body: patch,
    );
    if (r.statusCode != 200) {
      throw ApiHttpException(
        method: 'PATCH',
        path: '/api/v1/tasks/$id',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
    return Task.fromJson(json.decode(r.body) as Map<String, dynamic>);
  }

  Future<void> deleteTask(String id) async {
    final r = await _client.send(
      'DELETE',
      _client.uri('/api/v1/tasks/$id'),
    );
    if (r.statusCode != 204) {
      throw ApiHttpException(
        method: 'DELETE',
        path: '/api/v1/tasks/$id',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
  }
}
