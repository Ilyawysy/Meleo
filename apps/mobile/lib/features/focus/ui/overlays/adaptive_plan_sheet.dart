import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/design/app_colors.dart';
import 'growth_setup_sheet.dart';
import 'plan_setup_sheet.dart';
import 'sprint_setup_sheet.dart';

Future<void> showAdaptivePlanDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    barrierColor: AppColors.overlay,
    builder: (ctx) => const _AdaptivePlanDialog(),
  );
}

class _AdaptivePlanDialog extends StatelessWidget {
  const _AdaptivePlanDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Text(
                  'Adaptive Plan',
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
            const SizedBox(height: 4),
            Text(
              'Choose how you want to structure your focus time',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: AppColors.textSlate,
              ),
            ),
            const SizedBox(height: 20),

            // Plan card
            _PlanOption(
              icon: Icons.calendar_month_outlined,
              iconColor: AppColors.primaryBlue,
              iconBg: AppColors.primaryBlue.withValues(alpha: 0.1),
              title: 'Custom Plan',
              subtitle: 'Set specific hours for each day of the week',
              onTap: () {
                Navigator.of(context).pop();
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  barrierColor: AppColors.overlay,
                  shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  builder: (_) => const PlanSetupSheet(),
                );
              },
            ),
            const SizedBox(height: 12),

            // Growth card
            _PlanOption(
              icon: Icons.trending_up,
              iconColor: const Color(0xFF16A34A),
              iconBg: const Color(0xFF16A34A).withValues(alpha: 0.1),
              title: 'Growth',
              subtitle:
                  'Gradually increase your weekly focus hours over time',
              onTap: () {
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
            ),
            const SizedBox(height: 12),

            // Sprint card
            _PlanOption(
              icon: Icons.bolt,
              iconColor: const Color(0xFFD97706),
              iconBg: const Color(0xFFD97706).withValues(alpha: 0.1),
              title: 'Sprint',
              subtitle:
                  'Intense focus toward a specific goal with a deadline',
              onTap: () {
                Navigator.of(context).pop();
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  barrierColor: AppColors.overlay,
                  shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  builder: (_) => const SprintSetupSheet(),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _PlanOption extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _PlanOption({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.greyBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSlate,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: AppColors.textLight, size: 20),
          ],
        ),
      ),
    );
  }
}
