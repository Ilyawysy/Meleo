import 'dart:math';
import 'package:flutter/material.dart';

class TimerRing extends StatelessWidget {
  final double progress;
  final Widget child;
  final double size;

  const TimerRing({
    super.key,
    required this.progress,
    required this.child,
    this.size = 240,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _TimerRingPainter(progress: progress),
          ),
          child,
        ],
      ),
    );
  }
}

class _TimerRingPainter extends CustomPainter {
  final double progress;
  _TimerRingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 10) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final bgPaint = Paint()
      ..color = const Color(0xFFE5E7EB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10;
    canvas.drawCircle(center, radius, bgPaint);

    if (progress > 0) {
      final sweepAngle = 2 * pi * progress;
      final arcPaint = Paint()
        ..shader = const SweepGradient(
          startAngle: -pi / 2,
          endAngle: 3 * pi / 2,
          colors: [Color(0xFF2563EB), Color(0xFF7C3AED)],
        ).createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, -pi / 2, sweepAngle, false, arcPaint);
    }
  }

  @override
  bool shouldRepaint(_TimerRingPainter old) => old.progress != progress;
}
