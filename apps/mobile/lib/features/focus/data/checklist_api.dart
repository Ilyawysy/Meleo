import 'dart:convert';

import '../../../core/api_client.dart';
import '../../../core/api_http_exception.dart';
import '../models/checklist_item.dart';

class FocusChecklistApi {
  final _client = ApiClient();

  Future<List<ChecklistItem>> list(String taskId) async {
    final r = await _client.send(
      'GET',
      _client.uri('/api/v1/tasks/$taskId/checklist'),
    );
    if (r.statusCode != 200) {
      throw ApiHttpException(
        method: 'GET',
        path: '/api/v1/tasks/$taskId/checklist',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
    final items = json.decode(r.body) as List<dynamic>;
    return items.map((e) => _fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<ChecklistItem> create(
    String taskId, {
    required String title,
    int sortOrder = 0,
  }) async {
    final r = await _client.send(
      'POST',
      _client.uri('/api/v1/tasks/$taskId/checklist'),
      body: {'title': title, 'sort_order': sortOrder},
    );
    if (r.statusCode != 201 && r.statusCode != 200) {
      throw ApiHttpException(
        method: 'POST',
        path: '/api/v1/tasks/$taskId/checklist',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
    return _fromJson(json.decode(r.body) as Map<String, dynamic>);
  }

  Future<ChecklistItem> update(
    String taskId,
    String itemId, {
    String? title,
    bool? isDone,
    int? sortOrder,
  }) async {
    final body = <String, dynamic>{};
    if (title != null) body['title'] = title;
    if (isDone != null) body['is_done'] = isDone;
    if (sortOrder != null) body['sort_order'] = sortOrder;
    final r = await _client.send(
      'PATCH',
      _client.uri('/api/v1/tasks/$taskId/checklist/$itemId'),
      body: body,
    );
    if (r.statusCode != 200) {
      throw ApiHttpException(
        method: 'PATCH',
        path: '/api/v1/tasks/$taskId/checklist/$itemId',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
    return _fromJson(json.decode(r.body) as Map<String, dynamic>);
  }

  Future<void> delete(String taskId, String itemId) async {
    final r = await _client.send(
      'DELETE',
      _client.uri('/api/v1/tasks/$taskId/checklist/$itemId'),
    );
    if (r.statusCode != 204) {
      throw ApiHttpException(
        method: 'DELETE',
        path: '/api/v1/tasks/$taskId/checklist/$itemId',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
  }

  static ChecklistItem _fromJson(Map<String, dynamic> j) {
    return ChecklistItem(
      id: j['id'] as String,
      taskId: j['task_id'] as String,
      title: j['title'] as String,
      isDone: j['is_done'] as bool? ?? false,
      sortOrder: j['sort_order'] as int? ?? 0,
      createdAt: DateTime.parse(j['created_at'] as String),
      updatedAt: DateTime.parse(j['updated_at'] as String),
    );
  }
}
