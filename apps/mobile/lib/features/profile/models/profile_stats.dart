class BestDay {
  final DateTime date;
  final int seconds;
  final int sessionCount;

  const BestDay({
    required this.date,
    required this.seconds,
    required this.sessionCount,
  });

  factory BestDay.fromJson(Map<String, dynamic> json) {
    return BestDay(
      date: DateTime.parse(json['date'] as String),
      seconds: json['seconds'] as int? ?? 0,
      sessionCount: json['session_count'] as int? ?? 0,
    );
  }
}

class BestWeek {
  final DateTime weekStart;
  final int totalSeconds;
  final List<int> perDay;

  const BestWeek({
    required this.weekStart,
    required this.totalSeconds,
    required this.perDay,
  });

  factory BestWeek.fromJson(Map<String, dynamic> json) {
    final rawPerDay = json['per_day'];
    final perDay = rawPerDay is List
        ? rawPerDay.map((e) => e as int? ?? 0).toList()
        : <int>[];
    return BestWeek(
      weekStart: DateTime.parse(json['week_start'] as String),
      totalSeconds: json['total_seconds'] as int? ?? 0,
      perDay: perDay,
    );
  }
}

class BestMonth {
  final String month;
  final int totalSeconds;
  final List<List<int>> heatmap;

  const BestMonth({
    required this.month,
    required this.totalSeconds,
    required this.heatmap,
  });

  factory BestMonth.fromJson(Map<String, dynamic> json) {
    final rawHeatmap = json['heatmap'];
    List<List<int>> heatmap = [];
    if (rawHeatmap is List) {
      heatmap = rawHeatmap.map((row) {
        if (row is List) {
          return row.map((e) => e as int? ?? 0).toList();
        }
        return <int>[];
      }).toList();
      // Tolerate up to 6 rows — keep as-is; the UI decides how to render
    }
    return BestMonth(
      month: json['month'] as String? ?? '',
      totalSeconds: json['total_seconds'] as int? ?? 0,
      heatmap: heatmap,
    );
  }
}

class ProfileStats {
  final int allFocusSeconds;
  final int daysInApp;
  final int longestStreak;
  final BestDay? bestDay;
  final BestWeek? bestWeek;
  final BestMonth? bestMonth;

  const ProfileStats({
    required this.allFocusSeconds,
    required this.daysInApp,
    required this.longestStreak,
    this.bestDay,
    this.bestWeek,
    this.bestMonth,
  });

  factory ProfileStats.fromJson(Map<String, dynamic> json) {
    final rawBestDay = json['best_day'];
    final rawBestWeek = json['best_week'];
    final rawBestMonth = json['best_month'];

    return ProfileStats(
      allFocusSeconds: json['all_focus_seconds'] as int? ?? 0,
      daysInApp: json['days_in_app'] as int? ?? 0,
      longestStreak: json['longest_streak'] as int? ?? 0,
      bestDay: rawBestDay is Map<String, dynamic>
          ? BestDay.fromJson(rawBestDay)
          : null,
      bestWeek: rawBestWeek is Map<String, dynamic>
          ? BestWeek.fromJson(rawBestWeek)
          : null,
      bestMonth: rawBestMonth is Map<String, dynamic>
          ? BestMonth.fromJson(rawBestMonth)
          : null,
    );
  }
}
