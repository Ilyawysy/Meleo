enum HelpActionType { focus, exit }

class HelpAction {
  final String label;
  final HelpActionType type;
  final int? durationMinutes;

  const HelpAction({
    required this.label,
    required this.type,
    this.durationMinutes,
  });

  factory HelpAction.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? 'exit';
    return HelpAction(
      label: json['label'] as String? ?? '',
      type: typeStr == 'focus' ? HelpActionType.focus : HelpActionType.exit,
      durationMinutes: json['duration_minutes'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'type': type == HelpActionType.focus ? 'focus' : 'exit',
        if (durationMinutes != null) 'duration_minutes': durationMinutes,
      };
}

class HelpQuestion {
  final String question;
  final List<String> options;

  const HelpQuestion({required this.question, required this.options});

  factory HelpQuestion.fromJson(Map<String, dynamic> json) {
    return HelpQuestion(
      question: json['question'] as String? ?? '',
      options: (json['options'] as List<dynamic>? ?? []).cast<String>(),
    );
  }
}

class HelpCard {
  final List<String> messages;
  final HelpAction action;
  final List<String> feedbackOptions;

  const HelpCard({
    required this.messages,
    required this.action,
    required this.feedbackOptions,
  });

  factory HelpCard.fromJson(Map<String, dynamic> json) {
    return HelpCard(
      messages: (json['messages'] as List<dynamic>? ?? []).cast<String>(),
      action: HelpAction.fromJson(json['action'] as Map<String, dynamic>? ?? {}),
      feedbackOptions:
          (json['feedback_options'] as List<dynamic>? ?? []).cast<String>(),
    );
  }
}

class HelpCardPrev {
  final List<String> messages;
  final String actionLabel;

  const HelpCardPrev({required this.messages, required this.actionLabel});

  factory HelpCardPrev.fromCard(HelpCard card) {
    return HelpCardPrev(
      messages: card.messages,
      actionLabel: card.action.label,
    );
  }

  Map<String, dynamic> toJson() => {
        'messages': messages,
        'action_label': actionLabel,
      };
}
