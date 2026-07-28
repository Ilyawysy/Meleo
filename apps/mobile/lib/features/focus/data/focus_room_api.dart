import 'dart:convert';

import '../../../core/api_client.dart';
import '../../../core/api_http_exception.dart';
import '../models/focus_room.dart';

class FocusRoomApi {
  final _client = ApiClient();

  Future<List<FocusRoom>> listRooms({bool archived = false}) async {
    final r = await _client.send(
      'GET',
      _client.uri('/api/v1/rooms', {'archived': archived}),
    );
    if (r.statusCode != 200) {
      throw ApiHttpException(
        method: 'GET',
        path: '/api/v1/rooms',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
    final list = json.decode(r.body) as List<dynamic>;
    return list
        .map((e) => FocusRoom.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<FocusRoom> createRoom(FocusRoom room) async {
    final r = await _client.send(
      'POST',
      _client.uri('/api/v1/rooms'),
      body: {
        'title': room.title,
        'color': room.color,
        'type': room.type.name,
        'sort_order': room.sortOrder,
        if (room.sprintGoal != null) 'sprint_goal': room.sprintGoal,
        if (room.sprintDeadline != null)
          'sprint_deadline': room.sprintDeadline!.toIso8601String(),
        if (room.sprintTotalHours != null) 'sprint_total_hours': room.sprintTotalHours,
        if (room.focusDurationMin != null) 'focus_duration_min': room.focusDurationMin,
        if (room.breakMin != null) 'break_min': room.breakMin,
      },
    );
    if (r.statusCode != 201 && r.statusCode != 200) {
      throw ApiHttpException(
        method: 'POST',
        path: '/api/v1/rooms',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
    return FocusRoom.fromJson(json.decode(r.body) as Map<String, dynamic>);
  }

  Future<FocusRoom> updateRoom(String id, Map<String, dynamic> patch) async {
    final r = await _client.send(
      'PATCH',
      _client.uri('/api/v1/rooms/$id'),
      body: patch,
    );
    if (r.statusCode != 200) {
      throw ApiHttpException(
        method: 'PATCH',
        path: '/api/v1/rooms/$id',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
    return FocusRoom.fromJson(json.decode(r.body) as Map<String, dynamic>);
  }

  Future<FocusRoom> archiveRoom(String id) async {
    final r = await _client.send(
      'POST',
      _client.uri('/api/v1/rooms/$id/archive'),
    );
    if (r.statusCode != 200) {
      throw ApiHttpException(
        method: 'POST',
        path: '/api/v1/rooms/$id/archive',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
    return FocusRoom.fromJson(json.decode(r.body) as Map<String, dynamic>);
  }

  Future<FocusRoom> unarchiveRoom(String id) async {
    final r = await _client.send(
      'POST',
      _client.uri('/api/v1/rooms/$id/unarchive'),
    );
    if (r.statusCode != 200) {
      throw ApiHttpException(
        method: 'POST',
        path: '/api/v1/rooms/$id/unarchive',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
    return FocusRoom.fromJson(json.decode(r.body) as Map<String, dynamic>);
  }

  Future<void> setActiveRoom(String? remoteRoomId) async {
    final r = await _client.send(
      'PUT',
      _client.uri('/api/v1/rooms/active'),
      body: {'room_id': remoteRoomId},
    );
    if (r.statusCode != 200) {
      throw ApiHttpException(
        method: 'PUT',
        path: '/api/v1/rooms/active',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
  }

  Future<int> getRoomFocusTime(String id) async {
    final r = await _client.send(
      'GET',
      _client.uri('/api/v1/rooms/$id/focus-time'),
    );
    if (r.statusCode != 200) {
      throw ApiHttpException(
        method: 'GET',
        path: '/api/v1/rooms/$id/focus-time',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
    final obj = json.decode(r.body) as Map<String, dynamic>;
    return (obj['total_active_elapsed_sec'] as int?) ?? 0;
  }
}
