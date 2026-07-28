import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/design/app_colors.dart';
import '../../data/gamification_calculator.dart' as calc;
import '../../models/focus_room.dart' as room_model;
import '../../models/gamification_models.dart';
import 'mascot.dart';

/// Focus tab body — matches pencil-new.pen node HQB0f.
///
/// Layout top→bottom:
///   Top area (padding 20px horizontal, gap 10):
///     row1: PRO pill + Daily Progress pill ("Xm / Yh today") + settings gear
///     row2: streak card (flame + streak + multiplier) + shop card
///   Center: mascot (idle animation), fills remaining space
///   Controls: timer button + Start Focus button + apps-block button
class FocusRoom extends StatelessWidget {
  final double coins;
  final GamificationProfile? profile;
  final int creditedMinutesToday;
  final VoidCallback onOpenShop;
  final VoidCallback onStart;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenHelp;
  final VoidCallback? onOpenTimer;
  final VoidCallback? onOpenAppBlock;
  final bool isPro;
  final String? activeSessionLabel;
  final String? activeSessionSubLabel;
  final String? activeSessionTaskTitle;
  final VoidCallback? onReturnToSession;
  /// When set, shows selected-room widget (room name + start button) instead of
  /// the generic Start Focus button. Help button remains visible.
  final room_model.FocusRoom? activeRoom;
  /// Called when the user taps "Start Focus" in the selected-room widget.
  final VoidCallback? onStartForRoom;

  const FocusRoom({
    super.key,
    required this.coins,
    required this.profile,
    required this.creditedMinutesToday,
    required this.onOpenShop,
    required this.onStart,
    required this.onOpenSettings,
    required this.onOpenHelp,
    this.onOpenTimer,
    this.onOpenAppBlock,
    this.isPro = false,
    this.activeSessionLabel,
    this.activeSessionSubLabel,
    this.activeSessionTaskTitle,
    this.onReturnToSession,
    this.activeRoom,
    this.onStartForRoom,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Column(
            children: [
              _buildTopRow1(),
              const SizedBox(height: 10),
              _buildTopRow2(),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: Mascot(
              mode: mascotForToday(
                creditedMinutesToday: creditedMinutesToday,
                planMinutes: profile?.planMinutes[DateTime.now().weekday] ?? 0,
              ),
              size: 280,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: onReturnToSession != null
              ? _buildActiveSessionWidget()
              : activeRoom != null
                  ? _buildSelectedRoomControls()
                  : _buildControls(),
        ),
      ],
    );
  }

  // ───────────────────────── Top area ─────────────────────────

  Widget _buildTopRow1() {
    return Row(
      children: [
        if (isPro) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2563EB), Color(0xFF7C3AED), Color(0xFFEC4899)],
              ),
            ),
            child: Text(
              'PRO',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(child: _buildDailyProgressPill()),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: onOpenSettings,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFF4F4F5),
              borderRadius: BorderRadius.circular(18),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.settings_outlined,
              size: 20,
              color: Color(0xFF71717A),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDailyProgressPill() {
    final planMinutes =
        profile?.planMinutes[DateTime.now().weekday] ?? 0;
    final progress = planMinutes > 0
        ? (creditedMinutesToday / planMinutes).clamp(0.0, 1.0)
        : 0.0;
    final planHours = planMinutes / 60;
    final label = planMinutes > 0
        ? '${creditedMinutesToday}m / ${planHours.toStringAsFixed(planHours == planHours.roundToDouble() ? 0 : 1)}h'
        : '${creditedMinutesToday}m today';

    return LayoutBuilder(
      builder: (context, constraints) {
        final fillW = (constraints.maxWidth * progress).clamp(0.0, constraints.maxWidth);
        return Stack(
          children: [
            Container(
              height: 36,
              width: constraints.maxWidth,
              decoration: BoxDecoration(
                color: const Color(0xFFF4F4F5),
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            if (progress > 0)
              Container(
                height: 36,
                width: fillW,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  gradient: const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Color(0xFF2563EB), Color(0xFF60A5FA)],
                  ),
                ),
              ),
            SizedBox(
              height: 36,
              width: constraints.maxWidth,
              child: Center(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: progress > 0.5 ? Colors.white : const Color(0xFF52525B),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTopRow2() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildStreakCard(),
        _buildShopCard(),
      ],
    );
  }

  Widget _buildStreakCard() {
    final streak = profile?.streakCurrent ?? 0;
    final mult = profile != null
        ? calc.computeModeMultiplier(
            profile!.recoveryMode != null, profile!.streakCurrent)
        : 1.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFDE68A), width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.local_fire_department,
                  size: 28, color: Color(0xFFF59E0B)),
              const SizedBox(width: 6),
              Text(
                '$streak',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFD97706),
                  height: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'x${mult.toStringAsFixed(2)}',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: const Color(0xFFB45309),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShopCard() {
    return GestureDetector(
      onTap: onOpenShop,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F4F5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.monetization_on,
                size: 20, color: Color(0xFFF59E0B)),
            const SizedBox(width: 8),
            Text(
              coins.toStringAsFixed(0),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF18181B),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.shopping_bag_outlined,
                size: 20, color: Color(0xFF71717A)),
          ],
        ),
      ),
    );
  }

  // ───────────────────────── Controls ─────────────────────────

  Widget _buildControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _SideIconButton(
          icon: Icons.timer_outlined,
          onTap: onOpenTimer,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: onStart,
            child: Container(
              height: 56,
              constraints: const BoxConstraints(maxWidth: 260),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryBlue.withValues(alpha: 0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.play_arrow_rounded,
                      color: Colors.white, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Start Focus',
                    style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _HelpButton(onTap: onOpenHelp),
            const SizedBox(height: 8),
            _SideIconButton(
              icon: Icons.block,
              onTap: onOpenAppBlock,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSelectedRoomControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _SideIconButton(
          icon: Icons.timer_outlined,
          onTap: onOpenTimer,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: onStartForRoom,
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.primaryBlue,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryBlue.withValues(alpha: 0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.play_arrow_rounded,
                      color: Colors.white, size: 22),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      activeRoom?.title ?? 'Start Focus',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _HelpButton(onTap: onOpenHelp),
            const SizedBox(height: 8),
            _SideIconButton(
              icon: Icons.block,
              onTap: onOpenAppBlock,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActiveSessionWidget() {
    return GestureDetector(
      onTap: onReturnToSession,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2563EB).withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activeSessionLabel ?? '',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppColors.white,
                  ),
                ),
                Text(
                  activeSessionSubLabel ?? '',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: const Color(0xFFBFD7FF),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Active Session',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF86EFAC),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    activeSessionTaskTitle ?? 'Free focus',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tap to return →',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: const Color(0xFFBFD7FF),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _SideIconButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: const Color(0xFFF4F4F5),
          borderRadius: BorderRadius.circular(18),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 24, color: const Color(0xFF71717A)),
      ),
    );
  }
}

class _HelpButton extends StatelessWidget {
  final VoidCallback onTap;
  const _HelpButton({required this.onTap});

  static const _fill = Color(0xFFDBEAFE); // pale blue
  static const _stroke = Color(0xFF2563EB); // primary blue
  static const _radius = 18.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        painter: _DashedRRectPainter(
          color: _stroke,
          radius: _radius,
          strokeWidth: 1.5,
          dashLength: 5,
          gapLength: 4,
        ),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: _fill,
            borderRadius: BorderRadius.circular(_radius),
          ),
          alignment: Alignment.center,
          child: const Text(
            'help',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _stroke,
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;

  const _DashedRRectPainter({
    required this.color,
    required this.radius,
    required this.strokeWidth,
    required this.dashLength,
    required this.gapLength,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final path = Path()..addRRect(rrect);

    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = distance + dashLength;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.strokeWidth != strokeWidth ||
      old.dashLength != dashLength ||
      old.gapLength != gapLength;
}
