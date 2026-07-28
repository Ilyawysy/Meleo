import 'package:flutter/foundation.dart';

/// Developer announcement model (from backend developer_announcements table)
@immutable
class Announcement {
  final String id;
  final String title;
  final String message;
  final DateTime createdAt;

  const Announcement({
    required this.id,
    required this.title,
    required this.message,
    required this.createdAt,
  });

  factory Announcement.fromJson(Map<String, dynamic> json) {
    return Announcement(
      id: json['id'] as String,
      title: json['title'] as String,
      message: json['message'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  @override
  String toString() => 'Announcement(id: $id, title: $title)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Announcement && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
