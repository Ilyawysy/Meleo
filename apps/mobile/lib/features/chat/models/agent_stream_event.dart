/// A single event from the SSE agent stream.
class AgentStreamEvent {
  final String type; // "token", "tool_start", "tool_result", "done", "error"
  final String? content; // for "token"
  final String? name; // for "tool_start", "tool_result"
  final Map<String, dynamic>? args; // for "tool_start"
  final bool? ok; // for "tool_result"
  final Map<String, dynamic>? result; // for "done" — full result payload
  final String? message; // for "error"

  AgentStreamEvent({
    required this.type,
    this.content,
    this.name,
    this.args,
    this.ok,
    this.result,
    this.message,
  });

  factory AgentStreamEvent.fromJson(Map<String, dynamic> json) {
    return AgentStreamEvent(
      type: json['type'] as String? ?? 'unknown',
      content: json['content'] as String?,
      name: json['name'] as String?,
      args: json['args'] is Map ? Map<String, dynamic>.from(json['args'] as Map) : null,
      ok: json['ok'] as bool?,
      result: json['result'] is Map ? Map<String, dynamic>.from(json['result'] as Map) : null,
      message: json['message'] as String?,
    );
  }

  bool get isToken => type == 'token';
  bool get isToolStart => type == 'tool_start';
  bool get isToolResult => type == 'tool_result';
  bool get isDone => type == 'done';
  bool get isError => type == 'error';
}
