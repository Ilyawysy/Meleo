import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_typography.dart';

class _Feature {
  final String name;
  final String freeValue;
  final String proValue;
  final bool freeCheck;
  final bool proCheck;

  const _Feature({
    required this.name,
    this.freeValue = '',
    this.proValue = '',
    this.freeCheck = false,
    this.proCheck = true,
  });
}

const _features = [
  _Feature(name: 'AI-assistant messages', freeValue: '5 / day', proValue: 'Unlimited'),
  _Feature(name: 'Statistics widgets', freeValue: '5 basic', proValue: '18+ pro'),
  _Feature(name: 'Focus session history', freeValue: '7 days', proValue: 'Unlimited'),
  _Feature(name: 'Custom focus goals', freeCheck: false, proCheck: true),
  _Feature(name: 'Advanced analytics', freeCheck: false, proCheck: true),
  _Feature(name: 'Streak insights', freeCheck: false, proCheck: true),
  _Feature(name: 'Export reports', freeCheck: false, proCheck: true),
  _Feature(name: 'Priority support', freeCheck: false, proCheck: true),
];

class ProUpgradeSheet extends StatelessWidget {
  const ProUpgradeSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Crown icon + title
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF7C3AED), Color(0xFFF59E0B)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.workspace_premium,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Upgrade to Pro',
            style: AppTypography.heading22(),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Unlock the full power of Meleo with advanced analytics, unlimited AI, and premium features.',
              textAlign: TextAlign.center,
              style: AppTypography.body14(color: AppColors.textMedium),
            ),
          ),
          const SizedBox(height: 24),

          // Comparison table
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  // Table header
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.greyBg,
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(14)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 5,
                          child: Text('Feature',
                              style: AppTypography.caption11(
                                  color: AppColors.textMedium)),
                        ),
                        SizedBox(
                          width: 60,
                          child: Center(
                            child: Text('Free',
                                style: AppTypography.caption11(
                                    color: AppColors.textMedium)),
                          ),
                        ),
                        SizedBox(
                          width: 60,
                          child: Center(
                            child: Text(
                              'Pro',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF7C3AED),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Rows
                  ...List.generate(_features.length, (i) {
                    final f = _features[i];
                    final isLast = i == _features.length - 1;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        border: isLast
                            ? null
                            : const Border(
                                bottom: BorderSide(
                                    color: AppColors.divider, width: 0.5)),
                        borderRadius: isLast
                            ? const BorderRadius.vertical(
                                bottom: Radius.circular(14))
                            : null,
                        color: Colors.white,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 5,
                            child: Text(f.name,
                                style: AppTypography.body13(
                                    color: AppColors.textDark)),
                          ),
                          SizedBox(
                            width: 60,
                            child: Center(child: _buildCell(f, false)),
                          ),
                          SizedBox(
                            width: 60,
                            child: Center(child: _buildCell(f, true)),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // CTA button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _UpgradeButton(
              onTap: () {
                Navigator.of(context).pop();
                // TODO: integrate with payment
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '14-day free trial. Cancel anytime.',
            style: AppTypography.caption12(color: AppColors.textLight),
          ),
          SizedBox(height: 16 + bottomPad),
        ],
      ),
    );
  }

  Widget _buildCell(_Feature f, bool isPro) {
    final value = isPro ? f.proValue : f.freeValue;
    if (value.isNotEmpty) {
      return Text(
        value,
        textAlign: TextAlign.center,
        style: AppTypography.caption11(
          color: isPro ? const Color(0xFF7C3AED) : AppColors.textMedium,
        ).copyWith(fontWeight: isPro ? FontWeight.w600 : FontWeight.w400),
      );
    }
    final check = isPro ? f.proCheck : f.freeCheck;
    if (check) {
      return const Icon(Icons.check_circle, size: 18, color: Color(0xFF22C55E));
    }
    return Icon(Icons.remove_circle_outline,
        size: 18, color: AppColors.textLight.withValues(alpha: 0.5));
  }
}

class _UpgradeButton extends StatefulWidget {
  final VoidCallback onTap;
  const _UpgradeButton({required this.onTap});

  @override
  State<_UpgradeButton> createState() => _UpgradeButtonState();
}

class _UpgradeButtonState extends State<_UpgradeButton>
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, child) {
          return Container(
            width: double.infinity,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: const [
                  Color(0xFF7C3AED),
                  Color(0xFFA855F7),
                  Color(0xFF7C3AED),
                ],
                begin: Alignment(-1.0 + 2.0 * _ctrl.value, 0),
                end: Alignment(1.0 + 2.0 * _ctrl.value, 0),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: child,
          );
        },
        child: Center(
          child: Text(
            'Start Free Trial',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
