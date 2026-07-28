import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_typography.dart';
import '../logic/formatters.dart';
import '../models/profile_stats.dart';

class BestMonthCard extends StatelessWidget {
  final BestMonth? bestMonth;

  const BestMonthCard({super.key, this.bestMonth});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.greyBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: bestMonth == null ? _empty() : _filled(bestMonth!),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.emoji_events_outlined,
            size: 20,
            color: Color(0xFFEA580C),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'Best Month',
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

  Widget _filled(BestMonth month) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(),
        const SizedBox(height: 14),
        Text(
          formatHoursMinutes(month.totalSeconds),
          style: GoogleFonts.plusJakartaSans(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          formatMonthYear(month.month),
          style: AppTypography.caption12(color: AppColors.textLight),
        ),
        const SizedBox(height: 14),
        _Heatmap(heatmap: month.heatmap),
      ],
    );
  }
}

class _Heatmap extends StatelessWidget {
  final List<List<int>> heatmap;

  const _Heatmap({required this.heatmap});

  @override
  Widget build(BuildContext context) {
    // Use at most 5 rows, 7 columns
    final rows = heatmap.take(5).toList();

    int maxVal = 1;
    for (final row in rows) {
      for (final val in row) {
        if (val > maxVal) maxVal = val;
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(rows.length, (rowIdx) {
        final cols = rows[rowIdx];
        return Padding(
          padding: EdgeInsets.only(bottom: rowIdx < rows.length - 1 ? 4 : 0),
          child: Row(
            children: List.generate(7, (colIdx) {
              final val = colIdx < cols.length ? cols[colIdx] : 0;
              final opacity = val == 0
                  ? 0.08
                  : 0.2 + 0.8 * (val / maxVal);

              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: colIdx < 6 ? 4 : 0),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFEA580C)
                            .withValues(alpha: opacity),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      }),
    );
  }
}
