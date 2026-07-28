import 'dart:convert';

import '../../../core/api_client.dart';
import '../models/mascot_skin.dart';

class MascotSkinsApi {
  final _client = ApiClient();

  Future<MascotSkinsCatalog> getCatalog() async {
    final r =
        await _client.send('GET', _client.uri('/api/v1/mascot-skins'));
    if (r.statusCode != 200) {
      throw Exception('GET /mascot-skins failed: ${r.statusCode} ${r.body}');
    }
    return MascotSkinsCatalog.fromJson(
      json.decode(r.body) as Map<String, dynamic>,
    );
  }

  Future<MascotSkin> buy(int skinId) async {
    final r = await _client.send(
      'POST',
      _client.uri('/api/v1/mascot-skins/$skinId/buy'),
    );
    if (r.statusCode != 200) {
      throw Exception(
          'POST /mascot-skins/$skinId/buy failed: ${r.statusCode} ${r.body}');
    }
    return MascotSkin.fromJson(json.decode(r.body) as Map<String, dynamic>);
  }

  Future<MascotSkinsCatalog> setActive(int? skinId) async {
    final r = await _client.send(
      'POST',
      _client.uri('/api/v1/mascot-skins/active'),
      body: {'skin_id': skinId},
    );
    if (r.statusCode != 200) {
      throw Exception(
          'POST /mascot-skins/active failed: ${r.statusCode} ${r.body}');
    }
    return MascotSkinsCatalog.fromJson(
      json.decode(r.body) as Map<String, dynamic>,
    );
  }
}
