import 'package:flutter_riverpod/flutter_riverpod.dart';

class FirstSyncSettledNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void markSettled() {
    if (!state) state = true;
  }

  void reset() {
    if (state) state = false;
  }
}

final firstSyncSettledProvider =
    NotifierProvider<FirstSyncSettledNotifier, bool>(
  FirstSyncSettledNotifier.new,
);
