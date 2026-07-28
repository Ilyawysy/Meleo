import 'chat_thread.dart';
import 'message.dart';

DateTime? _dt(String? iso) => iso == null ? null : DateTime.parse(iso);

/// Convert JSON from API to ChatThread model
ChatThread chatThreadFromApiJson(Map<String, dynamic> j) {
  return ChatThread(
    id: j['id'] as String,
    title: j['title'] as String,
    remoteId: j['id'] as String, // API возвращает UUID как id
    createdAt: _dt(j['created_at'] as String?) ?? DateTime.now(),
    updatedAt: _dt(j['updated_at'] as String?) ?? DateTime.now(),
  );
}

/// Convert JSON from API to Message model
Message messageFromApiJson(Map<String, dynamic> j) {
  final role = j['role'] as String? ?? 'user';
  return Message(
    id: j['id'] as String,
    text: j['content'] as String,
    isMe: role == 'user',
    ts: _dt(j['created_at'] as String?) ?? DateTime.now(),
    threadId: j['thread_id'] as String?,
    remoteId: j['id'] as String,
    order: (j['order'] as int?) ?? 0,
  );
}
