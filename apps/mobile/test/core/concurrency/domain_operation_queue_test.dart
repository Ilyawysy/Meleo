import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:meleo/core/concurrency/domain_operation_queue.dart';

void main() {
  group('DomainOperationQueue', () {
    test('executes single operation immediately', () async {
      final queue = DomainOperationQueue();
      final result = await queue.run(() async => 42);
      expect(result, 42);
    });

    test('executes operations in FIFO order', () async {
      final queue = DomainOperationQueue();
      final order = <int>[];
      final completer1 = Completer<void>();

      // First op blocks until completer1 completes
      final f1 = queue.run(() async {
        await completer1.future;
        order.add(1);
      });

      // Second and third ops are queued
      final f2 = queue.run(() async {
        order.add(2);
      });
      final f3 = queue.run(() async {
        order.add(3);
      });

      // Nothing has executed yet (first op is waiting)
      expect(order, isEmpty);

      // Release first op
      completer1.complete();
      await Future.wait([f1, f2, f3]);

      expect(order, [1, 2, 3]);
    });

    test('propagates errors without blocking subsequent operations', () async {
      final queue = DomainOperationQueue();

      // First op throws
      expect(
        queue.run(() async => throw Exception('boom')),
        throwsException,
      );

      // Second op still runs
      final result = await queue.run(() async => 'ok');
      expect(result, 'ok');
    });

    test('returns correct typed result for each operation', () async {
      final queue = DomainOperationQueue();

      final intResult = await queue.run(() async => 123);
      final stringResult = await queue.run(() async => 'hello');
      final listResult = await queue.run(() async => [1, 2, 3]);

      expect(intResult, 123);
      expect(stringResult, 'hello');
      expect(listResult, [1, 2, 3]);
    });

    test('concurrent run calls are serialized', () async {
      final queue = DomainOperationQueue();
      var counter = 0;

      // Launch 10 concurrent increments
      final futures = List.generate(10, (_) {
        return queue.run(() async {
          final current = counter;
          // Simulate async gap
          await Future.delayed(Duration.zero);
          counter = current + 1;
        });
      });

      await Future.wait(futures);
      // Without serialization this would be less than 10
      expect(counter, 10);
    });
  });
}
