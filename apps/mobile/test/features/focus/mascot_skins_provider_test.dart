import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:meleo/features/focus/data/mascot_skins_api.dart';
import 'package:meleo/features/focus/data/mascot_skins_sync_bus.dart';
import 'package:meleo/features/focus/models/mascot_skin.dart';
import 'package:meleo/features/focus/providers/mascot_skins_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _catalog(int id) => {
  'skins': [
    {
      'id': id,
      'slug': 'skin-$id',
      'tier': 'cheap',
      'price_coins': 0,
      'color1': '#000000',
      'color2': '#000000',
      'color3': '#000000',
      'color4': '#000000',
      'sort_order': 0,
      'owned': true,
      'active': true,
    },
  ],
  'active_skin_id': id,
};

void main() {
  test('cached mascot catalog does not leak between accounts', () async {
    SharedPreferences.setMockInitialValues({
      'mascot_skins_catalog_v1_user-1': jsonEncode(_catalog(1)),
      'mascot_skins_catalog_v1_user-2': jsonEncode(_catalog(2)),
    });

    final first = MascotSkinsNotifier(userId: 'user-1');
    final second = MascotSkinsNotifier(userId: 'user-2');
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    await Future<void>.delayed(Duration.zero);

    expect(first.state.catalog?.activeSkinId, 1);
    expect(second.state.catalog?.activeSkinId, 2);
  });

  test('anonymous mascot state does not hydrate an account cache', () async {
    SharedPreferences.setMockInitialValues({
      'mascot_skins_catalog_v1_user-1': jsonEncode(_catalog(1)),
    });

    final notifier = MascotSkinsNotifier(userId: null);
    addTearDown(notifier.dispose);
    await Future<void>.delayed(Duration.zero);

    expect(notifier.state.catalog, isNull);
  });

  test('dispose before hydration ignores cache and later bus events', () async {
    SharedPreferences.setMockInitialValues({
      'mascot_skins_catalog_v1_user-1': jsonEncode(_catalog(1)),
    });

    final notifier = MascotSkinsNotifier(userId: 'user-1');
    notifier.dispose();
    MascotSkinsSyncBus.push(MascotSkinsCatalog.fromJson(_catalog(2)));
    await Future<void>.delayed(Duration.zero);

    final prefs = await SharedPreferences.getInstance();
    final cached =
        jsonDecode(prefs.getString('mascot_skins_catalog_v1_user-1')!)
            as Map<String, dynamic>;
    expect(cached['active_skin_id'], 1);
  });

  test('fresh bus data is not overwritten by stale cache hydration', () async {
    final cacheRead = Completer<String?>();
    final notifier = MascotSkinsNotifier(
      userId: 'user-1',
      readCache: (_) => cacheRead.future,
      writeCache: (_, __) async {},
    );
    addTearDown(notifier.dispose);

    MascotSkinsSyncBus.push(MascotSkinsCatalog.fromJson(_catalog(2)));
    await Future<void>.delayed(Duration.zero);
    cacheRead.complete(jsonEncode(_catalog(1)));
    await Future<void>.delayed(Duration.zero);

    expect(notifier.state.catalog?.activeSkinId, 2);
  });

  for (final action in ['buy', 'setActive']) {
    test(
      '$action does not call API after disposal during persistence',
      () async {
        final writeStarted = Completer<void>();
        final allowWrite = Completer<void>();
        final api = _FakeMascotSkinsApi();
        final notifier = MascotSkinsNotifier(
          userId: 'user-1',
          api: api,
          readCache: (_) async => jsonEncode(_catalog(1)),
          writeCache: (_, __) async {
            if (!writeStarted.isCompleted) writeStarted.complete();
            await allowWrite.future;
          },
        );
        await Future<void>.delayed(Duration.zero);

        final command = action == 'buy'
            ? notifier.buy(1)
            : notifier.setActive(null);
        await writeStarted.future;
        notifier.dispose();
        allowWrite.complete();
        await command;

        expect(api.calls, 0);
      },
    );
  }
}

class _FakeMascotSkinsApi extends MascotSkinsApi {
  int calls = 0;

  @override
  Future<MascotSkin> buy(int skinId) async {
    calls++;
    return MascotSkinsCatalog.fromJson(_catalog(skinId)).skins.first;
  }

  @override
  Future<MascotSkinsCatalog> setActive(int? skinId) async {
    calls++;
    return MascotSkinsCatalog.fromJson(_catalog(skinId ?? 1));
  }
}
