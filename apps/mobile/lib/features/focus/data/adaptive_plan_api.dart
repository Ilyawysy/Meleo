import 'dart:convert';

import '../../../core/api_client.dart';
import '../../../core/api_http_exception.dart';
import '../models/adaptive_plan.dart';

class AdaptivePlanApi {
  final _client = ApiClient();

  Future<AdaptivePlan> getPlan() async {
    final r = await _client.send(
      'GET',
      _client.uri('/api/v1/plan/'),
    );
    if (r.statusCode != 200) {
      throw ApiHttpException(
        method: 'GET',
        path: '/api/v1/plan/',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
    return AdaptivePlan.fromJson(json.decode(r.body) as Map<String, dynamic>);
  }

  Future<AdaptivePlan> patchPlan(
    AdaptivePlan updates, {
    Set<String> clearFields = const {},
  }) async {
    final r = await _client.send(
      'PATCH',
      _client.uri('/api/v1/plan/'),
      body: updates.toPatchJson(clearFields: clearFields),
    );
    if (r.statusCode != 200) {
      throw ApiHttpException(
        method: 'PATCH',
        path: '/api/v1/plan/',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
    return AdaptivePlan.fromJson(json.decode(r.body) as Map<String, dynamic>);
  }
}
