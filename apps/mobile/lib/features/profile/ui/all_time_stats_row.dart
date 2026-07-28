import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/design/app_typography.dart';
import '../logic/formatters.dart';

class AllTimeStatsRow extends StatelessWidget {
  final int allFocusSeconds;
  final int daysInApp;
  final int longestStreak;

  const AllTimeStatsRow({
    super.key,
    required this.allFocusSeconds,
    required this.daysInApp,
    required this.longestStreak,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            icon: Icons.timer_outlined,
            value: formatHoursMinutes(allFocusSeconds),
            label: 'All focus',
            color: const Color(0xFF2563EB),
            bgColor: const Color(0xFFEFF6FF),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            icon: Icons.calendar_month_outlined,
            value: daysInApp.toString(),
            label: 'Days in app',
            color: const Color(0xFF7C3AED),
            bgColor: const Color(0xFFF5F3FF),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            icon: Icons.local_fire_department_outlined,
            value: longestStreak.toString(),
            label: 'Longest streak',
            color: const Color(0xFFEA580C),
            bgColor: const Color(0xFFFFF7ED),
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final Color bgColor;

  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTypography.caption11(color: color.withValues(alpha: 0.7)),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
