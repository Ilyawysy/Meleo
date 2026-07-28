import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rive/rive.dart';

import '../../models/mascot_skin.dart';
import '../../providers/mascot_skins_provider.dart';

/// Which mascot animation to play.
enum MascotMode {
  /// Focus session — used in opened focus room (with or without active session).
  focus,

  /// Idle: nothing focused today yet.
  sofaTikTok,

  /// Idle: focused some today, daily plan not yet hit.
  dinner,

  /// Idle: daily plan hit (or exceeded).
  grassResting,
}

const Map<MascotMode, String> _assets = {
  MascotMode.focus: 'assets/rive/focus.riv',
  MascotMode.sofaTikTok: 'assets/rive/sofaTikTok.riv',
  MascotMode.dinner: 'assets/rive/dinner.riv',
  MascotMode.grassResting: 'assets/rive/grassResting.riv',
};

/// Picks the idle mascot for the main focus screen based on today's progress.
MascotMode mascotForToday({
  required int creditedMinutesToday,
  required int planMinutes,
}) {
  if (creditedMinutesToday <= 0) return MascotMode.sofaTikTok;
  if (planMinutes > 0 && creditedMinutesToday >= planMinutes) {
    return MascotMode.grassResting;
  }
  return MascotMode.dinner;
}

/// Animated mascot used on the focus tab and inside focus rooms.
///
/// Loads the requested Rive asset with its default state machine and binds
/// the active mascot skin's colors (color1..color4) to the ViewModel. If
/// [skinOverride] is provided, those colors are used instead of the active
/// skin (useful for shop previews).
class Mascot extends ConsumerStatefulWidget {
  final MascotMode mode;
  final double size;
  final Fit fit;
  final MascotSkin? skinOverride;

  const Mascot({
    super.key,
    required this.mode,
    this.size = 240,
    this.fit = Fit.contain,
    this.skinOverride,
  });

  @override
  ConsumerState<Mascot> createState() => _MascotState();
}

class _MascotState extends ConsumerState<Mascot> {
  File? _file;
  RiveWidgetController? _controller;
  ViewModelInstance? _vmi;
  ViewModelInstanceColor? _color1;
  ViewModelInstanceColor? _color2;
  ViewModelInstanceColor? _color3;
  ViewModelInstanceColor? _color4;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant Mascot old) {
    super.didUpdateWidget(old);
    if (old.mode != widget.mode) {
      _disposeCurrent();
      _load();
    } else if (old.skinOverride?.id != widget.skinOverride?.id) {
      _applyColors();
    }
  }

  void _disposeCurrent() {
    _controller?.dispose();
    _file?.dispose();
    _controller = null;
    _file = null;
    _vmi = null;
    _color1 = _color2 = _color3 = _color4 = null;
  }

  Future<void> _load() async {
    final asset = _assets[widget.mode]!;
    try {
      final file = await File.asset(asset, riveFactory: Factory.rive);
      if (file == null) return;
      if (!mounted) {
        file.dispose();
        return;
      }
      final controller = RiveWidgetController(file);
      final vmi = controller.dataBind(DataBind.auto());
      setState(() {
        _file = file;
        _controller = controller;
        _vmi = vmi;
        _color1 = vmi.color('color1');
        _color2 = vmi.color('color2');
        _color3 = vmi.color('color3');
        _color4 = vmi.color('color4');
      });
      _applyColors();
    } catch (_) {
      // Swallow — the static fallback will render.
    }
  }

  void _applyColors() {
    if (_vmi == null) return;
    final skin = widget.skinOverride ?? ref.read(activeMascotSkinProvider);
    if (skin == null) {
      // No active skin — the .riv plays with its default editor colors.
      // We don't reset colors here because we never overwrote them yet
      // (or we did from a previous skin and just leave them — switching to
      // null acts as "reapply previous skin's colors", which is acceptable).
      return;
    }
    _color1?.value = skin.color1;
    _color2?.value = skin.color2;
    _color3?.value = skin.color3;
    _color4?.value = skin.color4;
  }

  @override
  void dispose() {
    _disposeCurrent();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch active skin changes and reapply when it changes.
    if (widget.skinOverride == null) {
      ref.listen<MascotSkin?>(activeMascotSkinProvider, (prev, next) {
        if ((prev?.id ?? -1) != (next?.id ?? -1)) {
          _applyColors();
        }
      });
    }

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: _controller != null
          ? RiveWidget(controller: _controller!, fit: widget.fit)
          : const Icon(
              Icons.pets_rounded,
              size: 64,
              color: Color(0x66888888),
            ),
    );
  }
}
