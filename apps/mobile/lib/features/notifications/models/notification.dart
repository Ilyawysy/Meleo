// lib/features/notifications/models/notification.dart
import 'package:flutter/material.dart';
import '../../../core/models/recurrence.dart';
import '../../../core/id_generator.dart';

class Notification {
  final String id;
  final String title;
  final DateTime time;
  final Recurrence recurrence;
  final bool sent;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Notification({
    required this.id,
    required this.title,
    required this.time,
    this.recurrence = Recurrence.none,
    this.sent = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Notification.newNotification(String title, DateTime time, {Recurrence recurrence = Recurrence.none}) {
    final now = DateTime.now();
    return Notification(
      id: generateLocalId(),
      title: title.trim(),
      time: time,
      recurrence: recurrence,
      sent: false,
      createdAt: now,
      updatedAt: now,
    );
  }

  Notification copyWith({
    String? id,
    String? title,
    DateTime? time,
    Recurrence? recurrence,
    bool? sent,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Notification(
      id: id ?? this.id,
      title: title ?? this.title,
      time: time ?? this.time,
      recurrence: recurrence ?? this.recurrence,
      sent: sent ?? this.sent,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Удобные геттеры для фильтров
  bool get isToday => DateUtils.isSameDay(time, DateTime.now());

  bool get isTomorrow {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    return DateUtils.isSameDay(time, tomorrow);
  }

  bool get isPast => time.isBefore(DateTime.now());
}
