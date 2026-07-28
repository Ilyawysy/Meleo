import 'dart:ui';

enum MascotSkinTier { cheap, medium, expensive, pro }

MascotSkinTier _tierFromString(String s) {
  switch (s) {
    case 'cheap':
      return MascotSkinTier.cheap;
    case 'medium':
      return MascotSkinTier.medium;
    case 'expensive':
      return MascotSkinTier.expensive;
    case 'pro':
      return MascotSkinTier.pro;
    default:
      return MascotSkinTier.cheap;
  }
}

Color _hexToColor(String hex) {
  final clean = hex.replaceAll('#', '');
  return Color(int.parse('FF$clean', radix: 16));
}

class MascotSkin {
  final int id;
  final String slug;
  final MascotSkinTier tier;
  final int priceCoins;
  final String color1Hex;
  final String color2Hex;
  final String color3Hex;
  final String color4Hex;
  final int sortOrder;
  final bool owned;
  final bool active;

  const MascotSkin({
    required this.id,
    required this.slug,
    required this.tier,
    required this.priceCoins,
    required this.color1Hex,
    required this.color2Hex,
    required this.color3Hex,
    required this.color4Hex,
    required this.sortOrder,
    required this.owned,
    required this.active,
  });

  Color get color1 => _hexToColor(color1Hex);
  Color get color2 => _hexToColor(color2Hex);
  Color get color3 => _hexToColor(color3Hex);
  Color get color4 => _hexToColor(color4Hex);

  factory MascotSkin.fromJson(Map<String, dynamic> j) {
    return MascotSkin(
      id: j['id'] as int,
      slug: j['slug'] as String,
      tier: _tierFromString(j['tier'] as String),
      priceCoins: j['price_coins'] as int,
      color1Hex: j['color1'] as String,
      color2Hex: j['color2'] as String,
      color3Hex: j['color3'] as String,
      color4Hex: j['color4'] as String,
      sortOrder: j['sort_order'] as int? ?? 0,
      owned: j['owned'] as bool? ?? false,
      active: j['active'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'slug': slug,
        'tier': tier.name,
        'price_coins': priceCoins,
        'color1': color1Hex,
        'color2': color2Hex,
        'color3': color3Hex,
        'color4': color4Hex,
        'sort_order': sortOrder,
        'owned': owned,
        'active': active,
      };

  MascotSkin copyWith({bool? owned, bool? active}) => MascotSkin(
        id: id,
        slug: slug,
        tier: tier,
        priceCoins: priceCoins,
        color1Hex: color1Hex,
        color2Hex: color2Hex,
        color3Hex: color3Hex,
        color4Hex: color4Hex,
        sortOrder: sortOrder,
        owned: owned ?? this.owned,
        active: active ?? this.active,
      );
}

class MascotSkinsCatalog {
  final List<MascotSkin> skins;
  final int? activeSkinId;

  const MascotSkinsCatalog({required this.skins, required this.activeSkinId});

  MascotSkin? get activeSkin {
    if (activeSkinId == null) return null;
    for (final s in skins) {
      if (s.id == activeSkinId) return s;
    }
    return null;
  }

  factory MascotSkinsCatalog.fromJson(Map<String, dynamic> j) {
    final list = (j['skins'] as List<dynamic>)
        .map((e) => MascotSkin.fromJson(e as Map<String, dynamic>))
        .toList();
    return MascotSkinsCatalog(
      skins: list,
      activeSkinId: j['active_skin_id'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'skins': skins.map((s) => s.toJson()).toList(),
        'active_skin_id': activeSkinId,
      };
}
