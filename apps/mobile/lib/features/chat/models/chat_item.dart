import 'message.dart';
import 'chat_widget.dart';

class ChatItem {
  final Message? message;
  final ChatWidget? widget;

  ChatItem.message(this.message) : widget = null;
  ChatItem.widget(this.widget) : message = null;

  bool get isMessage => message != null;
}
