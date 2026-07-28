import 'dart:math';

// ---- Debug day offset (shifts "now" for testing streaks/multipliers) ----
// Only used in kDebugMode. Positive = future days, negative = past days.
int debugDayOffset = 0;

DateTime debugNow() => DateTime.now().add(Duration(days: debugDayOffset));

// ---- Constants (mirrored from backend/domain/gamification/calculator.py) ----

const int planDayMinutesStep = 10;
const int defaultDayCutoffHour = 4;

// Streak threshold constants (mirrored from backend)
const double streakPercent = 0.70;
const int streakAbsMinMinutes = 10;

// Ramp-up table: streak_day → minimum minutes
const List<(int, int)> streakRampUp = [
  (1, 15),
  (2, 20),
  (3, 25),
  (4, 30),
  (5, 35),
  (6, 40),
  // 7+ → 45
];
const int streakRampUpMax = 45;
const double recoveryCoinMult = 2.0;

// Streak multiplier table (spec 6.3)
const List<(int, double)> streakMultTable = [
  (1, 1.00),
  (2, 1.05),
  (3, 1.10),
  (4, 1.15),
  (5, 1.20),
  (6, 1.25),
  (7, 1.30),
  (8, 1.35),
  (9, 1.38),
  (10, 1.41),
  (11, 1.44),
  (12, 1.47),
  (13, 1.49),
  // 14+ → 1.50
];

// Shield constants (spec 7)
const int shieldUnlockStreakLen = 3;
const int shieldMaxCharges = 1;
const int shieldRechargeSuccessDays = 2;

// XP level curve (spec 3.1)
const List<(int, int, int)> levelCurveTiers = [
  (1, 5, 120),
  (6, 15, 300),
  (16, 30, 600),
  (31, 999999, 1000),
];

// ---- Pure functions ----

double computeStreakMultiplier(int streakLen) {
  if (streakLen <= 0) return 1.0;
  if (streakLen >= 14) return 1.50;
  for (final (day, mult) in streakMultTable) {
    if (streakLen == day) return mult;
  }
  return 1.0;
}

int rampUpMinutes(int streakDay) {
  for (final (day, minutes) in streakRampUp) {
    if (streakDay == day) return minutes;
  }
  return streakRampUpMax;
}

int streakThreshold(int planMinutesForDay, {int streakDay = 1}) {
  if (planMinutesForDay <= 0) return 0;
  final rampUp = rampUpMinutes(streakDay);
  final percentThreshold = (planMinutesForDay * streakPercent).floor();
  final raw = rampUp < percentThreshold ? rampUp : percentThreshold;
  return raw > streakAbsMinMinutes ? raw : streakAbsMinMinutes;
}

double computeModeMultiplier(bool recoveryActive, int streakLen) {
  if (recoveryActive) return recoveryCoinMult;
  final streakMult = computeStreakMultiplier(streakLen);
  return max(streakMult, 1.0);
}

// ---- XP levels (new curve) ----

int xpForLevel(int level) {
  if (level <= 0) return 0;
  for (final (lo, hi, increment) in levelCurveTiers) {
    if (level >= lo && level <= hi) return increment;
  }
  return levelCurveTiers.last.$3;
}

int cumulativeXpForLevel(int level) {
  if (level <= 0) return 0;
  var total = 0;
  for (var lvl = 1; lvl <= level; lvl++) {
    total += xpForLevel(lvl);
  }
  return total;
}

int computeXpLevel(int totalXp) {
  if (totalXp < xpForLevel(1)) return 0;
  var level = 0;
  var cumulative = 0;
  while (true) {
    final nextLevelXp = xpForLevel(level + 1);
    if (cumulative + nextLevelXp > totalXp) break;
    cumulative += nextLevelXp;
    level += 1;
  }
  return level;
}

int xpToNextLevel(int totalXp) {
  final currentLevel = computeXpLevel(totalXp);
  return cumulativeXpForLevel(currentLevel + 1) - totalXp;
}

// ---- FocusDate helper ----

DateTime focusDate(DateTime timestamp, String homeTz, int cutoffHour) {
  // In Flutter we don't have ZoneInfo; we use the local time or UTC.
  // For offline calculations, we use the device local time.
  final localDt = timestamp.toLocal();
  if (localDt.hour < cutoffHour) {
    return DateTime(localDt.year, localDt.month, localDt.day - 1);
  }
  return DateTime(localDt.year, localDt.month, localDt.day);
}
