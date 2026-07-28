import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_typography.dart';

// ---------------------------------------------------------------------------
// Gradient Button (blue gradient, radius 16, white text)
// ---------------------------------------------------------------------------
class GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final double height;
  final IconData? icon;

  const GradientButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.height = 56,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.gradientStart, AppColors.gradientEnd],
          ),
        ),
        child: ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: isLoading
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 18, color: Colors.white),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      label,
                      style: AppTypography.body17(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}


// ---------------------------------------------------------------------------
// Rounded Checkbox (rounded square, configurable size)
// ---------------------------------------------------------------------------
class RoundedCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final double size;
  final double borderRadius;

  const RoundedCheckbox({
    super.key,
    required this.value,
    this.onChanged,
    this.size = 24,
    this.borderRadius = 6,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onChanged != null ? () => onChanged!(!value) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: value ? AppColors.primaryBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(borderRadius),
          border: value
              ? null
              : Border.all(color: AppColors.border, width: 1.5),
        ),
        child: value
            ? Icon(Icons.check, size: size * 0.6, color: Colors.white)
            : null,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Circular Icon Button (36x36, border or fill, icon inside)
// ---------------------------------------------------------------------------
class CircularIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final Color? fill;
  final Color iconColor;
  final Color borderColor;

  const CircularIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 36,
    this.fill,
    this.iconColor = AppColors.textMedium,
    this.borderColor = AppColors.border,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: fill,
          shape: BoxShape.circle,
          border: fill == null
              ? Border.all(color: borderColor, width: 1.5)
              : null,
        ),
        child: Center(
          child: Icon(icon, size: 16, color: iconColor),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section Header (collapsible: title + chevron + count)
// ---------------------------------------------------------------------------
class SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  final bool expanded;
  final VoidCallback onToggle;
  final Color titleColor;

  const SectionHeader({
    super.key,
    required this.title,
    required this.count,
    required this.expanded,
    required this.onToggle,
    this.titleColor = AppColors.textDark,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggle,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Row(
            children: [
              Text(title, style: AppTypography.sectionTitle(color: titleColor)),
              const SizedBox(width: 6),
              Icon(
                expanded
                    ? Icons.keyboard_arrow_down
                    : Icons.keyboard_arrow_right,
                size: 18,
                color: AppColors.textSlateLight,
              ),
            ],
          ),
          const Spacer(),
          Text(
            '$count ${count == 1 ? 'task' : 'tasks'}',
            style: AppTypography.body13(color: AppColors.textMedium),
          ),
        ],
      ),
    );
  }
}
