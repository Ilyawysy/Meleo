import 'dart:convert';
import '../../../core/api_client.dart';
import '../models/gamification_models.dart';

class GamificationApi {
  final _client = ApiClient();

  Future<GamificationProfile> getProfile() async {
    final r = await _client.send('GET', _client.uri('/api/v1/gamification/profile'));
    if (r.statusCode != 200) {
      throw Exception('GET /gamification/profile failed: ${r.statusCode} ${r.body}');
    }
    return GamificationProfile.fromJson(json.decode(r.body) as Map<String, dynamic>);
  }

  Future<GamificationProfile> updateProfile({
    Map<int, int>? planMinutes,
    String? homeTz,
    int? dayCutoffHour,
    bool? minimalMode,
    String? themeMode,
    int? focusDurationMin,
    int? shortBreakMin,
    int? longBreakMin,
    int? sessionsBeforeLongBreak,
    bool? autoStartBreak,
    bool? autoStartNextSession,
    bool? adjustDurationAfterSession,
    String? statWidgetConfig,
  }) async {
    final r = await _client.send(
      'PATCH',
      _client.uri('/api/v1/gamification/profile'),
      body: {
        if (planMinutes != null)
          'plan_minutes':
              planMinutes.map((k, v) => MapEntry(k.toString(), v)),
        if (homeTz != null) 'home_tz': homeTz,
        if (dayCutoffHour != null) 'day_cutoff_hour': dayCutoffHour,
        if (minimalMode != null) 'minimal_mode': minimalMode,
        if (themeMode != null) 'theme_mode': themeMode,
        if (focusDurationMin != null) 'focus_duration_min': focusDurationMin,
        if (shortBreakMin != null) 'short_break_min': shortBreakMin,
        if (longBreakMin != null) 'long_break_min': longBreakMin,
        if (sessionsBeforeLongBreak != null) 'sessions_before_long_break': sessionsBeforeLongBreak,
        if (autoStartBreak != null) 'auto_start_break': autoStartBreak,
        if (autoStartNextSession != null) 'auto_start_next_session': autoStartNextSession,
        if (adjustDurationAfterSession != null) 'adjust_duration_after_session': adjustDurationAfterSession,
        if (statWidgetConfig != null) 'stat_widget_config': statWidgetConfig,
      },
    );
    if (r.statusCode != 200) {
      throw Exception('PATCH /gamification/profile failed: ${r.statusCode} ${r.body}');
    }
    return GamificationProfile.fromJson(json.decode(r.body) as Map<String, dynamic>);
  }

  Future<List<DailyStat>> getDailyStats({int days = 7}) async {
    final r = await _client.send('GET', _client.uri('/api/v1/gamification/daily-stats', {'days': days}));
    if (r.statusCode != 200) {
      throw Exception('GET /gamification/daily-stats failed: ${r.statusCode} ${r.body}');
    }
    final list = json.decode(r.body) as List<dynamic>;
    return list
        .map((e) => DailyStat.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
