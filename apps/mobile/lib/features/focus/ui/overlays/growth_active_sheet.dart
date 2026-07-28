import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/design/app_colors.dart';
import '../../logic/growth_calculator.dart';
import '../../models/adaptive_plan.dart';
import '../../providers/adaptive_plan_provider.dart';
import 'growth_setup_sheet.dart';

Future<void> showGrowthActiveSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    barrierColor: AppColors.overlay,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const GrowthActiveSheet(),
  );
}

class GrowthActiveSheet extends ConsumerWidget {
  const GrowthActiveSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(adaptivePlanProvider);
    final plan = planAsync.valueOrNull;

    if (plan == null ||
        plan.growthTargetHours == null ||
        plan.growthStartedAt == null ||
        plan.growthSpeed == null) {
      return const SizedBox(height: 200);
    }

    final base = basePlanTotalHours(plan.hoursPerDay);
    final target = plan.growthTargetHours!;
    final startedAt = plan.growthStartedAt!;
    final speed = plan.growthSpeed!;
    final now = DateTime.now();

    final current = currentWeeklyTargetHours(
      basePlanTotal: base,
      targetTotal: target,
      startedAt: startedAt,
      speed: speed,
      now: now,
    );
    final elapsed = weeksSinceStart(startedAt, now);
    final totalWeeks = weeksToTarget(speed);
    final completion = estimatedCompletionDate(startedAt: startedAt, speed: speed);
    final progressFraction =
        target > base ? ((current - base) / (target - base)).clamp(0.0, 1.0) : 0.0;

    final speedLabel = switch (speed) {
      GrowthSpeed.steady => 'Steady',
      GrowthSpeed.faster => 'Faster',
      GrowthSpeed.push => 'Push',
    };

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Header
          Row(
            children: [
              const Icon(Icons.trending_up,
                  color: Color(0xFF16A34A), size: 22),
              const SizedBox(width: 8),
              Text(
                'Growth — Active',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textDark,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.of(context).pop(),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Summary card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Now: ${current}h/week',
                      style: GoogleFonts.inter(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                    Text(
                      'Goal: ${target}h',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSlate,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progressFraction,
                    minHeight: 8,
                    backgroundColor: const Color(0xFFD1FAE5),
                    valueColor:
                        const AlwaysStoppedAnimation(Color(0xFF16A34A)),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Week ${elapsed + 1} of $totalWeeks · $speedLabel',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSlate,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Est. completion: ${_formatDate(completion)}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSlate,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Edit target
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                barrierColor: AppColors.overlay,
                shape: const RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(24)),
                ),
                builder: (_) => const GrowthSetupSheet(),
              );
            },
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: Text(
              'Edit target',
              style: GoogleFonts.inter(
                  fontSize: 15, fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              side: const BorderSide(color: AppColors.border),
              foregroundColor: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 12),

          // Stop growth
          TextButton(
            onPressed: () => _confirmStop(context, ref),
            style: TextButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              foregroundColor: AppColors.error,
            ),
            child: Text(
              'Stop Growth',
              style: GoogleFonts.inter(
                  fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  Future<void> _confirmStop(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: AppColors.overlay,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Stop Growth?'),
        content: const Text(
            'This will clear your growth target and speed. You can restart it anytime.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(adaptivePlanProvider.notifier).stopGrowth();
      if (context.mounted) Navigator.of(context).pop();
    }
  }
}
