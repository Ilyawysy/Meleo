class ChecklistItem {
  final String id;
  final String taskId;
  final String title;
  final bool isDone;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ChecklistItem({
    required this.id,
    required this.taskId,
    required this.title,
    this.isDone = false,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  ChecklistItem copyWith({
    String? id,
    String? taskId,
    String? title,
    bool? isDone,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ChecklistItem(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      title: title ?? this.title,
      isDone: isDone ?? this.isDone,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
