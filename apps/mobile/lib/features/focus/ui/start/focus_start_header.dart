import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_typography.dart';
import '../../../profile/ui/settings_screen.dart';
import '../../providers/adaptive_plan_provider.dart';

const _isProMock = false; // TODO: wire real provider

class FocusStartHeader extends ConsumerWidget {
  const FocusStartHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(adaptivePlanProvider);
    final plan = planAsync.valueOrNull;

    final now = DateTime.now();
    final todayIdx = now.weekday - 1; // 0=Mon
    final plannedHours = plan?.hoursPerDay != null && plan!.hoursPerDay!.length == 7
        ? plan.hoursPerDay![todayIdx]
        : 0;
    final isFocusDay = plannedHours > 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatDate(now),
                  style: AppTypography.body14(color: AppColors.textSlate),
                ),
                const SizedBox(height: 4),
                _DayBadge(isFocusDay: isFocusDay),
              ],
            ),
          ),
          Row(
            children: [
              if (_isProMock) ...[_ProBadge(), const SizedBox(width: 8)],
              IconButton(
                icon: const Icon(Icons.settings_outlined,
                    color: AppColors.textSlate, size: 22),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SettingsScreen(),
                  ),
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayBadge extends StatelessWidget {
  final bool isFocusDay;
  const _DayBadge({required this.isFocusDay});

  @override
  Widget build(BuildContext context) {
    final bg = isFocusDay
        ? AppColors.primaryBlue.withValues(alpha: 0.12)
        : const Color(0xFFF4F4F5);
    final textColor =
        isFocusDay ? AppColors.primaryBlue : AppColors.textMedium;
    final label = isFocusDay ? 'Focus Day' : 'Free Day';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}

String _formatDate(DateTime dt) {
  const weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  ];
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${weekdays[dt.weekday - 1]}, ${months[dt.month - 1]} ${dt.day}';
}

class _ProBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7C3AED), Color(0xFF2563EB)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'PRO',
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
