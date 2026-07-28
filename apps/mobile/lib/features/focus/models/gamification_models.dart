class GamificationProfile {
  final int xp;
  final int level;
  final int xpToNextLevel;
  final int streakCurrent;
  final Map<int, int> planMinutes;
  final String homeTz;
  final int dayCutoffHour;
  final int recoveryDaysRemaining;
  final bool minimalMode;
  final double coins;
  final String? recoveryMode;
  final bool shieldUnlocked;
  final int shieldCharges;
  final int shieldRechargeProgress;
  final String? themeMode;
  final String? statWidgetConfig;
  final int focusDurationMin;
  final int shortBreakMin;
  final int longBreakMin;
  final int sessionsBeforeLongBreak;
  final bool autoStartBreak;
  final bool autoStartNextSession;
  final bool adjustDurationAfterSession;
  final String? activeFocusRoomId;

  const GamificationProfile({
    required this.xp,
    required this.level,
    required this.xpToNextLevel,
    required this.streakCurrent,
    required this.planMinutes,
    required this.homeTz,
    required this.dayCutoffHour,
    required this.recoveryDaysRemaining,
    required this.minimalMode,
    required this.coins,
    this.recoveryMode,
    this.shieldUnlocked = false,
    this.shieldCharges = 0,
    this.shieldRechargeProgress = 0,
    this.themeMode,
    this.statWidgetConfig,
    this.focusDurationMin = 25,
    this.shortBreakMin = 5,
    this.longBreakMin = 15,
    this.sessionsBeforeLongBreak = 4,
    this.autoStartBreak = true,
    this.autoStartNextSession = false,
    this.adjustDurationAfterSession = false,
    this.activeFocusRoomId,
  });

  factory GamificationProfile.fromJson(Map<String, dynamic> json) {
    return GamificationProfile(
      xp: json['xp'] as int? ?? 0,
      level: json['level'] as int? ?? 0,
      xpToNextLevel: json['xp_to_next_level'] as int? ?? 0,
      streakCurrent: json['streak_current'] as int? ?? 0,
      planMinutes: json['plan_minutes'] != null
          ? (json['plan_minutes'] as Map<String, dynamic>).map(
              (k, v) => MapEntry(int.parse(k), v as int),
            )
          : {1: 30, 3: 30, 5: 30},
      homeTz: json['home_tz'] as String? ?? 'UTC',
      dayCutoffHour: json['day_cutoff_hour'] as int? ?? 4,
      recoveryDaysRemaining: json['recovery_days_remaining'] as int? ?? 0,
      minimalMode: json['minimal_mode'] as bool? ?? false,
      coins: (json['coins'] as num?)?.toDouble() ?? 0.0,
      recoveryMode: json['recovery_mode'] as String?,
      shieldUnlocked: json['shield_unlocked'] as bool? ?? false,
      shieldCharges: json['shield_charges'] as int? ?? 0,
      shieldRechargeProgress: json['shield_recharge_progress'] as int? ?? 0,
      themeMode: json['theme_mode'] as String?,
      statWidgetConfig: json['stat_widget_config'] as String?,
      focusDurationMin: json['focus_duration_min'] as int? ?? 25,
      shortBreakMin: json['short_break_min'] as int? ?? 5,
      longBreakMin: json['long_break_min'] as int? ?? 15,
      sessionsBeforeLongBreak: json['sessions_before_long_break'] as int? ?? 4,
      autoStartBreak: json['auto_start_break'] as bool? ?? true,
      autoStartNextSession: json['auto_start_next_session'] as bool? ?? false,
      adjustDurationAfterSession: json['adjust_duration_after_session'] as bool? ?? false,
      activeFocusRoomId: json['active_focus_room_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'xp': xp,
        'level': level,
        'xp_to_next_level': xpToNextLevel,
        'streak_current': streakCurrent,
        'plan_minutes': planMinutes.map((k, v) => MapEntry(k.toString(), v)),
        'home_tz': homeTz,
        'day_cutoff_hour': dayCutoffHour,
        'recovery_days_remaining': recoveryDaysRemaining,
        'minimal_mode': minimalMode,
        'coins': coins,
        'recovery_mode': recoveryMode,
        'shield_unlocked': shieldUnlocked,
        'shield_charges': shieldCharges,
        'shield_recharge_progress': shieldRechargeProgress,
        if (themeMode != null) 'theme_mode': themeMode,
        if (statWidgetConfig != null) 'stat_widget_config': statWidgetConfig,
        'focus_duration_min': focusDurationMin,
        'short_break_min': shortBreakMin,
        'long_break_min': longBreakMin,
        'sessions_before_long_break': sessionsBeforeLongBreak,
        'auto_start_break': autoStartBreak,
        'auto_start_next_session': autoStartNextSession,
        'adjust_duration_after_session': adjustDurationAfterSession,
        if (activeFocusRoomId != null) 'active_focus_room_id': activeFocusRoomId,
      };

  GamificationProfile copyWith({
    int? xp,
    int? level,
    int? xpToNextLevel,
    int? streakCurrent,
    Map<int, int>? planMinutes,
    String? homeTz,
    int? dayCutoffHour,
    int? recoveryDaysRemaining,
    bool? minimalMode,
    double? coins,
    String? recoveryMode,
    bool? shieldUnlocked,
    int? shieldCharges,
    int? shieldRechargeProgress,
    String? themeMode,
    String? statWidgetConfig,
    int? focusDurationMin,
    int? shortBreakMin,
    int? longBreakMin,
    int? sessionsBeforeLongBreak,
    bool? autoStartBreak,
    bool? autoStartNextSession,
    bool? adjustDurationAfterSession,
    String? activeFocusRoomId,
  }) {
    return GamificationProfile(
      xp: xp ?? this.xp,
      level: level ?? this.level,
      xpToNextLevel: xpToNextLevel ?? this.xpToNextLevel,
      streakCurrent: streakCurrent ?? this.streakCurrent,
      planMinutes: planMinutes ?? this.planMinutes,
      homeTz: homeTz ?? this.homeTz,
      dayCutoffHour: dayCutoffHour ?? this.dayCutoffHour,
      recoveryDaysRemaining:
          recoveryDaysRemaining ?? this.recoveryDaysRemaining,
      minimalMode: minimalMode ?? this.minimalMode,
      coins: coins ?? this.coins,
      recoveryMode: recoveryMode ?? this.recoveryMode,
      shieldUnlocked: shieldUnlocked ?? this.shieldUnlocked,
      shieldCharges: shieldCharges ?? this.shieldCharges,
      shieldRechargeProgress:
          shieldRechargeProgress ?? this.shieldRechargeProgress,
      themeMode: themeMode ?? this.themeMode,
      statWidgetConfig: statWidgetConfig ?? this.statWidgetConfig,
      focusDurationMin: focusDurationMin ?? this.focusDurationMin,
      shortBreakMin: shortBreakMin ?? this.shortBreakMin,
      longBreakMin: longBreakMin ?? this.longBreakMin,
      sessionsBeforeLongBreak:
          sessionsBeforeLongBreak ?? this.sessionsBeforeLongBreak,
      autoStartBreak: autoStartBreak ?? this.autoStartBreak,
      autoStartNextSession:
          autoStartNextSession ?? this.autoStartNextSession,
      adjustDurationAfterSession:
          adjustDurationAfterSession ?? this.adjustDurationAfterSession,
      activeFocusRoomId: activeFocusRoomId ?? this.activeFocusRoomId,
    );
  }
}

class DailyStat {
  final String date;
  final int creditedMinutes;
  final int xpEarned;
  final int coinsEarned;
  final int sessionCount;
  final bool isStreakDay;
  final String? recoveryMode;

  const DailyStat({
    required this.date,
    required this.creditedMinutes,
    required this.xpEarned,
    required this.coinsEarned,
    required this.sessionCount,
    required this.isStreakDay,
    this.recoveryMode,
  });

  factory DailyStat.fromJson(Map<String, dynamic> json) {
    return DailyStat(
      date: json['date'] as String? ?? '',
      creditedMinutes: json['credited_minutes'] as int? ?? 0,
      xpEarned: json['xp_earned'] as int? ?? 0,
      coinsEarned: json['coins_earned'] as int? ?? 0,
      sessionCount: json['session_count'] as int? ?? 0,
      isStreakDay: json['is_streak_day'] as bool? ?? false,
      recoveryMode: json['recovery_mode'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date,
        'credited_minutes': creditedMinutes,
        'xp_earned': xpEarned,
        'coins_earned': coinsEarned,
        'session_count': sessionCount,
        'is_streak_day': isStreakDay,
        'recovery_mode': recoveryMode,
      };
}
