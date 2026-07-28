import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/inner_scope.dart';
import '../../../core/providers/session_scope.dart';
import '../data/chat_db.dart';
import '../models/message.dart';
import '../models/chat_item.dart';
import '../models/chat_widget.dart';

/// Immutable view-state for the Chat domain.
class ChatState {
  final String? currentThreadId;
  final List<Message> messages;
  final List<ChatItem> chatItems;
  final List<ChatWidgetEntry> chatWidgets;
  final bool agentLoading;
  final int chatsCount;

  const ChatState({
    this.currentThreadId,
    this.messages = const [],
    this.chatItems = const [],
    this.chatWidgets = const [],
    this.agentLoading = false,
    this.chatsCount = 0,
  });

  ChatState copyWith({
    String? Function()? currentThreadId,
    List<Message>? messages,
    List<ChatItem>? chatItems,
    List<ChatWidgetEntry>? chatWidgets,
    bool? agentLoading,
    int? chatsCount,
  }) {
    return ChatState(
      currentThreadId: currentThreadId != null
          ? currentThreadId()
          : this.currentThreadId,
      messages: messages ?? this.messages,
      chatItems: chatItems ?? this.chatItems,
      chatWidgets: chatWidgets ?? this.chatWidgets,
      agentLoading: agentLoading ?? this.agentLoading,
      chatsCount: chatsCount ?? this.chatsCount,
    );
  }
}

/// Reactive read provider for Chat domain.
///
/// Holds the current thread's messages, computed chat items, widget entries,
/// agent loading flag, and thread count. Session-guarded.
class ChatReadNotifier extends Notifier<ChatState> {
  @override
  ChatState build() {
    ref.watch(domainScopeToken);

    final session = ref.watch(sessionScopeProvider);
    if (!session.isAuthenticated || session.logoutInProgress) {
      return const ChatState();
    }

    return const ChatState();
  }

  /// Build ChatItem list from messages + widget entries.
  static List<ChatItem> buildChatItems(
    List<Message> messages,
    List<ChatWidgetEntry> chatWidgets,
  ) {
    final items = <ChatItem>[];
    final widgetMap = <String, List<ChatWidget>>{};
    for (final entry in chatWidgets) {
      widgetMap.putIfAbsent(entry.afterMessageId, () => []).add(entry.widget);
    }
    for (final message in messages) {
      items.add(ChatItem.message(message));
      final widgets = widgetMap[message.id];
      if (widgets != null) {
        for (final widget in widgets) {
          items.add(ChatItem.widget(widget));
        }
      }
    }
    return items;
  }

  /// Update state with new messages (recomputes chatItems).
  void setMessages(List<Message> messages) {
    final items = buildChatItems(messages, state.chatWidgets);
    state = state.copyWith(messages: messages, chatItems: items);
  }

  /// Set current thread, messages, and reset widgets.
  void setThread(String? threadId, List<Message> messages) {
    final widgets = <ChatWidgetEntry>[];
    final items = buildChatItems(messages, widgets);
    state = state.copyWith(
      currentThreadId: () => threadId,
      messages: messages,
      chatWidgets: widgets,
      chatItems: items,
    );
  }

  /// Update the text of the last message in the list (used for streaming).
  void updateLastMessageText(String text) {
    final msgs = state.messages;
    if (msgs.isEmpty) return;
    final last = msgs.last;
    final updated = Message(
      id: last.id,
      text: text,
      isMe: last.isMe,
      ts: last.ts,
      threadId: last.threadId,
      remoteId: last.remoteId,
      order: last.order,
    );
    final newMsgs = [...msgs.sublist(0, msgs.length - 1), updated];
    final items = buildChatItems(newMsgs, state.chatWidgets);
    state = state.copyWith(messages: newMsgs, chatItems: items);
  }

  /// Set agent loading flag.
  void setAgentLoading(bool loading) {
    state = state.copyWith(agentLoading: loading);
  }

  /// Add widget entries and recompute chat items.
  void addWidgets(List<ChatWidgetEntry> entries) {
    final newWidgets = [...state.chatWidgets, ...entries];
    final items = buildChatItems(state.messages, newWidgets);
    state = state.copyWith(chatWidgets: newWidgets, chatItems: items);
  }

  /// Set chats count.
  void setChatsCount(int count) {
    state = state.copyWith(chatsCount: count);
  }

  /// Refresh current thread's messages from local DB.
  /// Read-only — does NOT call scheduleSync().
  Future<void> refresh() async {
    final session = ref.read(sessionScopeProvider);
    if (!session.isAuthenticated || session.logoutInProgress) {
      state = const ChatState();
      return;
    }
    final threadId = state.currentThreadId;
    if (threadId == null) return;
    try {
      final messages = await ChatDb().listMessages(threadId: threadId);
      setMessages(messages);
    } catch (e) {
      debugPrint('[ChatReadNotifier] Failed to refresh: $e');
    }
  }

  /// Refresh chats count from DB.
  Future<void> refreshChatsCount() async {
    try {
      final threads = await ChatDb().listThreads(limit: 1000);
      setChatsCount(threads.length);
    } catch (e) {
      debugPrint('[ChatReadNotifier] Failed to refresh chats count: $e');
    }
  }
}

final chatReadProvider = NotifierProvider<ChatReadNotifier, ChatState>(
  ChatReadNotifier.new,
  dependencies: [domainScopeToken],
);
