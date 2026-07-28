import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meleo/core/sync/first_sync_settled_provider.dart';

void main() {
  group('FirstSyncSettledNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state is false', () {
      expect(container.read(firstSyncSettledProvider), isFalse);
    });

    test('markSettled transitions false -> true', () {
      container.read(firstSyncSettledProvider.notifier).markSettled();
      expect(container.read(firstSyncSettledProvider), isTrue);
    });

    test('markSettled is idempotent when already true', () {
      final notifier = container.read(firstSyncSettledProvider.notifier);
      notifier.markSettled();
      notifier.markSettled(); // second call must not throw or flip state
      expect(container.read(firstSyncSettledProvider), isTrue);
    });

    test('reset transitions true -> false', () {
      final notifier = container.read(firstSyncSettledProvider.notifier);
      notifier.markSettled();
      notifier.reset();
      expect(container.read(firstSyncSettledProvider), isFalse);
    });

    test('reset is idempotent when already false', () {
      final notifier = container.read(firstSyncSettledProvider.notifier);
      notifier.reset(); // already false, must not throw
      expect(container.read(firstSyncSettledProvider), isFalse);
    });

    test('full cycle: markSettled -> reset -> markSettled', () {
      final notifier = container.read(firstSyncSettledProvider.notifier);
      notifier.markSettled();
      expect(container.read(firstSyncSettledProvider), isTrue);
      notifier.reset();
      expect(container.read(firstSyncSettledProvider), isFalse);
      notifier.markSettled();
      expect(container.read(firstSyncSettledProvider), isTrue);
    });

    test('two containers are independent — state does not bleed across instances', () {
      final container2 = ProviderContainer();
      addTearDown(container2.dispose);

      container.read(firstSyncSettledProvider.notifier).markSettled();
      // container2 was never touched; must still be false.
      expect(container2.read(firstSyncSettledProvider), isFalse);
    });
  });
}
