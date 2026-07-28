import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/providers/inner_scope.dart';
import '../../../core/providers/session_scope.dart';
import '../../focus/data/focus_db.dart';
import '../../focus/models/gamification_models.dart';
import '../data/statistics_calculator.dart' as calc;
import '../models/statistics_state.dart';

class StatisticsNotifier extends Notifier<AsyncValue<StatisticsState>> {
  @override
  AsyncValue<StatisticsState> build() {
    // keepAlive — statistics persist for the entire session.
    final link = ref.keepAlive();

    // Invalidate on logout / user-scope change.
    ref.listen(sessionScopeProvider, (prev, next) {
      if (!next.isAuthenticated || next.logoutInProgress) {
        link.close();
        ref.invalidateSelf();
      }
    });

    ref.watch(domainScopeToken);

    final session = ref.read(sessionScopeProvider);
    if (!session.isAuthenticated || session.logoutInProgress) {
      return const AsyncValue.loading();
    }

    _load();
    return const AsyncValue.loading();
  }

  Future<void> _load() async {
    try {
      final focusDb = FocusDb();
      final dailyStats = await focusDb.getDailyStats() ?? <DailyStat>[];
      final profile = await focusDb.getProfile();

      if (profile == null) {
        // Profile not yet synced — stay in loading state.
        return;
      }

      // Last 7 days from daily stats
      final last7 = dailyStats.length > 7
          ? dailyStats.sublist(dailyStats.length - 7)
          : dailyStats;

      // Previous 7 days for form trend (days 8-14 from end)
      final prev7Start = dailyStats.length > 14
          ? dailyStats.length - 14
          : 0;
      final prev7End = dailyStats.length > 7
          ? dailyStats.length - 7
          : 0;
      final prev7 = prev7End > prev7Start
          ? dailyStats.sublist(prev7Start, prev7End)
          : <DailyStat>[];

      // Form scores
      final formScore = calc.computeFormScore(last7, profile);
      final formScorePrev = prev7.isNotEmpty
          ? calc.computeFormScore(prev7, profile)
          : formScore;

      String formTrend;
      final diff = formScore - formScorePrev;
      if (diff > 5) {
        formTrend = 'rising';
      } else if (diff < -5) {
        formTrend = 'falling';
      } else {
        formTrend = 'stable';
      }

      // Focus stats from last 7 daily stats
      final focusStats = calc.computeFocusStats(last7);

      // Daily minutes map from last 7 days
      final dailyMinutes = <String, int>{};
      for (final s in last7) {
        dailyMinutes[s.date] = s.creditedMinutes;
      }

      // 30-day daily minutes map for trend chart
      final dailyMinutes30d = <String, int>{};
      for (final s in dailyStats) {
        dailyMinutes30d[s.date] = s.creditedMinutes;
      }
      final totalMinutes30d =
          dailyStats.fold<int>(0, (sum, s) => sum + s.creditedMinutes);
      final avgMinutesPerDay30d =
          dailyStats.isNotEmpty ? totalMinutes30d ~/ dailyStats.length : 0;

      final db = await DatabaseProvider().getDatabase();
      final now = DateTime.now();
      final weekAgo = now.subtract(const Duration(days: 7));
      final thirtyDaysAgo = now.subtract(const Duration(days: 30));

      // Current week Mon-Sun bounds
      final thisWeekStart = calc.mondayOf(now);
      final lastWeekStart = thisWeekStart.subtract(const Duration(days: 7));

      // Sessions for last 14 days (covers this week + last week)
      final fourteenDaysAgo = thisWeekStart.subtract(const Duration(days: 7));
      final sessionRows14d = await db.rawQuery(
        "SELECT started_at, credited_minutes, room_id FROM focus_sessions "
        "WHERE status = 'finished' "
        "AND started_at IS NOT NULL "
        "AND started_at >= ? "
        "ORDER BY started_at",
        [fourteenDaysAgo.toIso8601String()],
      );
      final sessionRows14dMapped =
          sessionRows14d.map((r) => Map<String, Object?>.from(r)).toList();

      // Sessions for last 7 days (existing usage for bestWindow / hourlyMinutes)
      final sessionRows = await db.rawQuery(
        "SELECT started_at, credited_minutes FROM focus_sessions "
        "WHERE status = 'finished' "
        "AND started_at IS NOT NULL "
        "AND started_at >= ? "
        "ORDER BY started_at",
        [weekAgo.toIso8601String()],
      );
      final bestWindow = calc.computeBestWindow(
        sessionRows.map((r) => Map<String, Object?>.from(r)).toList(),
      );

      // Hourly minutes aggregation from sessions
      final hourlyMinutes = <int, int>{};
      for (final row in sessionRows) {
        final startedAt = row['started_at'] as String?;
        final minutes = row['credited_minutes'] as int? ?? 0;
        if (startedAt != null && minutes > 0) {
          final dt = DateTime.tryParse(startedAt);
          if (dt != null) {
            hourlyMinutes[dt.hour] =
                (hourlyMinutes[dt.hour] ?? 0) + minutes;
          }
        }
      }

      // Gamification stats from 30 days
      final gamStats = calc.computeGamificationStats(dailyStats);

      // Tasks done in last 7 days from local DB
      final taskRows = await db.rawQuery(
        "SELECT id, title, room_id FROM tasks "
        "WHERE status = 'done' "
        "AND pending_delete = 0 "
        "AND updated_at >= ?",
        [weekAgo.toIso8601String()],
      );
      final doneTasks = taskRows
          .map((r) => (
                id: r['id'] as String,
                title: r['title'] as String,
                roomId: r['room_id'] as String? ?? '',
              ))
          .toList();

      // Rooms map for top-tasks context and room stats
      final roomRows = await db.rawQuery(
        "SELECT id, title, color, archived FROM focus_rooms WHERE pending_delete = 0",
      );
      final roomById = <String, ({String title, String color})>{
        for (final r in roomRows)
          r['id'] as String: (
            title: r['title'] as String? ?? '',
            color: r['color'] as String? ?? '#6366F1',
          ),
      };
      final totalRoomsAll = roomRows
          .where((r) => (r['archived'] as int? ?? 0) == 0)
          .length;

      // Sessions grouped by task_id for top-3
      final taskSessionRows = await db.rawQuery(
        "SELECT task_id, COALESCE(SUM(credited_minutes), 0) as total "
        "FROM focus_sessions "
        "WHERE status = 'finished' "
        "AND task_id IS NOT NULL "
        "AND credited_minutes IS NOT NULL "
        "AND started_at >= ? "
        "GROUP BY task_id",
        [weekAgo.toIso8601String()],
      );
      final sessionsByTask = <String, int>{};
      for (final row in taskSessionRows) {
        final taskId = row['task_id'] as String?;
        if (taskId != null) {
          sessionsByTask[taskId] = (row['total'] as int?) ?? 0;
        }
      }

      final taskStats = calc.computeTaskStats(doneTasks, sessionsByTask, roomById: roomById);

      // Form factors
      final factors =
          calc.computeFormFactors(last7, profile, taskStats.tasksDone);

      // Today's minutes
      final today = DateTime.now();
      final todayStr =
          '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final todayStat = last7.where((s) => s.date == todayStr).firstOrNull;
      final todayMinutes = todayStat?.creditedMinutes ?? 0;

      // Today's goal from profile plan (weekday 1=Mon..7=Sun)
      final todayGoalMinutes = profile.planMinutes[today.weekday] ?? 0;

      // Week goal = sum of all enabled plan minutes
      final weekGoalMinutes =
          profile.planMinutes.values.fold<int>(0, (s, v) => s + v);

      // New pro widget data
      final weekdayTotals = calc.computeWeekdayTotals(dailyStats);
      final streakCalendar = calc.computeStreakCalendar(dailyStats);
      final monthComparison = calc.computeMonthComparison(dailyStats);
      final weekOverWeek = calc.computeWeekOverWeek(dailyMinutes30d);
      final xpBreakdown = calc.computeXpBreakdown(dailyStats);

      // Session rows for 30 days (records computation)
      final sessionRows30d = await db.rawQuery(
        "SELECT credited_minutes FROM focus_sessions "
        "WHERE status = 'finished' "
        "AND credited_minutes IS NOT NULL "
        "AND started_at >= ?",
        [thirtyDaysAgo.toIso8601String()],
      );
      final records = calc.computeRecords(
        sessionRows30d.map((r) => Map<String, Object?>.from(r)).toList(),
        dailyStats,
        gamStats.streakBest,
      );

      // Daily task counts for 30 days
      final taskRows30d = await db.rawQuery(
        "SELECT date(updated_at) as day, COUNT(*) as cnt "
        "FROM tasks "
        "WHERE status = 'done' "
        "AND pending_delete = 0 "
        "AND updated_at >= ? "
        "GROUP BY day",
        [thirtyDaysAgo.toIso8601String()],
      );
      final dailyTaskCounts30d = <String, int>{};
      for (final row in taskRows30d) {
        final day = row['day'] as String?;
        if (day != null) {
          dailyTaskCounts30d[day] = (row['cnt'] as int?) ?? 0;
        }
      }

      // === Per-room stats (week) ===
      final thisWeekEnd = thisWeekStart.add(const Duration(days: 7));
      final roomStatsWeek = calc.computeRoomStats(
        sessionRows: sessionRows14dMapped,
        roomById: roomById,
        from: thisWeekStart,
        to: thisWeekEnd,
      );

      // activeRoomsWeek: count of rooms with focus > 0 this week
      final activeRoomsWeek = roomStatsWeek.length;

      // avgRoomsPerDayWeek: unique room-days / 7
      // proxy: sum of (1 per day per room) — use sessions14d filtered to this week
      final roomDaySet = <String>{};
      for (final row in sessionRows14dMapped) {
        final startedAtStr = row['started_at'] as String?;
        final roomId = row['room_id'] as String?;
        if (startedAtStr == null || roomId == null) continue;
        final dt = DateTime.tryParse(startedAtStr);
        if (dt == null) continue;
        if (dt.isBefore(thisWeekStart) || !dt.isBefore(thisWeekEnd)) continue;
        final dayStr = '${dt.year}-${dt.month}-${dt.day}';
        roomDaySet.add('$roomId|$dayStr');
      }
      final avgRoomsPerDayWeek = roomDaySet.length / 7.0;

      // === Per-room stats (current calendar month) ===
      final monthStart = DateTime(now.year, now.month);
      final monthEnd = DateTime(now.year, now.month + 1);
      final sessionRowsMonth = await db.rawQuery(
        "SELECT started_at, credited_minutes, room_id FROM focus_sessions "
        "WHERE status = 'finished' "
        "AND started_at IS NOT NULL "
        "AND started_at >= ? AND started_at < ? "
        "ORDER BY started_at",
        [monthStart.toIso8601String(), monthEnd.toIso8601String()],
      );
      final roomStatsMonth = calc.computeRoomStats(
        sessionRows: sessionRowsMonth
            .map((r) => Map<String, Object?>.from(r))
            .toList(),
        roomById: roomById,
        from: monthStart,
        to: monthEnd,
      );

      // === Plan vs Fact ===
      final planVsFact = calc.computePlanVsFactWeek(dailyMinutes30d, profile);

      // === Compare: this week & last week summaries ===
      final screenTimeMock = calc.mockScreenTime(thisWeekStart);
      final lastScreenTimeMock = calc.mockScreenTime(lastWeekStart);

      final thisWeekSummary = calc.computeWeekSummary(
        weekStart: thisWeekStart,
        dailyStats: dailyStats,
        profile: profile,
        screenTimeMockMin: screenTimeMock.total,
      );

      final lastWeekSummary = calc.computeWeekSummary(
        weekStart: lastWeekStart,
        dailyStats: dailyStats,
        profile: profile,
        screenTimeMockMin: lastScreenTimeMock.total,
      );

      // Compare delta
      final totalChangePct = ((thisWeekSummary.allFocusMinutes -
                  lastWeekSummary.allFocusMinutes) /
              math.max(1, lastWeekSummary.allFocusMinutes) *
              100)
          .round();
      final String totalChangeLabel;
      if (totalChangePct > 0) {
        totalChangeLabel = 'You did better than last week';
      } else if (totalChangePct < 0) {
        totalChangeLabel = 'You did worse than last week';
      } else {
        totalChangeLabel = 'Same as last week';
      }

      final result = StatisticsState(
        formScore: formScore,
        formScorePrev: formScorePrev,
        formTrend: formTrend,
        dailyMinutes: dailyMinutes,
        totalMinutes7d: focusStats.totalMinutes,
        totalSessions7d: focusStats.totalSessions,
        avgSessionMinutes: focusStats.avgSessionMinutes,
        bestDayOfWeek: focusStats.bestDayOfWeek,
        bestFocusWindow: bestWindow,
        streakCurrent: profile.streakCurrent,
        streakBest: gamStats.streakBest,
        goalMetDays7d: gamStats.goalMetDays7d,
        goalMetDays30d: gamStats.goalMetDays30d,
        level: profile.level,
        xpToNextLevel: profile.xpToNextLevel,
        coinsEarned7d: gamStats.coinsEarned7d,
        weeklyGoalMetCounts: gamStats.weeklyGoalMetCounts,
        tasksDone7d: taskStats.tasksDone,
        tasksDoneWithFocus7d: taskStats.tasksDoneWithFocus,
        topTasks: taskStats.topTasks
            .map((t) => TaskFocusStat(
                  taskId: t.taskId,
                  title: t.title,
                  focusMinutes: t.minutes,
                  roomTitle: t.roomTitle,
                  roomColor: t.roomColor,
                ))
            .toList(),
        factorFocusTime: factors.focusTime,
        factorTaskCompletion: factors.taskCompletion,
        factorConsistency: factors.consistency,
        factorGoalAchievement: factors.goalAchievement,
        todayMinutes: todayMinutes,
        todayGoalMinutes: todayGoalMinutes,
        weekGoalMinutes: weekGoalMinutes,
        dailyMinutes30d: dailyMinutes30d,
        avgMinutesPerDay30d: avgMinutesPerDay30d,
        hourlyMinutes: hourlyMinutes,
        currentMonthMinutes: monthComparison.currentMonth,
        prevMonthMinutes: monthComparison.prevMonth,
        weekdayTotals: weekdayTotals,
        streakCalendar: streakCalendar,
        dailyTaskCounts30d: dailyTaskCounts30d,
        xpFromFocus: xpBreakdown.focus,
        xpFromTasks: xpBreakdown.tasks,
        xpFromStreak: xpBreakdown.streak,
        coinsBalance: profile.coins.toDouble(),
        thisWeekMinutes: weekOverWeek.thisWeek,
        lastWeekMinutes: weekOverWeek.lastWeek,
        longestSessionMin: records.longestSession,
        maxDayMinutes: records.maxDayMinutes,
        bestStreakEver: records.bestStreak,
        currentXp: profile.xp,
        // New fields
        roomStatsWeek: roomStatsWeek,
        roomStatsMonth: roomStatsMonth,
        totalRoomsAll: totalRoomsAll,
        activeRoomsWeek: activeRoomsWeek,
        avgRoomsPerDayWeek: avgRoomsPerDayWeek,
        planVsFactWeek: planVsFact.byDay,
        planVsFactWeekTotal: planVsFact.factTotal,
        planVsFactWeekPlanTotal: planVsFact.planTotal,
        thisWeekSummary: thisWeekSummary,
        lastWeekSummary: lastWeekSummary,
        totalChangePct: totalChangePct,
        totalChangeLabel: totalChangeLabel,
        screenTimeTotalMinutes: screenTimeMock.total,
        screenTimeDuringFocus: screenTimeMock.duringFocus,
        screenTimeAfterFocus: screenTimeMock.afterFocus,
        appUsage: screenTimeMock.apps,
      );

      state = AsyncValue.data(result);
    } catch (e, st) {
      debugPrint('[Statistics] load error: $e');
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    await _load();
  }
}

final statisticsProvider =
    NotifierProvider<StatisticsNotifier, AsyncValue<StatisticsState>>(
  StatisticsNotifier.new,
  dependencies: [domainScopeToken],
);
