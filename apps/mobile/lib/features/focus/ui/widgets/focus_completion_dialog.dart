import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/design/app_colors.dart';
import '../../../../core/design/app_typography.dart';
import '../../models/focus_models.dart';

class FocusCompletionDialog extends StatelessWidget {
  final FocusSession session;
  final bool gotServerResponse;

  const FocusCompletionDialog({
    super.key,
    required this.session,
    required this.gotServerResponse,
  });

  @override
  Widget build(BuildContext context) {
    final minutes = session.creditedMinutes ?? ((session.activeElapsedSec / 60).floor());
    final xp = session.earnedXp;
    final coins = session.earnedCoins;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 24),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(28),
        ),
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎉', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(
              'Session Complete!',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: AppColors.textDark,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              gotServerResponse
                  ? 'Great work! You focused for $minutes minutes.'
                  : 'Session saved. Rewards will sync shortly.',
              style: AppTypography.body15(color: AppColors.textMedium),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (gotServerResponse)
              IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(child: _buildRewardCard('+$xp XP', 'Experience')),
                    const SizedBox(width: 8),
                    Expanded(child: _buildRewardCard('+${coins.toStringAsFixed(0)}', 'Coins')),
                    const SizedBox(width: 8),
                    Expanded(child: _buildRewardCard('${minutes}m', 'Minutes')),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppColors.gradientStart, AppColors.gradientEnd],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Start Break',
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Text('Done', style: AppTypography.body15(color: AppColors.textMedium)),
                ),
                Text(
                  ' · ',
                  style: AppTypography.body15(color: AppColors.textLight),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Text(
                    'Another session',
                    style: AppTypography.body15(color: AppColors.textMedium),
                  ),
                ),
              ],
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildRewardCard(String value, String label) {
    return Container(
      constraints: const BoxConstraints(minHeight: 80),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryBlue,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTypography.caption12(color: AppColors.textMedium),
          ),
        ],
      ),
    );
  }
}
