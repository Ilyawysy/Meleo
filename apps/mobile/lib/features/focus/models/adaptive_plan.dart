enum GrowthSpeed { steady, faster, push }

enum PlanWidgetMode { empty, plan, growth, sprint }

GrowthSpeed? _parseGrowthSpeed(String? value) {
  if (value == null) return null;
  switch (value) {
    case 'steady':
      return GrowthSpeed.steady;
    case 'faster':
      return GrowthSpeed.faster;
    case 'push':
      return GrowthSpeed.push;
    default:
      return null;
  }
}

int weeksToTarget(GrowthSpeed s) {
  switch (s) {
    case GrowthSpeed.steady:
      return 6;
    case GrowthSpeed.faster:
      return 4;
    case GrowthSpeed.push:
      return 2;
  }
}

class AdaptivePlan {
  final List<int>? hoursPerDay;
  final int? growthTargetHours;
  final GrowthSpeed? growthSpeed;
  final DateTime? growthStartedAt;

  const AdaptivePlan({
    this.hoursPerDay,
    this.growthTargetHours,
    this.growthSpeed,
    this.growthStartedAt,
  });

  const AdaptivePlan.empty()
      : hoursPerDay = null,
        growthTargetHours = null,
        growthSpeed = null,
        growthStartedAt = null;

  factory AdaptivePlan.fromJson(Map<String, dynamic> json) {
    List<int>? hoursPerDay;
    final rawHours = json['hours_per_day'];
    if (rawHours is List && rawHours.length == 7) {
      final parsed = rawHours.map((e) => e as int? ?? 0).toList();
      if (parsed.every((h) => h >= 0 && h <= 24)) {
        hoursPerDay = parsed;
      }
    }

    return AdaptivePlan(
      hoursPerDay: hoursPerDay,
      growthTargetHours: json['growth_target_hours'] as int?,
      growthSpeed: _parseGrowthSpeed(json['growth_speed'] as String?),
      growthStartedAt: _parseDate(json['growth_started_at']),
    );
  }

  Map<String, dynamic> toPatchJson({Set<String> clearFields = const {}}) {
    final result = <String, dynamic>{};

    if (clearFields.contains('hours_per_day')) {
      result['hours_per_day'] = null;
    } else if (hoursPerDay != null) {
      result['hours_per_day'] = hoursPerDay;
    }

    if (clearFields.contains('growth_target_hours')) {
      result['growth_target_hours'] = null;
    } else if (growthTargetHours != null) {
      result['growth_target_hours'] = growthTargetHours;
    }

    if (clearFields.contains('growth_speed')) {
      result['growth_speed'] = null;
    } else if (growthSpeed != null) {
      result['growth_speed'] = growthSpeed!.name;
    }

    if (clearFields.contains('growth_started_at')) {
      result['growth_started_at'] = null;
    } else if (growthStartedAt != null) {
      result['growth_started_at'] = growthStartedAt!.toIso8601String();
    }

    return result;
  }

  AdaptivePlan copyWith({
    List<int>? hoursPerDay,
    int? growthTargetHours,
    GrowthSpeed? growthSpeed,
    DateTime? growthStartedAt,
  }) {
    return AdaptivePlan(
      hoursPerDay: hoursPerDay ?? this.hoursPerDay,
      growthTargetHours: growthTargetHours ?? this.growthTargetHours,
      growthSpeed: growthSpeed ?? this.growthSpeed,
      growthStartedAt: growthStartedAt ?? this.growthStartedAt,
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
