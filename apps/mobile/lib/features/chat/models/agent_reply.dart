import 'chat_widget.dart';

class AgentReply {
  final String text;
  final List<ChatWidget> widgets;

  AgentReply({required this.text, required this.widgets});
}
