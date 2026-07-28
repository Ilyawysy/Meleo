import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../core/api_client.dart';
import '../models/announcement.dart';

class AnnouncementApi {
  final _client = ApiClient();

  /// Get all unread announcements for the current user
  Future<List<Announcement>> getUnread() async {
    final r = await _client.send('GET', _client.uri("/api/v1/announcements/unread"));

    if (r.statusCode == 401) {
      debugPrint('❌ [AnnouncementApi] Failed to refresh token');
    }

    if (r.statusCode != 200) {
      throw Exception(
          "GET /announcements/unread failed: ${r.statusCode} ${r.body}");
    }

    final List<dynamic> body = json.decode(r.body) as List<dynamic>;
    return body
        .map((e) => Announcement.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Mark announcement as read for the current user
  Future<void> markRead(String announcementId) async {
    final r = await _client.send(
      'POST',
      _client.uri("/api/v1/announcements/$announcementId/mark-read"),
    );

    if (r.statusCode == 401) {
      debugPrint('❌ [AnnouncementApi] Failed to refresh token');
    }

    if (r.statusCode != 204) {
      throw Exception(
          "POST /announcements/$announcementId/mark-read failed: ${r.statusCode} ${r.body}");
    }
  }
}
