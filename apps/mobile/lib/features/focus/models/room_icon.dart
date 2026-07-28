enum RoomIcon { book, code, penTool, dumbbell, music, briefcase }

extension RoomIconSlug on RoomIcon {
  String get slug => name;

  static RoomIcon? fromSlug(String? value) {
    if (value == null) return null;
    for (final icon in RoomIcon.values) {
      if (icon.name == value) return icon;
    }
    // Backward-compat: legacy slugs from before the icon set was reshuffled.
    switch (value) {
      case 'tag':
        return RoomIcon.penTool;
      case 'puzzle':
        return RoomIcon.dumbbell;
    }
    return null;
  }
}
