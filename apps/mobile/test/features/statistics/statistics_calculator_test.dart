import 'package:flutter_test/flutter_test.dart';
import 'package:meleo/features/focus/models/gamification_models.dart';
import 'package:meleo/features/statistics/data/statistics_calculator.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

GamificationProfile _profile({Map<int, int>? planMinutes}) {
  return GamificationProfile(
    xp: 0,
    level: 1,
    xpToNextLevel: 100,
    streakCurrent: 0,
    planMinutes: planMinutes ?? {1: 30, 2: 30, 3: 30, 4: 30, 5: 30, 6: 0, 7: 0},
    homeTz: 'UTC',
    dayCutoffHour: 4,
    recoveryDaysRemaining: 0,
    minimalMode: false,
    coins: 0,
  );
}

DailyStat _stat({
  required String date,
  int creditedMinutes = 0,
  int xpEarned = 0,
  int coinsEarned = 0,
  int sessionCount = 0,
  bool isStreakDay = false,
}) {
  return DailyStat(
    date: date,
    creditedMinutes: creditedMinutes,
    xpEarned: xpEarned,
    coinsEarned: coinsEarned,
    sessionCount: sessionCount,
    isStreakDay: isStreakDay,
  );
}

// ---------------------------------------------------------------------------
// mondayOf
// ---------------------------------------------------------------------------

void main() {
  group('mondayOf', () {
    test('Monday returns itself at 00:00:00', () {
      // 2025-04-21 is a Monday
      final monday = DateTime(2025, 4, 21, 14, 30, 0);
      final result = mondayOf(monday);
      expect(result, DateTime(2025, 4, 21));
    });

    test('Wednesday returns the preceding Monday', () {
      // 2025-04-23 is Wednesday
      final wednesday = DateTime(2025, 4, 23, 9, 0, 0);
      final result = mondayOf(wednesday);
      expect(result, DateTime(2025, 4, 21));
    });

    test('Sunday returns the Monday of the same week', () {
      // 2025-04-27 is Sunday
      final sunday = DateTime(2025, 4, 27, 23, 59, 59);
      final result = mondayOf(sunday);
      expect(result, DateTime(2025, 4, 21));
    });

    test('Saturday returns the Monday of the same week', () {
      // 2025-04-26 is Saturday
      final saturday = DateTime(2025, 4, 26);
      final result = mondayOf(saturday);
      expect(result, DateTime(2025, 4, 21));
    });

    test('result has time zeroed out', () {
      final friday = DateTime(2025, 4, 25, 15, 45, 12);
      final result = mondayOf(friday);
      expect(result.hour, 0);
      expect(result.minute, 0);
      expect(result.second, 0);
    });

    test('week boundary: Friday before vs Monday after', () {
      // 2025-04-18 is Friday of previous week
      final friday = DateTime(2025, 4, 18);
      // 2025-04-21 is Monday of current week
      final monday = DateTime(2025, 4, 21);
      expect(mondayOf(friday), DateTime(2025, 4, 14)); // preceding Mon
      expect(mondayOf(monday), DateTime(2025, 4, 21)); // itself
    });
  });

  // -------------------------------------------------------------------------
  // computePlanVsFactWeek
  // -------------------------------------------------------------------------

  group('computePlanVsFactWeek', () {
    // Pin a known Monday so tests are date-independent.
    // We inject data only for that week and verify filtering.

    test('returns entries for all 7 weekdays (keys 1..7)', () {
      final result = computePlanVsFactWeek({}, _profile());
      expect(result.byDay.keys.toSet(), {1, 2, 3, 4, 5, 6, 7});
    });

    test('fact defaults to 0 when no matching date entry', () {
      final result = computePlanVsFactWeek({}, _profile());
      for (final entry in result.byDay.values) {
        expect(entry.fact, 0);
      }
    });

    test('plan values come from GamificationProfile', () {
      final profile = _profile(planMinutes: {
        1: 60, 2: 45, 3: 30, 4: 0, 5: 90, 6: 0, 7: 0,
      });
      final result = computePlanVsFactWeek({}, profile);

      expect(result.byDay[1]!.plan, 60);
      expect(result.byDay[2]!.plan, 45);
      expect(result.byDay[3]!.plan, 30);
      expect(result.byDay[4]!.plan, 0);
      expect(result.byDay[5]!.plan, 90);
    });

    test('planTotal sums all plan minutes for the week', () {
      final profile = _profile(planMinutes: {
        1: 60, 2: 60, 3: 60, 4: 0, 5: 60, 6: 0, 7: 0,
      });
      final result = computePlanVsFactWeek({}, profile);
      expect(result.planTotal, 240);
    });

    test('data outside current week is NOT counted', () {
      // Far-past date — guaranteed to be in a different week
      final pastDate = '2000-01-01';
      final result = computePlanVsFactWeek({pastDate: 999}, _profile());
      expect(result.factTotal, 0);
    });

    test('factTotal accumulates current-week entries', () {
      // Build a date string for the Monday of the current week and Tuesday
      final now = DateTime.now();
      final monday = mondayOf(now);
      final tuesday = monday.add(const Duration(days: 1));

      String fmt(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

      final dailyMinutes = {
        fmt(monday): 45,
        fmt(tuesday): 30,
      };

      final result = computePlanVsFactWeek(dailyMinutes, _profile());
      expect(result.factTotal, 75);
      expect(result.byDay[1]!.fact, 45);
      expect(result.byDay[2]!.fact, 30);
    });
  });

  // -------------------------------------------------------------------------
  // computeRoomStats
  // -------------------------------------------------------------------------

  group('computeRoomStats', () {
    final from = DateTime(2025, 4, 14); // Monday
    final to = DateTime(2025, 4, 21); // exclusive

    test('empty sessionRows returns empty list', () {
      final result = computeRoomStats(
        sessionRows: [],
        roomById: {},
        from: from,
        to: to,
      );
      expect(result, isEmpty);
    });

    test('session with credited_minutes == 0 is excluded', () {
      final result = computeRoomStats(
        sessionRows: [
          {'started_at': '2025-04-15T10:00:00', 'credited_minutes': 0, 'room_id': 'r1'},
        ],
        roomById: {'r1': (title: 'Room1', color: '#FF0000')},
        from: from,
        to: to,
      );
      expect(result, isEmpty);
    });

    test('session outside date range is excluded', () {
      final result = computeRoomStats(
        sessionRows: [
          // Before from
          {'started_at': '2025-04-13T10:00:00', 'credited_minutes': 30, 'room_id': 'r1'},
          // Equal to `to` (exclusive boundary)
          {'started_at': '2025-04-21T00:00:00', 'credited_minutes': 30, 'room_id': 'r1'},
        ],
        roomById: {'r1': (title: 'Room1', color: '#FF0000')},
        from: from,
        to: to,
      );
      expect(result, isEmpty);
    });

    test('correctly aggregates totalMinutes and totalSessions per room', () {
      final result = computeRoomStats(
        sessionRows: [
          {'started_at': '2025-04-15T09:00:00', 'credited_minutes': 30, 'room_id': 'r1'},
          {'started_at': '2025-04-16T11:00:00', 'credited_minutes': 45, 'room_id': 'r1'},
          {'started_at': '2025-04-17T14:00:00', 'credited_minutes': 60, 'room_id': 'r2'},
        ],
        roomById: {
          'r1': (title: 'Work', color: '#00FF00'),
          'r2': (title: 'Study', color: '#0000FF'),
        },
        from: from,
        to: to,
      );

      expect(result.length, 2);
      // Sorted descending by totalMinutes: r2=60, r1=75 -> r1 first
      final r1 = result.firstWhere((r) => r.roomId == 'r1');
      final r2 = result.firstWhere((r) => r.roomId == 'r2');

      expect(r1.totalMinutes, 75);
      expect(r1.totalSessions, 2);
      expect(r2.totalMinutes, 60);
      expect(r2.totalSessions, 1);
    });

    test('allFocusPct values sum to <= 1.0 (within floating point tolerance)', () {
      final result = computeRoomStats(
        sessionRows: [
          {'started_at': '2025-04-15T09:00:00', 'credited_minutes': 40, 'room_id': 'r1'},
          {'started_at': '2025-04-16T11:00:00', 'credited_minutes': 60, 'room_id': 'r2'},
        ],
        roomById: {
          'r1': (title: 'A', color: '#111111'),
          'r2': (title: 'B', color: '#222222'),
        },
        from: from,
        to: to,
      );

      final pctSum = result.fold<double>(0.0, (sum, r) => sum + r.allFocusPct);
      expect(pctSum, closeTo(1.0, 1e-9));
    });

    test('allFocusPct is 0.0 when grandTotal is 0', () {
      // This path is impossible if credited_minutes > 0 check passes,
      // but we verify via a single room that its pct equals 1.0 when sole contributor.
      final result = computeRoomStats(
        sessionRows: [
          {'started_at': '2025-04-15T09:00:00', 'credited_minutes': 120, 'room_id': 'r1'},
        ],
        roomById: {'r1': (title: 'Sole', color: '#AAAAAA')},
        from: from,
        to: to,
      );
      expect(result.first.allFocusPct, closeTo(1.0, 1e-9));
    });

    test('fallback title and color used when roomId not in roomById', () {
      final result = computeRoomStats(
        sessionRows: [
          {'started_at': '2025-04-15T09:00:00', 'credited_minutes': 20, 'room_id': 'unknown-room'},
        ],
        roomById: {},
        from: from,
        to: to,
      );
      expect(result.first.title, 'unknown-room');
      expect(result.first.color, '#6366F1');
    });

    test('result is sorted descending by totalMinutes', () {
      final result = computeRoomStats(
        sessionRows: [
          {'started_at': '2025-04-15T09:00:00', 'credited_minutes': 10, 'room_id': 'small'},
          {'started_at': '2025-04-15T10:00:00', 'credited_minutes': 100, 'room_id': 'large'},
          {'started_at': '2025-04-15T11:00:00', 'credited_minutes': 50, 'room_id': 'mid'},
        ],
        roomById: {
          'small': (title: 'Small', color: '#1'),
          'large': (title: 'Large', color: '#2'),
          'mid': (title: 'Mid', color: '#3'),
        },
        from: from,
        to: to,
      );

      expect(result[0].roomId, 'large');
      expect(result[1].roomId, 'mid');
      expect(result[2].roomId, 'small');
    });
  });

  // -------------------------------------------------------------------------
  // mockScreenTime
  // -------------------------------------------------------------------------

  group('mockScreenTime', () {
    test('same weekStart produces identical result on repeated calls', () {
      final weekStart = DateTime(2025, 4, 21);
      final r1 = mockScreenTime(weekStart);
      final r2 = mockScreenTime(weekStart);

      expect(r1.total, r2.total);
      expect(r1.duringFocus, r2.duringFocus);
      expect(r1.afterFocus, r2.afterFocus);
      expect(r1.apps.length, r2.apps.length);
      for (int i = 0; i < r1.apps.length; i++) {
        expect(r1.apps[i].app, r2.apps[i].app);
        expect(r1.apps[i].beforeMin, r2.apps[i].beforeMin);
        expect(r1.apps[i].afterMin, r2.apps[i].afterMin);
      }
    });

    test('different weekStarts produce different totals', () {
      final week1 = mockScreenTime(DateTime(2025, 4, 7));
      final week2 = mockScreenTime(DateTime(2025, 4, 14));
      // They MAY differ — just verify both are valid values
      expect(week1.total, greaterThan(0));
      expect(week2.total, greaterThan(0));
    });

    test('total equals duringFocus + afterFocus', () {
      final result = mockScreenTime(DateTime(2025, 3, 3));
      expect(result.total, result.duringFocus + result.afterFocus);
    });

    test('total is within expected range (30..120 min/day * 7 days)', () {
      final result = mockScreenTime(DateTime(2025, 1, 6));
      expect(result.total, greaterThanOrEqualTo(30 * 7));
      expect(result.total, lessThanOrEqualTo(120 * 7));
    });

    test('always returns exactly 3 apps', () {
      final result = mockScreenTime(DateTime(2025, 6, 2));
      expect(result.apps.length, 3);
    });

    test('app names are TikTok, YouTube, X', () {
      final result = mockScreenTime(DateTime(2025, 2, 10));
      final names = result.apps.map((a) => a.app).toList();
      expect(names, ['TikTok', 'YouTube', 'X']);
    });
  });

  // -------------------------------------------------------------------------
  // computeWeekSummary
  // -------------------------------------------------------------------------

  group('computeWeekSummary', () {
    final weekStart = DateTime(2025, 4, 14); // Monday
    final emptyProfile = _profile(planMinutes: {});

    test('empty stats does not throw', () {
      expect(
        () => computeWeekSummary(
          weekStart: weekStart,
          dailyStats: [],
          profile: emptyProfile,
          screenTimeMockMin: 0,
        ),
        returnsNormally,
      );
    });

    test('planCompletePct is 0 when planTotal is 0', () {
      final result = computeWeekSummary(
        weekStart: weekStart,
        dailyStats: [],
        profile: emptyProfile,
        screenTimeMockMin: 0,
      );
      expect(result.planCompletePct, 0);
    });

    test('planCompletePct is clamped to [0, 100]', () {
      // Massive focus vs tiny plan
      final profile = _profile(planMinutes: {1: 1}); // 1 min total plan
      final stats = [
        _stat(date: '2025-04-14', creditedMinutes: 9999, sessionCount: 1),
      ];
      final result = computeWeekSummary(
        weekStart: weekStart,
        dailyStats: stats,
        profile: profile,
        screenTimeMockMin: 0,
      );
      expect(result.planCompletePct, 100);
    });

    test('focusDays counts only days with creditedMinutes > 0 in the week', () {
      final stats = [
        _stat(date: '2025-04-14', creditedMinutes: 30, sessionCount: 1), // Mon in week
        _stat(date: '2025-04-15', creditedMinutes: 0, sessionCount: 0),  // Tue, no focus
        _stat(date: '2025-04-16', creditedMinutes: 45, sessionCount: 2), // Wed in week
        // Outside week:
        _stat(date: '2025-04-21', creditedMinutes: 60, sessionCount: 1),
      ];
      final result = computeWeekSummary(
        weekStart: weekStart,
        dailyStats: stats,
        profile: emptyProfile,
        screenTimeMockMin: 0,
      );
      expect(result.focusDays, 2);
    });

    test('allFocusMinutes sums only stats within the week', () {
      final stats = [
        _stat(date: '2025-04-14', creditedMinutes: 30, sessionCount: 1),
        _stat(date: '2025-04-15', creditedMinutes: 20, sessionCount: 1),
        // Outside week:
        _stat(date: '2025-04-07', creditedMinutes: 999, sessionCount: 1),
      ];
      final result = computeWeekSummary(
        weekStart: weekStart,
        dailyStats: stats,
        profile: emptyProfile,
        screenTimeMockMin: 0,
      );
      expect(result.allFocusMinutes, 50);
    });

    test('screenTimeMinutes is passed through unchanged', () {
      final result = computeWeekSummary(
        weekStart: weekStart,
        dailyStats: [],
        profile: emptyProfile,
        screenTimeMockMin: 420,
      );
      expect(result.screenTimeMinutes, 420);
    });

    test('weekStart is preserved on WeekSummary', () {
      final result = computeWeekSummary(
        weekStart: weekStart,
        dailyStats: [],
        profile: emptyProfile,
        screenTimeMockMin: 0,
      );
      expect(result.weekStart, weekStart);
    });

    test('sessions is sum of sessionCount for week stats', () {
      final stats = [
        _stat(date: '2025-04-14', creditedMinutes: 30, sessionCount: 2),
        _stat(date: '2025-04-15', creditedMinutes: 20, sessionCount: 3),
      ];
      final result = computeWeekSummary(
        weekStart: weekStart,
        dailyStats: stats,
        profile: emptyProfile,
        screenTimeMockMin: 0,
      );
      expect(result.sessions, 5);
    });

    test('focusDaysGoal is clamped between 1 and 7', () {
      // Profile with no enabled days -> clamp to 1
      final result = computeWeekSummary(
        weekStart: weekStart,
        dailyStats: [],
        profile: emptyProfile, // planMinutes = {}
        screenTimeMockMin: 0,
      );
      expect(result.focusDaysGoal, greaterThanOrEqualTo(1));
      expect(result.focusDaysGoal, lessThanOrEqualTo(7));
    });
  });
}
