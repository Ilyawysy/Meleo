import 'package:flutter/foundation.dart';

enum ShopItemCategory { hat, top, bottom, shoes, accessory, theme, aura, skin, environment }

enum FocusSessionStatus {
  created,
  running,
  paused,
  finished,
  cancelled,
}

class Balance {
  final double coins;
  const Balance({required this.coins});

  factory Balance.fromJson(Map<String, dynamic> json) {
    return Balance(coins: (json['coins'] as num?)?.toDouble() ?? 0.0);
  }
}

class ShopItem {
  final String id;
  final String name;
  final ShopItemCategory category;
  final double price;
  final bool owned;
  final int requiredLevel;

  const ShopItem({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.owned,
    this.requiredLevel = 0,
  });

  factory ShopItem.fromJson(Map<String, dynamic> json) {
    return ShopItem(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      category: _parseCategory(json['category'] as String?),
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      owned: json['owned'] as bool? ?? false,
      requiredLevel: json['required_level'] as int? ?? 0,
    );
  }

  static ShopItemCategory _parseCategory(String? value) {
    switch (value) {
      case 'hat':
        return ShopItemCategory.hat;
      case 'top':
        return ShopItemCategory.top;
      case 'bottom':
        return ShopItemCategory.bottom;
      case 'shoes':
        return ShopItemCategory.shoes;
      case 'accessory':
        return ShopItemCategory.accessory;
      case 'theme':
        return ShopItemCategory.theme;
      case 'aura':
        return ShopItemCategory.aura;
      case 'skin':
        return ShopItemCategory.skin;
      case 'environment':
        return ShopItemCategory.environment;
      default:
        debugPrint('Unknown category: $value');
        return ShopItemCategory.accessory;
    }
  }

  ShopItem copyWith({bool? owned, int? requiredLevel}) {
    return ShopItem(
      id: id,
      name: name,
      category: category,
      price: price,
      owned: owned ?? this.owned,
      requiredLevel: requiredLevel ?? this.requiredLevel,
    );
  }
}

class ActiveItems {
  final String? aura;
  final String? skin;
  final String? environment;

  const ActiveItems({this.aura, this.skin, this.environment});

  factory ActiveItems.fromJson(Map<String, dynamic> json) {
    final items = json['active_items'] as Map<String, dynamic>? ?? json;
    return ActiveItems(
      aura: items['aura'] as String?,
      skin: items['skin'] as String?,
      environment: items['environment'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'aura': aura,
    'skin': skin,
    'environment': environment,
  };

  ActiveItems copyWith({
    String? aura,
    String? skin,
    String? environment,
    bool clearAura = false,
    bool clearSkin = false,
    bool clearEnvironment = false,
  }) {
    return ActiveItems(
      aura: clearAura ? null : (aura ?? this.aura),
      skin: clearSkin ? null : (skin ?? this.skin),
      environment: clearEnvironment ? null : (environment ?? this.environment),
    );
  }
}

class FocusSession {
  final String id;
  final String? roomId;
  final int plannedDurationSec;
  final FocusSessionStatus status;
  final int activeElapsedSec;
  final DateTime? lastStateChangeAt;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final String? taskId;
  final double earnedCoins;
  final int? creditedMinutes;
  final int earnedXp;
  final DateTime? sessionDay;

  const FocusSession({
    required this.id,
    this.roomId,
    required this.plannedDurationSec,
    required this.status,
    required this.activeElapsedSec,
    required this.lastStateChangeAt,
    required this.startedAt,
    required this.endedAt,
    required this.taskId,
    required this.earnedCoins,
    this.creditedMinutes,
    this.earnedXp = 0,
    this.sessionDay,
  });

  factory FocusSession.fromJson(Map<String, dynamic> json) {
    return FocusSession(
      id: json['id'] as String,
      roomId: json['room_id'] as String?,
      plannedDurationSec: json['planned_duration_sec'] as int? ?? 0,
      status: _parseStatus(json['status'] as String?),
      activeElapsedSec: json['active_elapsed_sec'] as int? ?? 0,
      lastStateChangeAt: _parseDate(json['last_state_change_at']),
      startedAt: _parseDate(json['started_at']),
      endedAt: _parseDate(json['ended_at']),
      taskId: json['task_id'] as String?,
      earnedCoins: (json['earned_coins'] as num?)?.toDouble() ?? 0.0,
      creditedMinutes: json['credited_minutes'] as int?,
      earnedXp: json['earned_xp'] as int? ?? 0,
      sessionDay: _parseDate(json['session_day']),
    );
  }

  FocusSession copyWith({
    FocusSessionStatus? status,
    int? activeElapsedSec,
    DateTime? lastStateChangeAt,
    DateTime? startedAt,
    DateTime? endedAt,
    String? taskId,
    double? earnedCoins,
    int? creditedMinutes,
    int? earnedXp,
    DateTime? sessionDay,
  }) {
    return FocusSession(
      id: id,
      plannedDurationSec: plannedDurationSec,
      status: status ?? this.status,
      activeElapsedSec: activeElapsedSec ?? this.activeElapsedSec,
      lastStateChangeAt: lastStateChangeAt ?? this.lastStateChangeAt,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      taskId: taskId ?? this.taskId,
      earnedCoins: earnedCoins ?? this.earnedCoins,
      creditedMinutes: creditedMinutes ?? this.creditedMinutes,
      earnedXp: earnedXp ?? this.earnedXp,
      sessionDay: sessionDay ?? this.sessionDay,
    );
  }

  static FocusSessionStatus _parseStatus(String? value) {
    switch (value) {
      case 'created':
        return FocusSessionStatus.created;
      case 'running':
        return FocusSessionStatus.running;
      case 'finished':
        return FocusSessionStatus.finished;
      case 'paused':
        return FocusSessionStatus.paused;
      case 'stopped':
      case 'cancelled':
        return FocusSessionStatus.cancelled;
      // Legacy mapping for cached data from older versions
      case 'stopped_pending_credit':
      case 'credited_undoable':
      case 'credited_final':
        return FocusSessionStatus.finished;
      case 'awaiting_confirm':
      case 'completed':
        return FocusSessionStatus.cancelled;
      default:
        debugPrint('Unknown status: $value');
        return FocusSessionStatus.created;
    }
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}

class FocusTaskSegment {
  final String id;
  final String sessionId;
  final String taskId;
  final DateTime startedAt;
  final DateTime? endedAt;

  const FocusTaskSegment({
    required this.id,
    required this.sessionId,
    required this.taskId,
    required this.startedAt,
    this.endedAt,
  });

  int get durationSec {
    final end = endedAt ?? DateTime.now();
    return end.difference(startedAt).inSeconds;
  }

  Map<String, dynamic> toJson() => {
    'task_id': taskId,
    'started_at': startedAt.toUtc().toIso8601String(),
    'ended_at': endedAt?.toUtc().toIso8601String(),
  };

  factory FocusTaskSegment.fromJson(Map<String, dynamic> json) {
    return FocusTaskSegment(
      id: json['id'] as String,
      sessionId: json['session_id'] as String,
      taskId: json['task_id'] as String,
      startedAt: DateTime.parse(json['started_at'] as String),
      endedAt: json['ended_at'] != null
          ? DateTime.parse(json['ended_at'] as String)
          : null,
    );
  }

  factory FocusTaskSegment.fromRow(Map<String, Object?> row) {
    return FocusTaskSegment(
      id: row['id'] as String,
      sessionId: row['session_id'] as String,
      taskId: row['task_id'] as String,
      startedAt: DateTime.parse(row['started_at'] as String),
      endedAt: row['ended_at'] != null
          ? DateTime.parse(row['ended_at'] as String)
          : null,
    );
  }
}
