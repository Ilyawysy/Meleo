import 'dart:math' as math;

import '../../focus/models/gamification_models.dart';
import '../models/statistics_state.dart';

/// Compute Form score (0-100) from daily stats.
///
/// Formula: weighted combination of:
/// - Focus consistency (days with credited minutes / total days) * 40
/// - Goal met ratio (streak days / total days) * 30
/// - Session volume (total minutes / (plan * days), capped at 1) * 30
int computeFormScore(List<DailyStat> stats, GamificationProfile profile) {
  if (stats.isEmpty) return 0;

  final days = stats.length;
  final daysWithFocus = stats.where((s) => s.creditedMinutes > 0).length;
  final daysGoalMet = stats.where((s) => s.isStreakDay).length;
  final totalMinutes =
      stats.fold<int>(0, (sum, s) => sum + s.creditedMinutes);

  final focusConsistency = daysWithFocus / days;
  final goalRatio = daysGoalMet / days;
  final enabledDayMins = profile.planMinutes.values.where((v) => v > 0).toList();
  final avgPlanMinutes = enabledDayMins.isEmpty
      ? 0
      : enabledDayMins.fold<int>(0, (s, v) => s + v) ~/ enabledDayMins.length;
  final planTotal = avgPlanMinutes * days;
  final volumeRatio =
      planTotal > 0 ? (totalMinutes / planTotal).clamp(0.0, 1.0) : 0.0;

  final score =
      (focusConsistency * 40 + goalRatio * 30 + volumeRatio * 30).round();
  return score.clamp(0, 100);
}

/// Compute focus stats from daily stats (last 7 days).
({
  int totalMinutes,
  int totalSessions,
  double avgSessionMinutes,
  String bestDayOfWeek,
}) computeFocusStats(List<DailyStat> stats) {
  final totalMinutes =
      stats.fold<int>(0, (sum, s) => sum + s.creditedMinutes);
  final totalSessions =
      stats.fold<int>(0, (sum, s) => sum + s.sessionCount);

  final avgSession =
      totalSessions > 0 ? totalMinutes / totalSessions : 0.0;

  // Find best day of week by credited_minutes
  final dayNames = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
  final byDow = <int, int>{};
  for (final s in stats) {
    final date = DateTime.tryParse(s.date);
    if (date == null) continue;
    // DateTime weekday: 1=Monday ... 7=Sunday
    byDow.update(date.weekday, (v) => v + s.creditedMinutes,
        ifAbsent: () => s.creditedMinutes);
  }

  String bestDay = '—';
  if (byDow.isNotEmpty) {
    final bestDow =
        byDow.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    bestDay = dayNames[bestDow - 1];
  }

  return (
    totalMinutes: totalMinutes,
    totalSessions: totalSessions,
    avgSessionMinutes: avgSession,
    bestDayOfWeek: bestDay,
  );
}

/// Determine best focus window from session start times.
///
/// Windows: Morning 6-12, Day 12-18, Evening 18-24, Night 0-6.
/// [sessionRows] should contain maps with 'started_at' (ISO string)
/// and 'credited_minutes' (int).
String computeBestWindow(List<Map<String, Object?>> sessionRows) {
  final windows = <String, int>{
    'Morning': 0,
    'Day': 0,
    'Evening': 0,
    'Night': 0,
  };

  for (final row in sessionRows) {
    final startedAtStr = row['started_at'] as String?;
    final minutes = (row['credited_minutes'] as int?) ?? 0;
    if (startedAtStr == null || minutes <= 0) continue;

    final dt = DateTime.tryParse(startedAtStr);
    if (dt == null) continue;

    final hour = dt.hour;
    if (hour >= 6 && hour < 12) {
      windows['Morning'] = windows['Morning']! + minutes;
    } else if (hour >= 12 && hour < 18) {
      windows['Day'] = windows['Day']! + minutes;
    } else if (hour >= 18) {
      windows['Evening'] = windows['Evening']! + minutes;
    } else {
      windows['Night'] = windows['Night']! + minutes;
    }
  }

  final total = windows.values.fold<int>(0, (a, b) => a + b);
  if (total == 0) return '—';

  return windows.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
}

/// Compute gamification stats from 30-day daily stats.
({
  int streakBest,
  int goalMetDays7d,
  int goalMetDays30d,
  int coinsEarned7d,
  List<int> weeklyGoalMetCounts,
}) computeGamificationStats(List<DailyStat> stats) {
  // Sort by date ascending
  final sorted = List<DailyStat>.from(stats)
    ..sort((a, b) => a.date.compareTo(b.date));

  // Best streak: longest consecutive run of isStreakDay
  int streakBest = 0;
  int currentRun = 0;
  for (final s in sorted) {
    if (s.isStreakDay) {
      currentRun++;
      if (currentRun > streakBest) streakBest = currentRun;
    } else {
      currentRun = 0;
    }
  }

  // Split into last 7 days and full 30 days
  final last7 = sorted.length > 7 ? sorted.sublist(sorted.length - 7) : sorted;

  final goalMetDays7d = last7.where((s) => s.isStreakDay).length;
  final goalMetDays30d = sorted.where((s) => s.isStreakDay).length;
  final coinsEarned7d =
      last7.fold<int>(0, (sum, s) => sum + s.coinsEarned);

  // Weekly goal met counts: split 30 days into 4 weeks (7+7+7+9 or similar)
  final weeklyGoalMet = <int>[];
  for (int i = 0; i < 4; i++) {
    final weekStart = i * 7;
    final weekEnd = (i + 1) * 7;
    if (weekStart >= sorted.length) {
      weeklyGoalMet.add(0);
      continue;
    }
    final weekSlice = sorted.sublist(
      weekStart,
      weekEnd > sorted.length ? sorted.length : weekEnd,
    );
    weeklyGoalMet.add(weekSlice.where((s) => s.isStreakDay).length);
  }

  return (
    streakBest: streakBest,
    goalMetDays7d: goalMetDays7d,
    goalMetDays30d: goalMetDays30d,
    coinsEarned7d: coinsEarned7d,
    weeklyGoalMetCounts: weeklyGoalMet,
  );
}

/// Compute the 4 form factor scores (0-100 each).
({int focusTime, int taskCompletion, int consistency, int goalAchievement})
    computeFormFactors(
  List<DailyStat> stats,
  GamificationProfile profile,
  int tasksDone7d,
) {
  if (stats.isEmpty) {
    return (
      focusTime: 0,
      taskCompletion: 0,
      consistency: 0,
      goalAchievement: 0,
    );
  }

  final days = stats.length;
  final totalMinutes =
      stats.fold<int>(0, (sum, s) => sum + s.creditedMinutes);
  final daysWithFocus = stats.where((s) => s.creditedMinutes > 0).length;
  final daysGoalMet = stats.where((s) => s.isStreakDay).length;

  // Focus Time: volume vs plan (40% weight in form score)
  final enabledDayMins =
      profile.planMinutes.values.where((v) => v > 0).toList();
  final avgPlanMinutes = enabledDayMins.isEmpty
      ? 0
      : enabledDayMins.fold<int>(0, (s, v) => s + v) ~/
          enabledDayMins.length;
  final planTotal = avgPlanMinutes * days;
  final volumeRatio =
      planTotal > 0 ? (totalMinutes / planTotal).clamp(0.0, 1.0) : 0.0;
  final focusTime = (volumeRatio * 100).round().clamp(0, 100);

  // Task Completion: approx 7 tasks/week = 100
  final taskCompletion = (tasksDone7d * 14).clamp(0, 100);

  // Consistency: days with focus / total days
  final consistency = ((daysWithFocus / days) * 100).round().clamp(0, 100);

  // Goal Achievement: streak days / total days
  final goalAchievement =
      ((daysGoalMet / days) * 100).round().clamp(0, 100);

  return (
    focusTime: focusTime,
    taskCompletion: taskCompletion,
    consistency: consistency,
    goalAchievement: goalAchievement,
  );
}

/// Compute task stats.
///
/// [doneTasks] — tasks with status='done' updated in last 7 days.
/// [sessionsByTask] — map of taskId -> total credited_minutes.
/// [roomById] — map of roomId -> (title, color) for room context.
({
  int tasksDone,
  int tasksDoneWithFocus,
  List<({String taskId, String title, int minutes, String? roomTitle, String? roomColor})>
      topTasks,
}) computeTaskStats(
  List<({String id, String title, String roomId})> doneTasks,
  Map<String, int> sessionsByTask, {
  Map<String, ({String title, String color})> roomById = const {},
}) {
  final tasksDone = doneTasks.length;
  int withFocus = 0;
  final taskMinutes =
      <({String taskId, String title, int minutes, String? roomTitle, String? roomColor})>[];

  for (final t in doneTasks) {
    final minutes = sessionsByTask[t.id] ?? 0;
    if (minutes > 0) {
      withFocus++;
      final room = roomById[t.roomId];
      taskMinutes.add((
        taskId: t.id,
        title: t.title,
        minutes: minutes,
        roomTitle: room?.title,
        roomColor: room?.color,
      ));
    }
  }

  // Sort by minutes descending, take top 3
  taskMinutes.sort((a, b) => b.minutes.compareTo(a.minutes));
  final top3 = taskMinutes.take(3).toList();

  return (
    tasksDone: tasksDone,
    tasksDoneWithFocus: withFocus,
    topTasks: top3,
  );
}

/// Compute per-weekday totals from daily stats (30d).
Map<int, int> computeWeekdayTotals(List<DailyStat> stats) {
  final result = <int, int>{};
  for (final s in stats) {
    final date = DateTime.tryParse(s.date);
    if (date == null) continue;
    result.update(date.weekday, (v) => v + s.creditedMinutes,
        ifAbsent: () => s.creditedMinutes);
  }
  return result;
}

/// Build streak calendar map from daily stats.
Map<String, bool> computeStreakCalendar(List<DailyStat> stats) {
  return {for (final s in stats) s.date: s.isStreakDay};
}

/// Compute current month vs previous month total minutes.
({int currentMonth, int prevMonth}) computeMonthComparison(
    List<DailyStat> stats) {
  final now = DateTime.now();
  final currentMonthStr =
      '${now.year}-${now.month.toString().padLeft(2, '0')}';

  final prevDate = DateTime(now.year, now.month - 1);
  final prevMonthStr =
      '${prevDate.year}-${prevDate.month.toString().padLeft(2, '0')}';

  int currentTotal = 0;
  int prevTotal = 0;
  for (final s in stats) {
    if (s.date.startsWith(currentMonthStr)) {
      currentTotal += s.creditedMinutes;
    } else if (s.date.startsWith(prevMonthStr)) {
      prevTotal += s.creditedMinutes;
    }
  }
  return (currentMonth: currentTotal, prevMonth: prevTotal);
}

/// Compute this week vs last week total minutes.
({int thisWeek, int lastWeek}) computeWeekOverWeek(
    Map<String, int> dailyMinutes) {
  final now = DateTime.now();
  final mondayThisWeek = now.subtract(Duration(days: now.weekday - 1));
  final mondayLastWeek = mondayThisWeek.subtract(const Duration(days: 7));

  int thisWeek = 0;
  int lastWeek = 0;

  dailyMinutes.forEach((dateStr, minutes) {
    final date = DateTime.tryParse(dateStr);
    if (date == null) return;
    if (!date.isBefore(mondayThisWeek) &&
        date.isBefore(mondayThisWeek.add(const Duration(days: 7)))) {
      thisWeek += minutes;
    } else if (!date.isBefore(mondayLastWeek) &&
        date.isBefore(mondayThisWeek)) {
      lastWeek += minutes;
    }
  });

  return (thisWeek: thisWeek, lastWeek: lastWeek);
}

/// Approximate XP breakdown (focus ~60%, tasks ~25%, streak ~15%).
({int focus, int tasks, int streak}) computeXpBreakdown(
    List<DailyStat> stats) {
  final totalXp = stats.fold<int>(0, (sum, s) => sum + s.xpEarned);
  final focusXp = (totalXp * 0.6).round();
  final taskXp = (totalXp * 0.25).round();
  final streakXp = totalXp - focusXp - taskXp;
  return (focus: focusXp, tasks: taskXp, streak: streakXp);
}

/// Compute personal records.
({int longestSession, int maxDayMinutes, int bestStreak}) computeRecords(
  List<Map<String, Object?>> sessionRows,
  List<DailyStat> stats,
  int bestStreakOverall,
) {
  int longestSession = 0;
  for (final row in sessionRows) {
    final minutes = (row['credited_minutes'] as int?) ?? 0;
    if (minutes > longestSession) longestSession = minutes;
  }

  int maxDayMinutes = 0;
  for (final s in stats) {
    if (s.creditedMinutes > maxDayMinutes) maxDayMinutes = s.creditedMinutes;
  }

  return (
    longestSession: longestSession,
    maxDayMinutes: maxDayMinutes,
    bestStreak: bestStreakOverall,
  );
}

/// Returns the Monday of the week containing [d], at 00:00:00 local time.
DateTime mondayOf(DateTime d) {
  return DateTime(d.year, d.month, d.day)
      .subtract(Duration(days: d.weekday - 1));
}

/// Per-room aggregates for sessions within [from, to).
///
/// [sessionRows] must contain: started_at (ISO string), credited_minutes (int),
/// room_id (String).
List<RoomStat> computeRoomStats({
  required List<Map<String, Object?>> sessionRows,
  required Map<String, ({String title, String color})> roomById,
  required DateTime from,
  required DateTime to,
}) {
  // Accumulate per-room totals
  final minutes = <String, int>{};
  final sessions = <String, int>{};
  final dailyMin = <String, Map<int, int>>{};
  final hourlyMin = <String, Map<int, int>>{};

  for (final row in sessionRows) {
    final startedAtStr = row['started_at'] as String?;
    final credited = (row['credited_minutes'] as int?) ?? 0;
    final roomId = row['room_id'] as String?;
    if (startedAtStr == null || roomId == null || credited <= 0) continue;

    final dt = DateTime.tryParse(startedAtStr);
    if (dt == null) continue;
    if (dt.isBefore(from) || !dt.isBefore(to)) continue;

    minutes[roomId] = (minutes[roomId] ?? 0) + credited;
    sessions[roomId] = (sessions[roomId] ?? 0) + 1;

    // daily bucket: weekday 1..7 for weekly, day-of-month 1..31 for monthly
    final bucket = dt.weekday; // caller decides; we use weekday uniformly
    dailyMin.putIfAbsent(roomId, () => {});
    dailyMin[roomId]![bucket] = (dailyMin[roomId]![bucket] ?? 0) + credited;

    hourlyMin.putIfAbsent(roomId, () => {});
    hourlyMin[roomId]![dt.hour] = (hourlyMin[roomId]![dt.hour] ?? 0) + credited;
  }

  // Total minutes across all rooms for % calculation
  final grandTotal = minutes.values.fold<int>(0, (a, b) => a + b);

  final result = <RoomStat>[];
  for (final roomId in minutes.keys) {
    final room = roomById[roomId];
    final totalMin = minutes[roomId]!;
    final totalSess = sessions[roomId]!;

    // Best window by hour bucket
    final hourMap = hourlyMin[roomId] ?? {};
    String bestWindow = '—';
    if (hourMap.isNotEmpty) {
      final bestHour =
          hourMap.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      final endHour = (bestHour + 1) % 24;
      bestWindow =
          '${bestHour.toString().padLeft(2, '0')}:00 - ${endHour.toString().padLeft(2, '0')}:00';
    }

    result.add(RoomStat(
      roomId: roomId,
      title: room?.title ?? roomId,
      color: room?.color ?? '#6366F1',
      totalMinutes: totalMin,
      totalSessions: totalSess,
      avgSessionMinutes: totalSess > 0 ? totalMin / totalSess : 0.0,
      dailyMinutes: dailyMin[roomId] ?? {},
      bestWindow: bestWindow,
      allFocusPct: grandTotal > 0 ? totalMin / grandTotal : 0.0,
    ));
  }

  // Sort descending by total minutes
  result.sort((a, b) => b.totalMinutes.compareTo(a.totalMinutes));
  return result;
}

/// Plan vs Fact for the current Mon-Sun week.
///
/// [dailyMinutes] is a map of date-string -> credited minutes.
/// [profile] supplies planMinutes (weekday 1..7 -> planned minutes).
({
  Map<int, ({int plan, int fact})> byDay,
  int factTotal,
  int planTotal,
}) computePlanVsFactWeek(
  Map<String, int> dailyMinutes,
  GamificationProfile profile,
) {
  final now = DateTime.now();
  final monday = mondayOf(now);

  final byDay = <int, ({int plan, int fact})>{};
  int factTotal = 0;
  int planTotal = 0;

  for (int wd = 1; wd <= 7; wd++) {
    final date = monday.add(Duration(days: wd - 1));
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final fact = dailyMinutes[dateStr] ?? 0;
    final plan = profile.planMinutes[wd] ?? 0;
    byDay[wd] = (plan: plan, fact: fact);
    factTotal += fact;
    planTotal += plan;
  }

  return (byDay: byDay, factTotal: factTotal, planTotal: planTotal);
}

/// Compute a summary for a single Mon-Sun week starting at [weekStart].
WeekSummary computeWeekSummary({
  required DateTime weekStart,
  required List<DailyStat> dailyStats,
  required GamificationProfile profile,
  required int screenTimeMockMin,
}) {
  final weekEnd = weekStart.add(const Duration(days: 7));

  // Filter daily stats to this week
  final weekStats = dailyStats.where((s) {
    final d = DateTime.tryParse(s.date);
    return d != null && !d.isBefore(weekStart) && d.isBefore(weekEnd);
  }).toList();

  final allFocusMinutes =
      weekStats.fold<int>(0, (sum, s) => sum + s.creditedMinutes);
  final sessions = weekStats.fold<int>(0, (sum, s) => sum + s.sessionCount);
  final focusDays = weekStats.where((s) => s.creditedMinutes > 0).length;

  final avgFocusPerDay = focusDays > 0 ? allFocusMinutes ~/ 7 : 0;
  final avgFocusPerSession =
      sessions > 0 ? allFocusMinutes / sessions : 0.0;

  // Plan completion: fact / plan * 100
  int planTotal = 0;
  for (int wd = 1; wd <= 7; wd++) {
    planTotal += profile.planMinutes[wd] ?? 0;
  }
  final planCompletePct =
      planTotal > 0 ? ((allFocusMinutes / planTotal) * 100).round().clamp(0, 100) : 0;

  // focusDaysGoal: days with plan > 0
  final focusDaysGoal =
      profile.planMinutes.values.where((v) => v > 0).length.clamp(1, 7);

  // Form score for this week
  final focusFormScore = computeFormScore(weekStats, profile);

  // Rhythm score: inverse of coefficient of variation of daily minutes (0..100)
  // High consistency = high score
  int rhythmScore = 0;
  if (focusDays > 1) {
    final mean = allFocusMinutes / 7;
    if (mean > 0) {
      final variance = weekStats.fold<double>(
          0.0, (acc, s) => acc + math.pow(s.creditedMinutes - mean, 2));
      final stdDev = math.sqrt(variance / 7);
      final cv = stdDev / mean; // coefficient of variation
      rhythmScore = ((1 - cv.clamp(0.0, 1.0)) * 100).round().clamp(0, 100);
    }
  }

  return WeekSummary(
    weekStart: weekStart,
    focusFormScore: focusFormScore,
    allFocusMinutes: allFocusMinutes,
    avgFocusMinutesPerDay: avgFocusPerDay,
    avgFocusMinutesPerSession: avgFocusPerSession,
    sessions: sessions,
    focusDays: focusDays,
    focusDaysGoal: focusDaysGoal,
    screenTimeMinutes: screenTimeMockMin,
    rhythmScore: rhythmScore,
    planCompletePct: planCompletePct,
  );
}

/// Deterministic mock screen time generator seeded on [weekStart].
///
/// Returns consistent values across restarts (no random on each call).
//TODO: replace with real native screen time data when plugin is available
({
  int total,
  int duringFocus,
  int afterFocus,
  List<({String app, int beforeMin, int afterMin})> apps,
}) mockScreenTime(DateTime weekStart) {
  // Deterministic seed from weekStart day-of-year
  final seed = weekStart.year * 1000 + weekStart.month * 31 + weekStart.day;
  final rng = math.Random(seed);

  // Total screen time: 30..120 min/day * 7 days
  final dailyAvg = 30 + rng.nextInt(91); // 30..120
  final total = dailyAvg * 7;

  // ~50% during focus
  final duringFocus = (total * (0.4 + rng.nextDouble() * 0.2)).round();
  final afterFocus = total - duringFocus;

  // 3 mock apps
  final apps = <({String app, int beforeMin, int afterMin})>[
    (
      app: 'TikTok',
      beforeMin: 5 + rng.nextInt(16),
      afterMin: 10 + rng.nextInt(21),
    ),
    (
      app: 'YouTube',
      beforeMin: 3 + rng.nextInt(11),
      afterMin: 8 + rng.nextInt(16),
    ),
    (
      app: 'X',
      beforeMin: 2 + rng.nextInt(9),
      afterMin: 5 + rng.nextInt(11),
    ),
  ];

  return (
    total: total,
    duringFocus: duringFocus,
    afterFocus: afterFocus,
    apps: apps,
  );
}
