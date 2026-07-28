import '../../../core/id_generator.dart';

enum FocusRoomType { regular, sprint }

class FocusRoom {
  final String id;
  final String title;
  final String color;
  final FocusRoomType type;
  final bool archived;
  final DateTime? archivedAt;
  final int sortOrder;
  final String? sprintGoal;
  final DateTime? sprintDeadline;
  final int? sprintTotalHours;
  final int? focusDurationMin;
  final int? breakMin;
  final DateTime createdAt;
  final DateTime updatedAt;
  // Computed fields — not stored in DB, populated by aggregation queries
  final int taskCount;
  final int totalFocusSec;
  // Local-only sync field — populated from DB row, not serialized to server
  final String? remoteId;

  const FocusRoom({
    required this.id,
    required this.title,
    required this.color,
    this.type = FocusRoomType.regular,
    this.archived = false,
    this.archivedAt,
    this.sortOrder = 0,
    this.sprintGoal,
    this.sprintDeadline,
    this.sprintTotalHours,
    this.focusDurationMin,
    this.breakMin,
    required this.createdAt,
    required this.updatedAt,
    this.taskCount = 0,
    this.totalFocusSec = 0,
    this.remoteId,
  });

  factory FocusRoom.create({
    required String title,
    String color = '#6366F1',
    int? focusDurationMin,
    int? breakMin,
  }) {
    final now = DateTime.now();
    return FocusRoom(
      id: generateLocalId(),
      title: title,
      color: color,
      focusDurationMin: focusDurationMin,
      breakMin: breakMin,
      createdAt: now,
      updatedAt: now,
    );
  }

  factory FocusRoom.fromJson(Map<String, dynamic> json) {
    return FocusRoom(
      id: json['id'] as String,
      title: json['title'] as String,
      color: json['color'] as String? ?? '#6366F1',
      type: _parseType(json['type'] as String?),
      archived: json['archived'] as bool? ?? false,
      archivedAt: _parseDate(json['archived_at']),
      sortOrder: json['sort_order'] as int? ?? 0,
      sprintGoal: json['sprint_goal'] as String?,
      sprintDeadline: _parseDate(json['sprint_deadline']),
      sprintTotalHours: json['sprint_total_hours'] as int?,
      focusDurationMin: json['focus_duration_min'] as int?,
      breakMin: json['break_min'] as int?,
      createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(json['updated_at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'color': color,
    'type': _typeToString(type),
    'archived': archived,
    if (archivedAt != null) 'archived_at': archivedAt!.toIso8601String(),
    'sort_order': sortOrder,
    if (sprintGoal != null) 'sprint_goal': sprintGoal,
    if (sprintDeadline != null) 'sprint_deadline': sprintDeadline!.toIso8601String(),
    if (sprintTotalHours != null) 'sprint_total_hours': sprintTotalHours,
    if (focusDurationMin != null) 'focus_duration_min': focusDurationMin,
    if (breakMin != null) 'break_min': breakMin,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory FocusRoom.fromDb(Map<String, Object?> row) {
    return FocusRoom(
      id: row['id'] as String,
      title: row['title'] as String,
      color: row['color'] as String? ?? '#6366F1',
      type: _parseType(row['type'] as String?),
      archived: (row['archived'] as int? ?? 0) == 1,
      archivedAt: _parseDate(row['archived_at']),
      sortOrder: row['sort_order'] as int? ?? 0,
      sprintGoal: row['sprint_goal'] as String?,
      sprintDeadline: _parseDate(row['sprint_deadline']),
      sprintTotalHours: row['sprint_total_hours'] as int?,
      focusDurationMin: row['focus_duration_min'] as int?,
      breakMin: row['break_min'] as int?,
      createdAt: _parseDate(row['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(row['updated_at']) ?? DateTime.now(),
      taskCount: row['task_count'] as int? ?? 0,
      totalFocusSec: row['total_focus_sec'] as int? ?? 0,
      remoteId: row['remote_id'] as String?,
    );
  }

  Map<String, Object?> toDb() => {
    'id': id,
    'title': title,
    'color': color,
    'type': _typeToString(type),
    'archived': archived ? 1 : 0,
    'archived_at': archivedAt?.toIso8601String(),
    'sort_order': sortOrder,
    'sprint_goal': sprintGoal,
    'sprint_deadline': sprintDeadline?.toIso8601String(),
    'sprint_total_hours': sprintTotalHours,
    'focus_duration_min': focusDurationMin,
    'break_min': breakMin,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  FocusRoom copyWith({
    String? id,
    String? title,
    String? color,
    FocusRoomType? type,
    bool? archived,
    DateTime? archivedAt,
    int? sortOrder,
    String? sprintGoal,
    DateTime? sprintDeadline,
    int? sprintTotalHours,
    int? focusDurationMin,
    int? breakMin,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? taskCount,
    int? totalFocusSec,
    String? remoteId,
  }) {
    return FocusRoom(
      id: id ?? this.id,
      title: title ?? this.title,
      color: color ?? this.color,
      type: type ?? this.type,
      archived: archived ?? this.archived,
      archivedAt: archivedAt ?? this.archivedAt,
      sortOrder: sortOrder ?? this.sortOrder,
      sprintGoal: sprintGoal ?? this.sprintGoal,
      sprintDeadline: sprintDeadline ?? this.sprintDeadline,
      sprintTotalHours: sprintTotalHours ?? this.sprintTotalHours,
      focusDurationMin: focusDurationMin ?? this.focusDurationMin,
      breakMin: breakMin ?? this.breakMin,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      taskCount: taskCount ?? this.taskCount,
      totalFocusSec: totalFocusSec ?? this.totalFocusSec,
      remoteId: remoteId ?? this.remoteId,
    );
  }

  static FocusRoomType _parseType(String? value) {
    switch (value) {
      case 'sprint':
        return FocusRoomType.sprint;
      default:
        return FocusRoomType.regular;
    }
  }

  static String _typeToString(FocusRoomType type) {
    switch (type) {
      case FocusRoomType.sprint:
        return 'sprint';
      case FocusRoomType.regular:
        return 'regular';
    }
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
