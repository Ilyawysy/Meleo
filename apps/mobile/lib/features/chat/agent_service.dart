import 'dart:async' show Stream, TimeoutException;
import 'dart:convert';
import 'dart:developer' show log;

import 'package:http/http.dart' as http;

import '../../core/api_client.dart';
import '../../core/env.dart';
import '../auth/data/token_manager.dart';
import '../chat/models/agent_stream_event.dart';

/// Thrown when agent submit is rate-limited.
class AgentRateLimitException implements Exception {
  @override
  String toString() => 'Rate limit exceeded';
}

class AgentService {
  final String baseUrl;

  AgentService({String? agentUrl}) : baseUrl = agentUrl ?? '${Env.apiBase}/api/v1/agent';

  /// Send message via SSE streaming endpoint (POST /chat.stream).
  /// Yields [AgentStreamEvent] as they arrive from the server.
  Stream<AgentStreamEvent> sendMessageStream(
    String content, {
    List<Map<String, String>>? history,
  }) async* {
    log('[AgentService] sendMessageStream starting...');

    final messageHistory =
        history ??
        [
          {'role': 'user', 'content': content},
        ];

    final client = http.Client();
    try {
      final uri = ApiClient().uri('/api/v1/agent/chat.stream');
      final headers = await TokenManager.authHeaders;
      headers['Accept'] = 'text/event-stream';
      headers['Content-Type'] = 'application/json';

      final request = http.Request('POST', uri);
      request.headers.addAll(headers);
      request.body = jsonEncode({
        'history': messageHistory,
        'variant': 'focus_stats',
      });

      final streamedResponse = await client.send(request).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException('Connection timeout', const Duration(seconds: 30)),
      );

      if (streamedResponse.statusCode == 429) {
        yield AgentStreamEvent(type: 'error', message: 'Rate limit exceeded');
        return;
      }

      if (streamedResponse.statusCode != 200) {
        yield AgentStreamEvent(
          type: 'error',
          message: 'HTTP ${streamedResponse.statusCode}',
        );
        return;
      }

      // Parse SSE stream: lines starting with "data: " separated by blank lines
      var buffer = '';
      const inactivityLimit = Duration(seconds: 120);
      await for (final bytes in streamedResponse.stream.timeout(
        inactivityLimit,
        onTimeout: (sink) {
          log('[AgentService] SSE stream inactivity timeout (${inactivityLimit.inSeconds}s)');
          sink.close();
        },
      )) {
        buffer += utf8.decode(bytes);

        // Process complete SSE messages (separated by double newline)
        while (buffer.contains('\n\n')) {
          final idx = buffer.indexOf('\n\n');
          final message = buffer.substring(0, idx);
          buffer = buffer.substring(idx + 2);

          for (final line in message.split('\n')) {
            if (line.startsWith('data: ')) {
              final jsonStr = line.substring(6); // remove "data: " prefix
              try {
                final data = jsonDecode(jsonStr) as Map<String, dynamic>;
                final event = AgentStreamEvent.fromJson(data);
                yield event;
              } catch (e) {
                log('[AgentService] SSE parse error: $e for line: $jsonStr');
              }
            }
          }
        }
      }
    } catch (e) {
      log('[AgentService] sendMessageStream error: $e');
      yield AgentStreamEvent(type: 'error', message: e.toString());
    } finally {
      client.close();
    }
  }
}
