import 'dart:convert';
import '../../../core/api_client.dart';
import '../../../core/api_http_exception.dart';
import '../models/chat_thread.dart';
import '../models/message.dart';
import '../models/chat_mapper.dart';

class ChatApi {
  final _client = ApiClient();

  Future<List<ChatThread>> listThreads({int limit = 50, int offset = 0}) async {
    final uri = _client.uri("/api/v1/chat/threads", {
      "limit": limit,
      "offset": offset,
    });
    final r = await _client.send('GET', uri);
    if (r.statusCode != 200) {
      throw ApiHttpException(
        method: 'GET',
        path: '/api/v1/chat/threads',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
    final body = json.decode(r.body) as Map<String, dynamic>;
    final items = (body["items"] as List?) ?? const [];
    return items
        .map((e) => chatThreadFromApiJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ChatThread> createThread({required String title}) async {
    final r = await _client.send(
      'POST',
      _client.uri("/api/v1/chat/threads"),
      body: {"title": title},
    );
    if (r.statusCode != 201 && r.statusCode != 200) {
      throw ApiHttpException(
        method: 'POST',
        path: '/api/v1/chat/threads',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
    final obj = json.decode(r.body) as Map<String, dynamic>;
    return chatThreadFromApiJson(obj);
  }

  Future<ChatThread> getThread(String threadId) async {
    final r = await _client.send(
      'GET',
      _client.uri("/api/v1/chat/threads/$threadId"),
    );
    if (r.statusCode != 200) {
      throw ApiHttpException(
        method: 'GET',
        path: '/api/v1/chat/threads/$threadId',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
    final obj = json.decode(r.body) as Map<String, dynamic>;
    return chatThreadFromApiJson(obj);
  }

  Future<void> deleteThread(String threadId) async {
    final r = await _client.send(
      'DELETE',
      _client.uri("/api/v1/chat/threads/$threadId"),
    );
    if (r.statusCode != 204 && r.statusCode != 200) {
      throw ApiHttpException(
        method: 'DELETE',
        path: '/api/v1/chat/threads/$threadId',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
  }

  Future<List<Message>> listMessages({
    required String threadId,
    int limit = 100,
    int offset = 0,
  }) async {
    final uri = _client.uri("/api/v1/chat/threads/$threadId/messages", {
      "limit": limit,
      "offset": offset,
    });
    final r = await _client.send('GET', uri);
    if (r.statusCode != 200) {
      throw ApiHttpException(
        method: 'GET',
        path: '/api/v1/chat/threads/$threadId/messages',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
    final body = json.decode(r.body) as Map<String, dynamic>;
    final items = (body["items"] as List?) ?? const [];
    return items
        .map((e) => messageFromApiJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Message> addMessage({
    required String threadId,
    required String role,
    required String content,
  }) async {
    final r = await _client.send(
      'POST',
      _client.uri("/api/v1/chat/threads/$threadId/messages"),
      body: {"role": role, "content": content},
    );
    if (r.statusCode != 201 && r.statusCode != 200) {
      throw ApiHttpException(
        method: 'POST',
        path: '/api/v1/chat/threads/$threadId/messages',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
    final obj = json.decode(r.body) as Map<String, dynamic>;
    return messageFromApiJson(obj);
  }
}
