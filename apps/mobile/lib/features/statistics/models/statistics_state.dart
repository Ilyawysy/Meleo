class TaskFocusStat {
  final String taskId;
  final String title;
  final int focusMinutes;
  final String? roomTitle;
  final String? roomColor;

  const TaskFocusStat({
    required this.taskId,
    required this.title,
    required this.focusMinutes,
    this.roomTitle,
    this.roomColor,
  });
}

// === Per-room aggregates (для StatsRoomsPage) ===
class RoomStat {
  final String roomId;
  final String title;
  final String color;
  final int totalMinutes;
  final int totalSessions;
  final double avgSessionMinutes;
  final Map<int, int> dailyMinutes;
  final String bestWindow;
  final double allFocusPct;

  const RoomStat({
    required this.roomId,
    required this.title,
    required this.color,
    required this.totalMinutes,
    required this.totalSessions,
    required this.avgSessionMinutes,
    required this.dailyMinutes,
    required this.bestWindow,
    required this.allFocusPct,
  });
}

// === Compare (для StatsCompPage) ===
class WeekSummary {
  final DateTime weekStart;
  final int focusFormScore;
  final int allFocusMinutes;
  final int avgFocusMinutesPerDay;
  final double avgFocusMinutesPerSession;
  final int sessions;
  final int focusDays;
  final int focusDaysGoal;
  final int screenTimeMinutes;
  final int rhythmScore;
  final int planCompletePct;

  const WeekSummary({
    required this.weekStart,
    required this.focusFormScore,
    required this.allFocusMinutes,
    required this.avgFocusMinutesPerDay,
    required this.avgFocusMinutesPerSession,
    required this.sessions,
    required this.focusDays,
    required this.focusDaysGoal,
    required this.screenTimeMinutes,
    required this.rhythmScore,
    required this.planCompletePct,
  });
}

class StatisticsState {
  // Form
  final int formScore;
  final int formScorePrev;
  final String formTrend; // "rising" | "falling" | "stable"

  // Focus
  final Map<String, int> dailyMinutes; // 7 days: date -> minutes
  final int totalMinutes7d;
  final int totalSessions7d;
  final double avgSessionMinutes;
  final String bestDayOfWeek;
  final String bestFocusWindow;

  // Gamification
  final int streakCurrent;
  final int streakBest;
  final int goalMetDays7d;
  final int goalMetDays30d;
  final int level;
  final int xpToNextLevel;
  final int coinsEarned7d;
  final List<int> weeklyGoalMetCounts; // 4 values for mini chart

  // Tasks
  final int tasksDone7d;
  final int tasksDoneWithFocus7d;
  final List<TaskFocusStat> topTasks;

  // Form factors for breakdown
  final int factorFocusTime; // 0-100
  final int factorTaskCompletion; // 0-100
  final int factorConsistency; // 0-100
  final int factorGoalAchievement; // 0-100

  // Today / week goals
  final int todayMinutes;
  final int todayGoalMinutes;
  final int weekGoalMinutes;

  // 30-day trend data
  final Map<String, int> dailyMinutes30d; // date -> minutes, 30 days
  final int avgMinutesPerDay30d;

  // Hourly focus heatmap (hour 0-23 -> total minutes across last 7 days)
  final Map<int, int> hourlyMinutes;

  // Month comparison (for MonthVsMonth)
  final int currentMonthMinutes;
  final int prevMonthMinutes;

  // Per-weekday totals (for DayOfWeekMap) - weekday 1(Mon)..7(Sun) -> total minutes
  final Map<int, int> weekdayTotals;

  // Streak calendar (for StreakHistory) - date string -> isStreakDay
  final Map<String, bool> streakCalendar;

  // Daily task counts (for TaskCompletionTrend, TaskCompletionGrid, TaskFocusCorrelation)
  final Map<String, int> dailyTaskCounts30d;

  // XP breakdown approximation
  final int xpFromFocus;
  final int xpFromTasks;
  final int xpFromStreak;

  // Coins balance
  final double coinsBalance;

  // Week over week
  final int thisWeekMinutes;
  final int lastWeekMinutes;

  // Records
  final int longestSessionMin;
  final int maxDayMinutes;
  final int bestStreakEver;

  // XP and level (from profile, for LevelProgress)
  final int currentXp;

  // === Per-room aggregates (для StatsRoomsPage) ===
  final List<RoomStat> roomStatsWeek;
  final List<RoomStat> roomStatsMonth;
  final int totalRoomsAll;
  final int activeRoomsWeek;
  final double avgRoomsPerDayWeek;

  // === Plan vs Fact (для StatsFocusPage) ===
  // weekday 1..7 (Mon..Sun) -> (plan, fact) минуты
  final Map<int, ({int plan, int fact})> planVsFactWeek;
  final int planVsFactWeekTotal;
  final int planVsFactWeekPlanTotal;

  // === Compare (для StatsCompPage) ===
  final WeekSummary thisWeekSummary;
  final WeekSummary lastWeekSummary;
  final int totalChangePct;
  final String totalChangeLabel;

  // === Screen time (mocked, TODO: replace with native plugin) ===
  //TODO: replace with real native screen time data when plugin is available
  final int screenTimeTotalMinutes;
  final int screenTimeDuringFocus;
  final int screenTimeAfterFocus;
  final List<({String app, int beforeMin, int afterMin})> appUsage;

  const StatisticsState({
    required this.formScore,
    required this.formScorePrev,
    required this.formTrend,
    required this.dailyMinutes,
    required this.totalMinutes7d,
    required this.totalSessions7d,
    required this.avgSessionMinutes,
    required this.bestDayOfWeek,
    required this.bestFocusWindow,
    required this.streakCurrent,
    required this.streakBest,
    required this.goalMetDays7d,
    required this.goalMetDays30d,
    required this.level,
    required this.xpToNextLevel,
    required this.coinsEarned7d,
    required this.weeklyGoalMetCounts,
    required this.tasksDone7d,
    required this.tasksDoneWithFocus7d,
    required this.topTasks,
    required this.factorFocusTime,
    required this.factorTaskCompletion,
    required this.factorConsistency,
    required this.factorGoalAchievement,
    required this.todayMinutes,
    required this.todayGoalMinutes,
    required this.weekGoalMinutes,
    required this.dailyMinutes30d,
    required this.avgMinutesPerDay30d,
    required this.hourlyMinutes,
    required this.currentMonthMinutes,
    required this.prevMonthMinutes,
    required this.weekdayTotals,
    required this.streakCalendar,
    required this.dailyTaskCounts30d,
    required this.xpFromFocus,
    required this.xpFromTasks,
    required this.xpFromStreak,
    required this.coinsBalance,
    required this.thisWeekMinutes,
    required this.lastWeekMinutes,
    required this.longestSessionMin,
    required this.maxDayMinutes,
    required this.bestStreakEver,
    required this.currentXp,
    required this.roomStatsWeek,
    required this.roomStatsMonth,
    required this.totalRoomsAll,
    required this.activeRoomsWeek,
    required this.avgRoomsPerDayWeek,
    required this.planVsFactWeek,
    required this.planVsFactWeekTotal,
    required this.planVsFactWeekPlanTotal,
    required this.thisWeekSummary,
    required this.lastWeekSummary,
    required this.totalChangePct,
    required this.totalChangeLabel,
    required this.screenTimeTotalMinutes,
    required this.screenTimeDuringFocus,
    required this.screenTimeAfterFocus,
    required this.appUsage,
  });
}
