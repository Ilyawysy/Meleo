class ChatThread {
  final String id;
  final String title;
  final String? remoteId;
  final DateTime createdAt;
  final DateTime updatedAt;

  ChatThread({
    required this.id,
    required this.title,
    this.remoteId,
    required this.createdAt,
    required this.updatedAt,
  });
}

