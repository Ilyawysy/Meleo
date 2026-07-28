import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../focus/data/focus_db.dart';
import '../domain/subscription_state.dart';

final subscriptionProvider = StateNotifierProvider<SubscriptionNotifier, SubscriptionState>(
  (ref) => SubscriptionNotifier(),
);

class SubscriptionNotifier extends StateNotifier<SubscriptionState> {
  SubscriptionNotifier() : super(SubscriptionState.free());

  /// True after loadFromDb has been called at least once.
  bool isLoaded = false;

  Future<void> loadFromDb() async {
    final data = await FocusDb().getSubscription();
    if (data != null) {
      state = SubscriptionState.fromJson(data);
    }
    isLoaded = true;
  }

  void update(SubscriptionState newState) {
    state = newState;
  }

  void incrementChatUsed() {
    state = state.copyWithIncrementedChat();
  }
}
