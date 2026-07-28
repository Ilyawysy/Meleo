import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'pro_upgrade_sheet.dart';

/// Shimmer-animated PRO badge button. Tap opens the upgrade bottom sheet.
class ProBadge extends StatefulWidget {
  const ProBadge({super.key});

  @override
  State<ProBadge> createState() => _ProBadgeState();
}

class _ProBadgeState extends State<ProBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _openUpgrade() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ProUpgradeSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _openUpgrade,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: const [
                  Color(0xFF7C3AED),
                  Color(0xFFA855F7),
                  Color(0xFFF59E0B),
                  Color(0xFFA855F7),
                  Color(0xFF7C3AED),
                ],
                stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
                begin: Alignment(-1.0 + 2.0 * _ctrl.value, 0),
                end: Alignment(1.0 + 2.0 * _ctrl.value, 0),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: child,
          );
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.workspace_premium, size: 14, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              'PRO',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
