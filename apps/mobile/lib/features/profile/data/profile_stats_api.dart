import 'dart:convert';

import '../../../core/api_client.dart';
import '../../../core/api_http_exception.dart';
import '../models/profile_stats.dart';

class ProfileStatsApi {
  final _client = ApiClient();

  Future<ProfileStats> getStats() async {
    final r = await _client.send(
      'GET',
      _client.uri('/api/v1/profile/stats'),
    );
    if (r.statusCode != 200) {
      throw ApiHttpException(
        method: 'GET',
        path: '/api/v1/profile/stats',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
    return ProfileStats.fromJson(
      json.decode(r.body) as Map<String, dynamic>,
    );
  }
}
