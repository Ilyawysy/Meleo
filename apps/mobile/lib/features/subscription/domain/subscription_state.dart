enum SubscriptionTier { free, pro }

class SubscriptionState {
  final SubscriptionTier tier;
  final int chatMessagesUsed;
  final int? chatMessagesLimit;

  const SubscriptionState({
    required this.tier,
    required this.chatMessagesUsed,
    this.chatMessagesLimit,
  });

  factory SubscriptionState.free() => const SubscriptionState(
        tier: SubscriptionTier.free,
        chatMessagesUsed: 0,
        chatMessagesLimit: 5,
      );

  factory SubscriptionState.fromJson(Map<String, dynamic> json) {
    return SubscriptionState(
      tier: json['tier'] == 'pro' ? SubscriptionTier.pro : SubscriptionTier.free,
      chatMessagesUsed: (json['chat_messages_used'] as num?)?.toInt() ?? 0,
      chatMessagesLimit: (json['chat_messages_limit'] as num?)?.toInt(),
    );
  }

  bool get canSendChat {
    if (tier == SubscriptionTier.pro) return true;
    if (chatMessagesLimit == null) return true;
    return chatMessagesUsed < chatMessagesLimit!;
  }

  int? get chatRemaining {
    if (chatMessagesLimit == null) return null;
    final remaining = chatMessagesLimit! - chatMessagesUsed;
    return remaining > 0 ? remaining : 0;
  }

  bool get isPro => tier == SubscriptionTier.pro;

  SubscriptionState copyWithIncrementedChat() {
    return SubscriptionState(
      tier: tier,
      chatMessagesUsed: chatMessagesUsed + 1,
      chatMessagesLimit: chatMessagesLimit,
    );
  }
}
