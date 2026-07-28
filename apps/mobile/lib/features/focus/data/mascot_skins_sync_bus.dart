import 'dart:async';

import '../models/mascot_skin.dart';

/// In-process event bus for fresh mascot-skin data delivered through
/// aggregated sync. The sync service pushes a [MascotSkinsCatalog] every time
/// the focus snapshot arrives; the [MascotSkinsNotifier] listens and updates
/// its state.
///
/// Decouples the sync layer (no Riverpod ref) from the provider layer.
class MascotSkinsSyncBus {
  MascotSkinsSyncBus._();

  static final _controller = StreamController<MascotSkinsCatalog>.broadcast();

  static Stream<MascotSkinsCatalog> get stream => _controller.stream;

  static void push(MascotSkinsCatalog catalog) {
    if (_controller.isClosed) return;
    _controller.add(catalog);
  }
}
