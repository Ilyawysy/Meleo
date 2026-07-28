import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_typography.dart';
import '../../subscription/ui/pro_badge.dart';
import '../logic/formatters.dart';

class ProfileHeroCard extends StatelessWidget {
  final String? displayName;
  final String? email;
  final DateTime? createdAt;
  final bool isPro;

  const ProfileHeroCard({
    super.key,
    this.displayName,
    this.email,
    this.createdAt,
    this.isPro = false,
  });

  String _initials() {
    final name = displayName?.trim() ?? '';
    if (name.isEmpty) return 'US';
    final parts = name.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  String _sincePeriod() {
    if (createdAt == null) return '';
    return 'Since ${shortMonths[createdAt!.month - 1]} ${createdAt!.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.greyBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: AppColors.gradientLogo,
              ),
              borderRadius: BorderRadius.circular(32),
            ),
            alignment: Alignment.center,
            child: Text(
              _initials(),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        displayName ?? 'User',
                        style: AppTypography.heading16(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isPro) ...[
                      const SizedBox(width: 8),
                      const ProBadge(),
                    ],
                  ],
                ),
                if (email != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    email!,
                    style: AppTypography.caption12(color: AppColors.textLight),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (createdAt != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        size: 12,
                        color: AppColors.textLight,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _sincePeriod(),
                        style: AppTypography.caption12(
                            color: AppColors.textLight),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
