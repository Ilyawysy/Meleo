import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:meleo/core/sync/aggregated_sync_service.dart';

void main() {
  group('AggregatedSyncService', () {
    test('pagination is capped at 5 pages and flags resync', () async {
      var fetchCount = 0;
      final adaptiveSignals = <bool>[];

      final service = AggregatedSyncService(
        delayFn: (_) async {},
        isAuthenticatedFn: () async => true,
        onSyncComplete: ({required hasChanges}) {
          adaptiveSignals.add(hasChanges);
        },
        fetchOverride: (_, __) async {
          fetchCount++;
          return _okResponse(
            cursor: 'cursor-$fetchCount',
            hasMore: true,
          );
        },
        processOverride: (_) async => 1,
      );

      final result = await service.sync();

      expect(fetchCount, AggregatedSyncService.maxPagesPerTick);
      expect(result.hasChanges, isTrue);
      expect(result.needsResync, isTrue);
      expect(adaptiveSignals, [true]);
    });

    test('mutex keeps pending sync via _needsResync flag', () async {
      var fetchCount = 0;
      final firstPageGate = Completer<void>();

      final service = AggregatedSyncService(
        delayFn: (_) async {},
        isAuthenticatedFn: () async => true,
        fetchOverride: (_, __) async {
          fetchCount++;
          if (fetchCount == 1) {
            await firstPageGate.future;
          }
          return _okResponse(
            cursor: 'cursor-$fetchCount',
            hasMore: false,
          );
        },
        processOverride: (_) async => 0,
      );

      final firstSync = service.sync();
      await Future<void>.delayed(Duration.zero);
      final secondResult = await service.sync();

      expect(secondResult.hasChanges, isFalse);
      expect(secondResult.needsResync, isTrue);

      firstPageGate.complete();
      final firstResult = await firstSync;

      expect(firstResult.hasChanges, isFalse);
      expect(firstResult.needsResync, isTrue);

      final drainedResult = await service.sync();
      expect(fetchCount, 2);
      expect(drainedResult.needsResync, isFalse);
    });

    test('throws rate-limited exception with parsed retry-after', () async {
      final service = AggregatedSyncService(
        isAuthenticatedFn: () async => true,
        fetchOverride: (_, __) async => http.Response(
          '',
          429,
          headers: {'retry-after': '7'},
        ),
      );

      await expectLater(
        service.sync(),
        throwsA(
          isA<SyncRateLimitedException>().having(
            (e) => e.retryAfter?.inSeconds,
            'retryAfterSeconds',
            7,
          ),
        ),
      );
    });
  });
}

http.Response _okResponse({
  required String cursor,
  required bool hasMore,
}) {
  final body = jsonEncode({
    'cursor': cursor,
    'changes': {
      'tasks': [],
      'notifications': [],
      'messages': [],
      'announcements': [],
    },
    'has_more': {
      'tasks': hasMore,
      'notifications': hasMore,
      'messages': hasMore,
      'announcements': hasMore,
    },
  });

  return http.Response(
    body,
    200,
    headers: {'etag': '"etag-test"'},
  );
}
