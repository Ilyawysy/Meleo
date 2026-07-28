class Message {
  final String id;
  final String text;
  final bool isMe;
  final DateTime ts;
  final String? threadId;
  final String? remoteId;
  final int order;

  Message({
    required this.id,
    required this.text,
    required this.isMe,
    required this.ts,
    this.threadId,
    this.remoteId,
    this.order = 0,
  });
}
