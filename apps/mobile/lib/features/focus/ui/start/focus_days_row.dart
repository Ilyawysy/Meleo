import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/design/app_colors.dart';
import '../../providers/adaptive_plan_provider.dart';

const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

class FocusDaysRow extends ConsumerWidget {
  const FocusDaysRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(adaptivePlanProvider);
    final hours = planAsync.valueOrNull?.hoursPerDay ?? List.filled(7, 0);

    final todayIdx = DateTime.now().weekday - 1; // 0=Mon

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(7, (i) {
          return _DayChip(
            label: _dayLabels[i],
            hours: hours.length > i ? hours[i] : 0,
            isToday: i == todayIdx,
          );
        }),
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  final String label;
  final int hours;
  final bool isToday;

  const _DayChip({
    required this.label,
    required this.hours,
    required this.isToday,
  });

  @override
  Widget build(BuildContext context) {
    final hasFocus = hours > 0;
    final circleColor = isToday
        ? AppColors.primaryBlue
        : hasFocus
            ? AppColors.primaryBlue.withValues(alpha: 0.12)
            : const Color(0xFFF4F4F5);
    final letterColor = isToday
        ? Colors.white
        : hasFocus
            ? AppColors.primaryBlue
            : AppColors.textLight;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: circleColor,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: letterColor,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          hours > 0 ? '${hours}h' : '',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: hasFocus ? AppColors.textSlate : AppColors.textLight,
          ),
        ),
      ],
    );
  }
}
