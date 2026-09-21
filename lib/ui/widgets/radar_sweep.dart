import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

/// 360° animated radar sweep widget for searching BLE devices.
class RadarSweep extends StatefulWidget {
  const RadarSweep({
    super.key,
    required this.size,
    this.child,
    this.ringCount = 3,
    this.color = AppTheme.amber,
  });

  final double size;
  final Widget? child;
  final int ringCount;
  final Color color;

  @override
  State<RadarSweep> createState() => _RadarSweepState();
}

class _RadarSweepState extends State<RadarSweep> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (ctx, _) => CustomPaint(
          painter: _RadarPainter(
            angle: _controller.value * 2 * math.pi,
            ringCount: widget.ringCount,
            color: widget.color,
          ),
          child: widget.child == null ? null : Center(child: widget.child),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.angle,
    required this.ringCount,
    required this.color,
  });

  final double angle;
  final int ringCount;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;

    // Concentric rings
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color.withValues(alpha: 0.15);

    for (var i = 1; i <= ringCount; i++) {
      canvas.drawCircle(center, radius * (i / ringCount), ringPaint);
    }

    // Cross hair lines
    final crossPaint = Paint()
      ..color = color.withValues(alpha: 0.10)
      ..strokeWidth = 1.0;

    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      crossPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      crossPaint,
    );

    // Gradient Sweep Wedge
    final shader = SweepGradient(
      colors: [
        color.withValues(alpha: 0.0),
        color.withValues(alpha: 0.45),
      ],
      stops: const [0.0, 1.0],
      startAngle: angle - 0.7,
      endAngle: angle,
      transform: const GradientRotation(0),
    ).createShader(Rect.fromCircle(center: center, radius: radius));

    final sweepPaint = Paint()..shader = shader;
    final path = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: radius),
        angle - 0.7,
        0.7,
        false,
      )
      ..close();
    canvas.drawPath(path, sweepPaint);

    // Leading edge line
    final leadPaint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = 2.0;

    canvas.drawLine(
      center,
      Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      ),
      leadPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) =>
      old.angle != angle || old.ringCount != ringCount || old.color != color;
}
