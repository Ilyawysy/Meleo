import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/design/app_colors.dart';
import '../../providers/adaptive_plan_provider.dart';
import '../../providers/today_focus_progress_provider.dart';

class TodayProgressRing extends ConsumerWidget {
  const TodayProgressRing({super.key});

  static const double _ringSize = 220.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(adaptivePlanProvider);
    final progressAsync = ref.watch(todayFocusProgressProvider);

    final plan = planAsync.valueOrNull;
    final todayIdx = DateTime.now().weekday - 1;
    final plannedH = plan?.hoursPerDay != null && plan!.hoursPerDay!.length == 7
        ? plan.hoursPerDay![todayIdx]
        : 0;
    final creditedMin = progressAsync.valueOrNull ?? 0;

    final hasPlan = plannedH > 0;
    final plannedMin = plannedH * 60;
    final progress =
        hasPlan ? (creditedMin / plannedMin).clamp(0.0, 1.0) : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: SizedBox(
          width: _ringSize,
          height: _ringSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(_ringSize, _ringSize),
                painter: _ProgressRingPainter(
                  progress: progress,
                  hasPlan: hasPlan,
                ),
              ),
              _RingCenter(
                creditedMin: creditedMin,
                plannedH: plannedH,
                hasPlan: hasPlan,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingCenter extends StatelessWidget {
  final int creditedMin;
  final int plannedH;
  final bool hasPlan;

  const _RingCenter({
    required this.creditedMin,
    required this.plannedH,
    required this.hasPlan,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasPlan) {
      if (creditedMin > 0) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${creditedMin}m',
              style: GoogleFonts.inter(
                fontSize: 44,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'today',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: AppColors.textSlate,
              ),
            ),
          ],
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.add_circle_outline,
              size: 32, color: AppColors.textLight),
          const SizedBox(height: 8),
          Text(
            'Set plan',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppColors.textMedium,
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${creditedMin}m',
          style: GoogleFonts.inter(
            fontSize: 44,
            fontWeight: FontWeight.w700,
            color: AppColors.textDark,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'of ${plannedH}h today',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: AppColors.textSlate,
          ),
        ),
      ],
    );
  }
}

class _ProgressRingPainter extends CustomPainter {
  final double progress;
  final bool hasPlan;

  const _ProgressRingPainter({required this.progress, required this.hasPlan});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 28) / 2;
    const strokeWidth = 14.0;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Background track
    final bgPaint = Paint()
      ..color = const Color(0xFFE5E7EB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);

    if (!hasPlan || progress <= 0) return;

    // Progress arc
    final sweepAngle = 2 * pi * progress;
    final arcPaint = Paint()
      ..shader = const SweepGradient(
        startAngle: -pi / 2,
        endAngle: 3 * pi / 2,
        colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -pi / 2, sweepAngle, false, arcPaint);

    // Dot at the end of progress arc
    if (progress > 0.02) {
      final angle = -pi / 2 + sweepAngle;
      final dotX = center.dx + radius * cos(angle);
      final dotY = center.dy + radius * sin(angle);
      final dotPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(dotX, dotY), strokeWidth / 2 + 1, dotPaint);
      final dotBorderPaint = Paint()
        ..color = const Color(0xFF7C3AED)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(
          Offset(dotX, dotY), strokeWidth / 2 + 1, dotBorderPaint);
    }
  }

  @override
  bool shouldRepaint(_ProgressRingPainter old) =>
      old.progress != progress || old.hasPlan != hasPlan;
}
