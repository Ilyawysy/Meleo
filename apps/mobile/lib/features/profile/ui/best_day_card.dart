import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_typography.dart';
import '../logic/formatters.dart';
import '../models/profile_stats.dart';

class BestDayCard extends StatelessWidget {
  final BestDay? bestDay;

  const BestDayCard({super.key, this.bestDay});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.greyBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: bestDay == null ? _empty() : _filled(bestDay!),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFFFEF3C7),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.emoji_events_outlined,
            size: 20,
            color: Color(0xFFD97706),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Best Day',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
          ),
        ),
      ],
    );
  }

  Widget _empty() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(),
        const SizedBox(height: 14),
        Text(
          'Start a focus session to unlock records',
          style: AppTypography.body14(color: AppColors.textLight),
        ),
      ],
    );
  }

  Widget _filled(BestDay day) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(),
        const SizedBox(height: 14),
        Text(
          formatHoursMinutes(day.seconds),
          style: GoogleFonts.plusJakartaSans(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              formatShortDate(day.date),
              style: AppTypography.caption12(color: AppColors.textLight),
            ),
            const SizedBox(width: 8),
            Container(
              width: 3,
              height: 3,
              decoration: BoxDecoration(
                color: AppColors.textLight,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${day.sessionCount} ${day.sessionCount == 1 ? 'session' : 'sessions'}',
              style: AppTypography.caption12(color: AppColors.textLight),
            ),
          ],
        ),
      ],
    );
  }
}
