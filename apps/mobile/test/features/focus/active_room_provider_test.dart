import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meleo/core/providers/inner_scope.dart';
import 'package:meleo/core/providers/session_scope.dart';
import 'package:meleo/features/focus/providers/active_room_provider.dart';

void main() {
  test('local-only active room is pushed after remote id appears', () async {
    final cache = <String, String>{};
    String? remoteId;
    final pushed = <String?>[];
    final provider = NotifierProvider<ActiveRoomNotifier, String?>(
      () => ActiveRoomNotifier(
        readCache: (key) async => cache[key],
        saveCache: (key, value) async => cache[key] = value,
        getRemoteId: (_) async => remoteId,
        setActiveRoom: (id) async => pushed.add(id),
      ),
      dependencies: [domainScopeToken, sessionScopeProvider],
    );
    final container = ProviderContainer(
      overrides: [domainScopeToken.overrideWithValue(0)],
    );
    addTearDown(container.dispose);
    container.read(sessionScopeProvider.notifier).login('user-1');

    final notifier = container.read(provider.notifier);
    await notifier.set('local-room');

    expect(container.read(provider), 'local-room');
    expect(cache['active_focus_room_local_id_pending_user-1'], 'local-room');
    expect(pushed, isEmpty);

    remoteId = 'remote-room';
    await notifier.tryResolvePending();

    expect(pushed, ['remote-room']);
    expect(cache['active_focus_room_local_id_pending_user-1'], isEmpty);
  });

  test('failed deferred push remains pending for retry', () async {
    final cache = <String, String>{};
    var shouldFail = true;
    var calls = 0;
    final provider = NotifierProvider<ActiveRoomNotifier, String?>(
      () => ActiveRoomNotifier(
        readCache: (key) async => cache[key],
        saveCache: (key, value) async => cache[key] = value,
        getRemoteId: (_) async => 'remote-room',
        setActiveRoom: (_) async {
          calls++;
          if (shouldFail) throw Exception('offline');
        },
      ),
      dependencies: [domainScopeToken, sessionScopeProvider],
    );
    final container = ProviderContainer(
      overrides: [domainScopeToken.overrideWithValue(0)],
    );
    addTearDown(container.dispose);
    container.read(sessionScopeProvider.notifier).login('user-1');

    final notifier = container.read(provider.notifier);
    await notifier.set('local-room');
    expect(cache['active_focus_room_local_id_pending_user-1'], 'local-room');

    shouldFail = false;
    await notifier.tryResolvePending();

    expect(calls, 2);
    expect(cache['active_focus_room_local_id_pending_user-1'], isEmpty);
  });

  test('active room cache is scoped by account', () async {
    final cache = <String, String>{
      'active_focus_room_id_user-1': 'room-1',
      'active_focus_room_id_user-2': 'room-2',
    };
    final provider = NotifierProvider<ActiveRoomNotifier, String?>(
      () => ActiveRoomNotifier(
        readCache: (key) async => cache[key],
        saveCache: (key, value) async => cache[key] = value,
      ),
      dependencies: [domainScopeToken, sessionScopeProvider],
    );
    final firstContainer = ProviderContainer(
      overrides: [domainScopeToken.overrideWithValue(0)],
    );
    addTearDown(firstContainer.dispose);
    firstContainer.read(sessionScopeProvider.notifier).login('user-1');
    firstContainer.read(provider);
    await Future<void>.delayed(Duration.zero);
    expect(firstContainer.read(provider), 'room-1');

    final secondContainer = ProviderContainer(
      overrides: [domainScopeToken.overrideWithValue(1)],
    );
    addTearDown(secondContainer.dispose);
    secondContainer.read(sessionScopeProvider.notifier).login('user-2');
    secondContainer.read(provider);
    await Future<void>.delayed(Duration.zero);
    expect(secondContainer.read(provider), 'room-2');
  });

  test('local selection clears and wins over stale remote pending', () async {
    final cache = <String, String>{
      'active_focus_room_remote_id_pending_user-1': 'stale-remote',
    };
    var remoteResolveCalls = 0;
    final provider = NotifierProvider<ActiveRoomNotifier, String?>(
      () => ActiveRoomNotifier(
        readCache: (key) async => cache[key],
        saveCache: (key, value) async => cache[key] = value,
        getRemoteId: (_) async => null,
        resolveRemoteId: (_) async {
          remoteResolveCalls++;
          return 'stale-local';
        },
      ),
      dependencies: [domainScopeToken, sessionScopeProvider],
    );
    final container = ProviderContainer(
      overrides: [domainScopeToken.overrideWithValue(0)],
    );
    addTearDown(container.dispose);
    container.read(sessionScopeProvider.notifier).login('user-1');

    final notifier = container.read(provider.notifier);
    await notifier.set('new-local');
    await notifier.tryResolvePending();

    expect(cache['active_focus_room_remote_id_pending_user-1'], isEmpty);
    expect(cache['active_focus_room_local_id_pending_user-1'], 'new-local');
    expect(container.read(provider), 'new-local');
    expect(remoteResolveCalls, 0);
  });

  test('account rotation invalidates in-flight active room work', () async {
    final cache = <String, String>{};
    final lookupStarted = Completer<void>();
    final remoteId = Completer<String?>();
    final pushed = <String?>[];
    final provider = NotifierProvider<ActiveRoomNotifier, String?>(
      () => ActiveRoomNotifier(
        readCache: (key) async => cache[key],
        saveCache: (key, value) async => cache[key] = value,
        getRemoteId: (_) {
          lookupStarted.complete();
          return remoteId.future;
        },
        setActiveRoom: (id) async => pushed.add(id),
      ),
      dependencies: [domainScopeToken, sessionScopeProvider],
    );
    final container = ProviderContainer(
      overrides: [domainScopeToken.overrideWithValue(0)],
    );
    addTearDown(container.dispose);
    container.read(sessionScopeProvider.notifier).login('user-1');

    final pendingSet = container
        .read(provider.notifier)
        .set('user-1-local-room');
    await lookupStarted.future;
    container.read(sessionScopeProvider.notifier).login('user-2');
    container.read(provider);
    remoteId.complete('user-1-remote-room');
    await pendingSet;

    expect(pushed, isEmpty);
    expect(
      cache.containsKey('active_focus_room_local_id_pending_user-2'),
      isFalse,
    );
  });

  test('latest overlapping selection is the only one pushed', () async {
    final cache = <String, String>{};
    final firstStarted = Completer<void>();
    final secondStarted = Completer<void>();
    final firstRemote = Completer<String?>();
    final secondRemote = Completer<String?>();
    final pushed = <String?>[];
    final provider = NotifierProvider<ActiveRoomNotifier, String?>(
      () => ActiveRoomNotifier(
        readCache: (key) async => cache[key],
        saveCache: (key, value) async => cache[key] = value,
        getRemoteId: (localId) {
          if (localId == 'first') {
            firstStarted.complete();
            return firstRemote.future;
          }
          secondStarted.complete();
          return secondRemote.future;
        },
        setActiveRoom: (id) async => pushed.add(id),
      ),
      dependencies: [domainScopeToken, sessionScopeProvider],
    );
    final container = ProviderContainer(
      overrides: [domainScopeToken.overrideWithValue(0)],
    );
    addTearDown(container.dispose);
    container.read(sessionScopeProvider.notifier).login('user-1');

    final notifier = container.read(provider.notifier);
    final first = notifier.set('first');
    await firstStarted.future;
    final second = notifier.set('second');
    firstRemote.complete('remote-first');
    await secondStarted.future;
    secondRemote.complete('remote-second');
    await Future.wait([first, second]);

    expect(container.read(provider), 'second');
    expect(cache['active_focus_room_id_user-1'], 'second');
    expect(pushed, ['remote-second']);
  });

  test(
    'sync starting after set cannot overwrite its pending selection',
    () async {
      final cache = <String, String>{};
      var remoteResolveCalls = 0;
      final provider = NotifierProvider<ActiveRoomNotifier, String?>(
        () => ActiveRoomNotifier(
          readCache: (key) async => cache[key],
          saveCache: (key, value) async => cache[key] = value,
          getRemoteId: (_) async => null,
          resolveRemoteId: (_) async {
            remoteResolveCalls++;
            return 'stale-local';
          },
        ),
        dependencies: [domainScopeToken, sessionScopeProvider],
      );
      final container = ProviderContainer(
        overrides: [domainScopeToken.overrideWithValue(0)],
      );
      addTearDown(container.dispose);
      container.read(sessionScopeProvider.notifier).login('user-1');

      final notifier = container.read(provider.notifier);
      final setFuture = notifier.set('new-local');
      final syncFuture = notifier.applyFromSync('stale-remote');
      await Future.wait([setFuture, syncFuture]);

      expect(container.read(provider), 'new-local');
      expect(cache['active_focus_room_id_user-1'], 'new-local');
      expect(cache['active_focus_room_local_id_pending_user-1'], 'new-local');
      expect(remoteResolveCalls, 0);
    },
  );

  test('new set finishes after an older pending server request', () async {
    final cache = <String, String>{
      'active_focus_room_local_id_pending_user-1': 'old-local',
    };
    final oldRequestStarted = Completer<void>();
    final finishOldRequest = Completer<void>();
    final pushed = <String?>[];
    final provider = NotifierProvider<ActiveRoomNotifier, String?>(
      () => ActiveRoomNotifier(
        readCache: (key) async => cache[key],
        saveCache: (key, value) async => cache[key] = value,
        getRemoteId: (localId) async => 'remote-$localId',
        setActiveRoom: (remoteId) async {
          if (remoteId == 'remote-old-local') {
            oldRequestStarted.complete();
            await finishOldRequest.future;
          }
          pushed.add(remoteId);
        },
      ),
      dependencies: [domainScopeToken, sessionScopeProvider],
    );
    final container = ProviderContainer(
      overrides: [domainScopeToken.overrideWithValue(0)],
    );
    addTearDown(container.dispose);
    container.read(sessionScopeProvider.notifier).login('user-1');

    final notifier = container.read(provider.notifier);
    final oldResolve = notifier.tryResolvePending();
    await oldRequestStarted.future;
    final newSet = notifier.set('new-local');
    finishOldRequest.complete();
    await Future.wait([oldResolve, newSet]);

    expect(pushed, ['remote-old-local', 'remote-new-local']);
    expect(container.read(provider), 'new-local');
    expect(cache['active_focus_room_id_user-1'], 'new-local');
    expect(cache['active_focus_room_local_id_pending_user-1'], isEmpty);
  });

  test('resolver clears only the exact remote pending value it read', () async {
    final cache = <String, String>{
      'active_focus_room_remote_id_pending_user-1': 'old-remote',
    };
    final resolveStarted = Completer<void>();
    final resolvedLocal = Completer<String?>();
    final provider = NotifierProvider<ActiveRoomNotifier, String?>(
      () => ActiveRoomNotifier(
        readCache: (key) async => cache[key],
        saveCache: (key, value) async => cache[key] = value,
        resolveRemoteId: (_) {
          resolveStarted.complete();
          return resolvedLocal.future;
        },
      ),
      dependencies: [domainScopeToken, sessionScopeProvider],
    );
    final container = ProviderContainer(
      overrides: [domainScopeToken.overrideWithValue(0)],
    );
    addTearDown(container.dispose);
    container.read(sessionScopeProvider.notifier).login('user-1');

    final resolving = container.read(provider.notifier).tryResolvePending();
    await resolveStarted.future;
    cache['active_focus_room_remote_id_pending_user-1'] = 'new-remote';
    resolvedLocal.complete('old-local');
    await resolving;

    expect(cache['active_focus_room_remote_id_pending_user-1'], 'new-remote');
  });

  test(
    'account switch resets prior account in-memory pending selection',
    () async {
      final cache = <String, String>{};
      final provider = NotifierProvider<ActiveRoomNotifier, String?>(
        () => ActiveRoomNotifier(
          readCache: (key) async => cache[key],
          saveCache: (key, value) async => cache[key] = value,
          getRemoteId: (_) async => null,
          resolveRemoteId: (remoteId) async => 'local-$remoteId',
        ),
        dependencies: [domainScopeToken, sessionScopeProvider],
      );
      final container = ProviderContainer(
        overrides: [domainScopeToken.overrideWithValue(0)],
      );
      addTearDown(container.dispose);
      container.read(sessionScopeProvider.notifier).login('user-1');

      final notifier = container.read(provider.notifier);
      await notifier.set('user-1-local');
      container.read(sessionScopeProvider.notifier).login('user-2');
      container.read(provider);
      await notifier.applyFromSync('user-2-remote');

      expect(container.read(provider), 'local-user-2-remote');
      expect(cache['active_focus_room_id_user-2'], 'local-user-2-remote');
    },
  );

  test('failed clear allows later sync reconciliation', () async {
    final cache = <String, String>{};
    final provider = NotifierProvider<ActiveRoomNotifier, String?>(
      () => ActiveRoomNotifier(
        readCache: (key) async => cache[key],
        saveCache: (key, value) async => cache[key] = value,
        setActiveRoom: (_) async => throw Exception('offline'),
        resolveRemoteId: (remoteId) async => 'local-$remoteId',
      ),
      dependencies: [domainScopeToken, sessionScopeProvider],
    );
    final container = ProviderContainer(
      overrides: [domainScopeToken.overrideWithValue(0)],
    );
    addTearDown(container.dispose);
    container.read(sessionScopeProvider.notifier).login('user-1');

    final notifier = container.read(provider.notifier);
    await notifier.set(null);
    await notifier.applyFromSync('server-active');

    expect(container.read(provider), 'local-server-active');
    expect(cache['active_focus_room_id_user-1'], 'local-server-active');
  });
}
