import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/concurrency/domain_operation_queue.dart';
import '../../../core/id_generator.dart';
import '../../../core/providers/inner_scope.dart';
import '../../../core/providers/session_scope.dart';
import '../../notifications/providers/notifications_read_provider.dart';
import '../agent_service.dart' show AgentRateLimitException, AgentService;
import '../data/chat_db.dart';
import '../data/chat_sync_service.dart';
import '../models/message.dart';
import 'chat_read_provider.dart';

/// Write commands for Chat domain.
///
/// Operations are serialized per-domain via [DomainOperationQueue].
/// Each write updates local DB, then refreshes the read provider.
class ChatCommands extends Notifier<void> {
  final _queue = DomainOperationQueue();
  final _db = ChatDb();
  final _agentService = AgentService();

  @override
  void build() {
    ref.watch(domainScopeToken);
  }

  bool _shouldAbort() {
    final session = ref.read(sessionScopeProvider);
    return !session.isAuthenticated || session.logoutInProgress;
  }

  ChatReadNotifier get _read => ref.read(chatReadProvider.notifier);

  /// Initialize chat: load first thread from local DB.
  /// Full sync (pull+push) is handled by SyncOrchestrator at app start/resume.
  Future<void> initChatThread() async {
    if (_shouldAbort()) return;
    await _queue.run(() async {
      try {
        final threads = await _db.listThreads(limit: 1);
        if (threads.isNotEmpty) {
          await _loadThreadInternal(threads.first.id);
        } else {
          _read.setThread(null, []);
        }
        await _refreshChatsCount();
      } catch (e) {
        debugPrint('[ChatCommands] Error initializing chat thread: $e');
        _read.setThread(null, []);
      }
    });
  }

  /// Create a new chat thread. Empty by design — UI shows the prompts/empty
  /// state until the user sends the first message.
  Future<void> createNewThread() async {
    if (_shouldAbort()) return;
    await _queue.run(() async {
      try {
        final thread = await _db.createThread(title: 'Новый чат');
        _read.setThread(thread.id, []);
        await _refreshChatsCount();
        ChatSyncService.instance.scheduleSync();
      } catch (e) {
        debugPrint('[ChatCommands] Error creating new thread: $e');
      }
    });
  }

  /// Load a thread's messages from DB and pull from server.
  Future<void> loadThread(String threadId) async {
    if (_shouldAbort()) return;
    await _queue.run(() async {
      await _loadThreadInternal(threadId);
    });
  }

  Future<void> _loadThreadInternal(String threadId) async {
    try {
      final messages = await _db.listMessages(threadId: threadId);
      _read.setThread(threadId, messages);
    } catch (e) {
      debugPrint('[ChatCommands] Error loading thread: $e');
    }
  }

  /// Select a thread (or create new if null).
  Future<void> selectThread(String? threadId) async {
    if (threadId == null) {
      await createNewThread();
    } else {
      await loadThread(threadId);
    }
  }

  /// Send a message to the agent.
  Future<void> sendMessage(String content) async {
    if (_shouldAbort()) return;
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;

    // Ensure a thread exists
    final chatState = ref.read(chatReadProvider);
    var threadId = chatState.currentThreadId;
    if (threadId == null) {
      await createNewThread();
      threadId = ref.read(chatReadProvider).currentThreadId;
      if (threadId == null) return;
    }

    final tid = threadId;
    await _queue.run(() async {
      // Save user message
      await _db.createMessage(
        threadId: tid,
        text: trimmed,
        isMe: true,
      );

      // Reload all messages to ensure order
      final allMessages = await _db.listMessages(threadId: tid);
      _read.setMessages(allMessages);
      _read.setAgentLoading(true);

      ChatSyncService.instance.scheduleSync();

      try {
        // Build history for agent
        final currentMessages = ref.read(chatReadProvider).messages;
        final history = currentMessages
            .map(
              (m) => {
                'role': m.isMe ? 'user' : 'assistant',
                'content': m.text,
              },
            )
            .toList();

        // Create a placeholder assistant message for streaming
        final placeholderMsg = Message(
          id: '${generateLocalId()}_streaming',
          text: '',
          isMe: false,
          ts: DateTime.now(),
          threadId: tid,
        );
        final msgsWithPlaceholder = [...ref.read(chatReadProvider).messages, placeholderMsg];
        _read.setMessages(msgsWithPlaceholder);

        // Stream tokens from agent
        var streamedText = '';

        await for (final event in _agentService.sendMessageStream(
          trimmed,
          history: history,
        )) {
          if (_shouldAbort()) break;

          if (event.isToken && event.content != null) {
            streamedText += event.content!;
            _read.updateLastMessageText(streamedText);
          } else if (event.isError) {
            if (streamedText.isEmpty) {
              streamedText = event.message ?? 'Ошибка при получении ответа';
              _read.updateLastMessageText(streamedText);
            }
          }
          // tool_start / tool_result / done — UI shows agent is working (loading stays true)
        }

        // Persist the final text to DB
        final finalText = streamedText.isNotEmpty
            ? streamedText
            : 'Нет ответа от агента';

        await _db.createMessage(
          threadId: tid,
          text: finalText,
          isMe: false,
        );

        // Reload messages from DB (replaces streaming placeholder with real message)
        final updatedMessages = await _db.listMessages(threadId: tid);
        _read.setMessages(updatedMessages);
        _read.setAgentLoading(false);

        ChatSyncService.instance.scheduleSync();

        // Refresh notifications (agent may have modified them)
        ref.read(notificationsReadProvider.notifier).refresh();
      } catch (e, stackTrace) {
        debugPrint('[ChatCommands] Error sending message: $e\n$stackTrace');

        // User-friendly error text based on exception type
        final String errorText;
        if (e is AgentRateLimitException) {
          errorText = 'Слишком частые сообщения. Подождите немного и попробуйте снова.';
        } else {
          errorText = 'Не удалось получить ответ. Попробуйте ещё раз.';
        }

        final errorMsg = Message(
          id: '${generateLocalId()}_error',
          text: errorText,
          isMe: false,
          ts: DateTime.now(),
        );
        final currentMessages = ref.read(chatReadProvider).messages;
        _read.setMessages([...currentMessages, errorMsg]);
        _read.setAgentLoading(false);
      }
    });
  }

  Future<void> _refreshChatsCount() async {
    await _read.refreshChatsCount();
  }
}

final chatCommandsProvider = NotifierProvider<ChatCommands, void>(
  ChatCommands.new,
  dependencies: [
    domainScopeToken,
    chatReadProvider,
    notificationsReadProvider,
  ],
);
