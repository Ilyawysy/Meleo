class DomainVersions {
  const DomainVersions({
    required this.tasks,
    required this.notifications,
    required this.messages,
    required this.focus,
    required this.rhythm,
  });

  static const zero = DomainVersions(
    tasks: 0,
    notifications: 0,
    messages: 0,
    focus: 0,
    rhythm: 0,
  );

  final int tasks;
  final int notifications;
  final int messages;
  final int focus;
  final int rhythm;

  /// Per-domain max of this and other.
  DomainVersions maxWith(DomainVersions other) => DomainVersions(
        tasks: tasks > other.tasks ? tasks : other.tasks,
        notifications:
            notifications > other.notifications ? notifications : other.notifications,
        messages: messages > other.messages ? messages : other.messages,
        focus: focus > other.focus ? focus : other.focus,
        rhythm: rhythm > other.rhythm ? rhythm : other.rhythm,
      );

  /// Promote applied version to target for domains where has_more is false.
  DomainVersions applyCompleted(
    DomainVersions target,
    Map<String, dynamic> hasMore,
  ) =>
      DomainVersions(
        tasks: hasMore['tasks'] == true ? tasks : target.tasks,
        notifications:
            hasMore['notifications'] == true ? notifications : target.notifications,
        messages: hasMore['messages'] == true ? messages : target.messages,
        focus: hasMore['focus_sessions'] == true ? focus : target.focus,
        rhythm: hasMore['rhythm_templates'] == true ? rhythm : target.rhythm,
      );

  factory DomainVersions.fromJson(Map<String, dynamic> json) {
    return DomainVersions(
      tasks: (json['tasks'] as num?)?.toInt() ?? 0,
      notifications: (json['notifications'] as num?)?.toInt() ?? 0,
      messages: (json['messages'] as num?)?.toInt() ?? 0,
      focus: (json['focus'] as num?)?.toInt() ?? 0,
      rhythm: (json['rhythm'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DomainVersions &&
          tasks == other.tasks &&
          notifications == other.notifications &&
          messages == other.messages &&
          focus == other.focus &&
          rhythm == other.rhythm;

  @override
  int get hashCode => Object.hash(tasks, notifications, messages, focus, rhythm);
}
