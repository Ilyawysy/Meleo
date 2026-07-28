import 'dart:convert';

import '../../../core/api_client.dart';
import '../../../core/api_http_exception.dart';
import '../models/help_models.dart';

class HelpApi {
  final _client = ApiClient();

  static const Duration _timeout = Duration(seconds: 25);

  Future<HelpQuestion> getQuestion(
    String topicId,
    String subtopicId,
  ) async {
    final r = await _client.send(
      'POST',
      _client.uri('/api/v1/help/question'),
      body: {'topic_id': topicId, 'subtopic_id': subtopicId},
      timeout: _timeout,
    );
    if (r.statusCode != 200) {
      throw ApiHttpException(
        method: 'POST',
        path: '/api/v1/help/question',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
    return HelpQuestion.fromJson(
        json.decode(r.body) as Map<String, dynamic>);
  }

  Future<HelpCard> getCard({
    required String topicId,
    required String subtopicId,
    required String question,
    required String answer,
    HelpCardPrev? prevCard,
    String? feedback,
  }) async {
    final body = <String, dynamic>{
      'topic_id': topicId,
      'subtopic_id': subtopicId,
      'question': question,
      'answer': answer,
      if (prevCard != null) 'prev_card': prevCard.toJson(),
      if (feedback != null) 'feedback': feedback,
    };
    final r = await _client.send(
      'POST',
      _client.uri('/api/v1/help/card'),
      body: body,
      timeout: _timeout,
    );
    if (r.statusCode != 200) {
      throw ApiHttpException(
        method: 'POST',
        path: '/api/v1/help/card',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
    return HelpCard.fromJson(
        json.decode(r.body) as Map<String, dynamic>);
  }
}
