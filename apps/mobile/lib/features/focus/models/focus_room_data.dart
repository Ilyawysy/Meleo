import 'task.dart';
import 'focus_models.dart';
import 'gamification_models.dart';

class FocusRoomData {
  final double coins;
  final GamificationProfile? profile;
  final List<ShopItem> items;
  final ActiveItems activeItems;
  final FocusSession? session;
  final Task? sessionTask;
  final String? error;

  const FocusRoomData({
    required this.coins,
    this.profile,
    this.items = const [],
    this.activeItems = const ActiveItems(),
    this.session,
    this.sessionTask,
    this.error,
  });
}
