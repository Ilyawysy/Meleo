import 'package:flutter/material.dart';
import '../../../core/design/app_colors.dart';
import '../../../core/design/app_typography.dart';

class CustomBottomNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const CustomBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onTap,
  });

  static const _tabs = [
    (icon: Icons.play_circle_outline_rounded, label: 'START'),
    (icon: Icons.timer_outlined, label: 'FOCUS'),
    (icon: Icons.bar_chart_rounded, label: 'STATS'),
    (icon: Icons.person_outline_rounded, label: 'PROFILE'),
  ];

  static const _duration = Duration(milliseconds: 250);
  static const _curve = Curves.easeInOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(21, 12, 21, 21),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00FFFFFF), Color(0xFFFFFFFF)],
          stops: [0, 0.3],
        ),
      ),
      child: Container(
        height: 62,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(36),
          border: Border.all(color: AppColors.border, width: 1.5),
        ),
        child: Row(
          children: List.generate(_tabs.length, (i) {
            final isSelected = selectedIndex == i;
            return Expanded(
              child: GestureDetector(
                onTap: () => onTap(i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: _duration,
                  curve: _curve,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primaryBlue
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedScale(
                        scale: isSelected ? 1.15 : 1.0,
                        duration: _duration,
                        curve: _curve,
                        child: TweenAnimationBuilder<Color?>(
                          tween: ColorTween(
                            end: isSelected
                                ? Colors.white
                                : AppColors.textLight,
                          ),
                          duration: _duration,
                          curve: _curve,
                          builder: (context, color, _) => Icon(
                            _tabs[i].icon,
                            size: 18,
                            color: color,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      TweenAnimationBuilder<Color?>(
                        tween: ColorTween(
                          end: isSelected
                              ? Colors.white
                              : AppColors.textLight,
                        ),
                        duration: _duration,
                        curve: _curve,
                        builder: (context, color, _) => Text(
                          _tabs[i].label,
                          style: AppTypography.label10(
                            color: color ?? AppColors.textLight,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
