class ChatWidget {
  final String type;
  final Map<String, dynamic> data;

  ChatWidget({required this.type, required this.data});

  factory ChatWidget.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? 'unknown';
    return ChatWidget(type: type, data: json);
  }
}

class ChatWidgetEntry {
  final String afterMessageId;
  final ChatWidget widget;

  ChatWidgetEntry({required this.afterMessageId, required this.widget});
}
