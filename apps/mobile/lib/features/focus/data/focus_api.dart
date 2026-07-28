import 'dart:convert';
import '../../../core/api_client.dart';
import '../../../core/api_http_exception.dart';
import '../models/focus_models.dart';
import '../models/gamification_models.dart';

class FocusApi {
  final _client = ApiClient();

  /// Fetch shop catalog with ETag caching.
  /// Returns null on 304 (not modified).
  Future<List<Map<String, dynamic>>?> getCatalog({String? etag}) async {
    final headers = <String, String>{};
    if (etag != null) {
      headers['If-None-Match'] = etag;
    }
    final r = await _client.send(
      'GET',
      _client.uri('/api/v1/shop/catalog'),
      headers: headers,
    );
    if (r.statusCode == 304) return null;
    if (r.statusCode != 200) {
      throw ApiHttpException(
        method: 'GET',
        path: '/api/v1/shop/catalog',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
    final list = json.decode(r.body) as List<dynamic>;
    return list.map((e) => e as Map<String, dynamic>).toList();
  }

  Future<Balance> getBalance() async {
    final r = await _client.send('GET', _client.uri('/api/v1/balance'));
    if (r.statusCode != 200) {
      throw ApiHttpException(
        method: 'GET',
        path: '/api/v1/balance',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
    return Balance.fromJson(json.decode(r.body) as Map<String, dynamic>);
  }

  Future<({Balance balance, List<ShopItem> shopItems, GamificationProfile profile, ActiveItems activeItems})>
      getSnapshot() async {
    final r = await _client.send('GET', _client.uri('/api/v1/focus/snapshot'));
    if (r.statusCode != 200) {
      throw ApiHttpException(
        method: 'GET',
        path: '/api/v1/focus/snapshot',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
    final obj = json.decode(r.body) as Map<String, dynamic>;
    final balance = Balance.fromJson(obj['balance'] as Map<String, dynamic>);
    final shopItems = (obj['shop_items'] as List<dynamic>)
        .map((e) => ShopItem.fromJson(e as Map<String, dynamic>))
        .toList();
    final profile = GamificationProfile.fromJson(obj['profile'] as Map<String, dynamic>);
    final activeItems = ActiveItems.fromJson(obj['active_items'] as Map<String, dynamic>? ?? {});
    return (balance: balance, shopItems: shopItems, profile: profile, activeItems: activeItems);
  }

  Future<ActiveItems> getActiveItems() async {
    final r = await _client.send('GET', _client.uri('/api/v1/shop/active-items'));
    if (r.statusCode != 200) {
      throw ApiHttpException(
        method: 'GET',
        path: '/api/v1/shop/active-items',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
    return ActiveItems.fromJson(json.decode(r.body) as Map<String, dynamic>);
  }

  Future<ActiveItems> activateItem(String itemId) async {
    final r = await _client.send(
      'POST',
      _client.uri('/api/v1/shop/activate'),
      body: {'item_id': itemId},
    );
    if (r.statusCode != 200) {
      throw ApiHttpException(
        method: 'POST',
        path: '/api/v1/shop/activate',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
    return ActiveItems.fromJson(json.decode(r.body) as Map<String, dynamic>);
  }

  Future<ActiveItems> deactivateItem(String category) async {
    final r = await _client.send(
      'POST',
      _client.uri('/api/v1/shop/deactivate'),
      body: {'category': category},
    );
    if (r.statusCode != 200) {
      throw ApiHttpException(
        method: 'POST',
        path: '/api/v1/shop/deactivate',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
    return ActiveItems.fromJson(json.decode(r.body) as Map<String, dynamic>);
  }

  Future<List<ShopItem>> listShopItems() async {
    final r = await _client.send('GET', _client.uri('/api/v1/shop/items'));
    if (r.statusCode != 200) {
      throw ApiHttpException(
        method: 'GET',
        path: '/api/v1/shop/items',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
    final list = json.decode(r.body) as List<dynamic>;
    return list
        .map((e) => ShopItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Balance> purchaseItem(String itemId) async {
    final r = await _client.send(
      'POST',
      _client.uri('/api/v1/shop/purchase'),
      body: {'item_id': itemId},
    );
    if (r.statusCode != 200) {
      throw ApiHttpException(
        method: 'POST',
        path: '/api/v1/shop/purchase',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
    final obj = json.decode(r.body) as Map<String, dynamic>;
    return Balance.fromJson(obj['balance'] as Map<String, dynamic>);
  }

  Future<List<FocusSession>> listSessions({
    required int limit,
    required int offset,
  }) async {
    final r = await _client.send(
      'GET',
      _client.uri('/api/v1/focus-sessions', {
        'limit': limit,
        'offset': offset,
      }),
    );
    if (r.statusCode != 200) {
      throw ApiHttpException(
        method: 'GET',
        path: '/api/v1/focus-sessions',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
    final list = json.decode(r.body) as List<dynamic>;
    return list
        .map((e) => FocusSession.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<FocusSession> createSession({
    required int plannedDurationSec,
    required String roomId,
    String? taskId,
  }) async {
    final r = await _client.send(
      'POST',
      _client.uri('/api/v1/focus-sessions'),
      body: {
        'planned_duration_sec': plannedDurationSec,
        'room_id': roomId,
        if (taskId != null) 'task_id': taskId,
      },
    );
    if (r.statusCode != 201 && r.statusCode != 200) {
      throw ApiHttpException(
        method: 'POST',
        path: '/api/v1/focus-sessions',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
    return FocusSession.fromJson(json.decode(r.body) as Map<String, dynamic>);
  }

  Future<(FocusSession, Balance?)> updateSessionState({
    required String sessionId,
    required String action,
  }) async {
    final r = await _client.send(
      'POST',
      _client.uri('/api/v1/focus-sessions/$sessionId/state'),
      body: {
        'action': action,
      },
    );
    if (r.statusCode != 200) {
      throw ApiHttpException(
        method: 'POST',
        path: '/api/v1/focus-sessions/$sessionId/state',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
    final obj = json.decode(r.body) as Map<String, dynamic>;
    final session = FocusSession.fromJson(obj['session'] as Map<String, dynamic>);
    final balanceRaw = obj['balance'];
    return (
      session,
      balanceRaw == null ? null : Balance.fromJson(balanceRaw as Map<String, dynamic>),
    );
  }

  Future<({FocusSession session, Balance? balance, List<Map<String, dynamic>> results})>
      batchActions({
    required String sessionId,
    required List<Map<String, dynamic>> actions,
    String? idempotencyKey,
    List<Map<String, dynamic>>? segments,
  }) async {
    final extraHeaders = <String, String>{};
    if (idempotencyKey != null) {
      extraHeaders['Idempotency-Key'] = idempotencyKey;
    }
    final body = <String, dynamic>{'actions': actions};
    if (segments != null && segments.isNotEmpty) {
      body['segments'] = segments;
    }
    final r = await _client.send(
      'POST',
      _client.uri('/api/v1/focus-sessions/$sessionId/actions'),
      body: body,
      headers: extraHeaders,
      timeout: const Duration(seconds: 30),
    );
    if (r.statusCode != 200) {
      throw ApiHttpException(
        method: 'POST',
        path: '/api/v1/focus-sessions/$sessionId/actions',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
    final obj = json.decode(r.body) as Map<String, dynamic>;
    final session = FocusSession.fromJson(obj['session'] as Map<String, dynamic>);
    final balanceRaw = obj['balance'];
    final results = (obj['results'] as List<dynamic>)
        .map((e) => e as Map<String, dynamic>)
        .toList();
    return (
      session: session,
      balance: balanceRaw == null ? null : Balance.fromJson(balanceRaw as Map<String, dynamic>),
      results: results,
    );
  }

  Future<FocusSession> updateSessionTask({
    required String sessionId,
    String? taskId,
  }) async {
    final r = await _client.send(
      'PATCH',
      _client.uri('/api/v1/focus-sessions/$sessionId'),
      body: {'task_id': taskId},
    );
    if (r.statusCode != 200) {
      throw ApiHttpException(
        method: 'PATCH',
        path: '/api/v1/focus-sessions/$sessionId',
        statusCode: r.statusCode,
        headers: r.headers,
        body: r.body,
      );
    }
    return FocusSession.fromJson(json.decode(r.body) as Map<String, dynamic>);
  }
}
