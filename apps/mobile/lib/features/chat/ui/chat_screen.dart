import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/chat_commands.dart';
import '../providers/chat_read_provider.dart';
import '../../subscription/providers/subscription_provider.dart';
import 'chat_tab.dart';
import 'chat_thread_selector.dart';

/// Pushable screen wrapping [ChatTab] with providers wired in.
///
/// Opened from places like the statistics page (similar pattern to the
/// help button on the focus room).
class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatState = ref.watch(chatReadProvider);
    final subscription = ref.watch(subscriptionProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      body: ChatTab(
        items: chatState.chatItems,
        isLoading: chatState.agentLoading,
        canSendChat: subscription.canSendChat,
        chatRemaining: subscription.chatRemaining,
        chatLimit: subscription.chatMessagesLimit,
        onSend: (text) {
          ref
              .read(chatCommandsProvider.notifier)
              .sendMessage(text);
        },
        onBack: () => Navigator.of(context).pop(),
        onThreadsTap: () {
          ChatThreadSelector(
            currentThreadId: chatState.currentThreadId,
            onThreadSelected: (id) {
              ref.read(chatCommandsProvider.notifier).selectThread(id);
            },
            onNewThread: () {
              ref.read(chatCommandsProvider.notifier).createNewThread();
            },
          ).showThreadList(context);
        },
      ),
    );
  }
}
