import '../../../core/id_generator.dart';

enum TaskStatus { notDone, done }

class Task {
  final String id;
  final String roomId;
  final String title;
  final String? description;
  final TaskStatus status;
  final int sortOrder;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Task({
    required this.id,
    required this.roomId,
    required this.title,
    this.description,
    this.status = TaskStatus.notDone,
    this.sortOrder = 0,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Task.create({
    required String roomId,
    required String title,
    String? description,
    int sortOrder = 0,
  }) {
    final now = DateTime.now();
    return Task(
      id: generateLocalId(),
      roomId: roomId,
      title: title,
      description: description,
      sortOrder: sortOrder,
      createdAt: now,
      updatedAt: now,
    );
  }

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] as String,
      roomId: json['room_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      status: _parseStatus(json['status'] as String?),
      sortOrder: json['sort_order'] as int? ?? 0,
      completedAt: _parseDate(json['completed_at']),
      createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(json['updated_at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'room_id': roomId,
    'title': title,
    if (description != null) 'description': description,
    'status': _statusToString(status),
    'sort_order': sortOrder,
    if (completedAt != null) 'completed_at': completedAt!.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory Task.fromDb(Map<String, Object?> row) {
    return Task(
      id: row['id'] as String,
      roomId: row['room_id'] as String,
      title: row['title'] as String,
      description: row['description'] as String?,
      status: _parseStatus(row['status'] as String?),
      sortOrder: row['sort_order'] as int? ?? 0,
      completedAt: _parseDate(row['completed_at']),
      createdAt: _parseDate(row['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(row['updated_at']) ?? DateTime.now(),
    );
  }

  Map<String, Object?> toDb() => {
    'id': id,
    'room_id': roomId,
    'title': title,
    'description': description,
    'status': _statusToString(status),
    'sort_order': sortOrder,
    'completed_at': completedAt?.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  Task copyWith({
    String? id,
    String? roomId,
    String? title,
    String? description,
    TaskStatus? status,
    int? sortOrder,
    DateTime? completedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Task(
      id: id ?? this.id,
      roomId: roomId ?? this.roomId,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      sortOrder: sortOrder ?? this.sortOrder,
      completedAt: completedAt ?? this.completedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get isDone => status == TaskStatus.done;

  static TaskStatus _parseStatus(String? value) {
    switch (value) {
      case 'done':
        return TaskStatus.done;
      default:
        return TaskStatus.notDone;
    }
  }

  static String _statusToString(TaskStatus status) {
    switch (status) {
      case TaskStatus.done:
        return 'done';
      case TaskStatus.notDone:
        return 'not_done';
    }
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
