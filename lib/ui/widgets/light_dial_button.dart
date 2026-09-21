import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/haptics.dart';
import '../theme.dart';

/// Tactile glowing dial button for Temple Lights in Serene Light Theme.
class LightDialButton extends StatefulWidget {
  const LightDialButton({
    super.key,
    required this.isOn,
    required this.mode,
    required this.brightness,
    required this.r,
    required this.g,
    required this.b,
    required this.isEnabled,
    required this.onToggle,
  });

  final bool isOn;
  final int mode;
  final int brightness;
  final int r, g, b;
  final bool isEnabled;
  final VoidCallback onToggle;

  @override
  State<LightDialButton> createState() => _LightDialButtonState();
}

class _LightDialButtonState extends State<LightDialButton> with TickerProviderStateMixin {
  late final AnimationController _pulseGlowController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  bool _isPressed = false;

  @override
  void dispose() {
    _pulseGlowController.dispose();
    super.dispose();
  }

  Color get _activeColor {
    if (!widget.isOn || widget.brightness == 0) return AppTheme.textMuted;
    switch (widget.mode) {
      case 0: // All warm white (rich warm amber)
        return const Color(0xFFD97706);
      case 1: // Center warm white (golden amber)
        return const Color(0xFFE68A00);
      case 2: // All pure white (crisp golden aura)
        return const Color(0xFF475569);
      case 3: // Custom RGB
        return Color.fromARGB(255, widget.r, widget.g, widget.b);
      default:
        return AppTheme.amber;
    }
  }

  Color get _glowColor {
    if (!widget.isOn || widget.brightness == 0) return Colors.transparent;
    switch (widget.mode) {
      case 0:
      case 1:
        return const Color(0xFFF59E0B);
      case 2:
        return const Color(0xFF94A3B8);
      case 3:
        return Color.fromARGB(255, widget.r, widget.g, widget.b);
      default:
        return AppTheme.amber;
    }
  }

  String get _modeSubtitle {
    if (!widget.isOn || widget.brightness == 0) return 'TAP TO TURN ON';
    switch (widget.mode) {
      case 0:
        return 'MODE 1 • ALL 2.5M WARM';
      case 1:
        return 'MODE 2 • CENTER 1.5M';
      case 2:
        return 'MODE 3 • ALL 2.5M WHITE';
      case 3:
        return 'MODE 4 • CUSTOM RGB';
      default:
        return 'TAP TO SWITCH OFF';
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = _activeColor;
    final glowColor = _glowColor;
    final isLit = widget.isOn && widget.brightness > 0;
    const size = 236.0;

    return Center(
      child: GestureDetector(
        onTapDown: (_) {
          if (!widget.isEnabled) return;
          setState(() => _isPressed = true);
          AppHaptics.tap();
        },
        onTapUp: (_) {
          if (!widget.isEnabled) return;
          setState(() => _isPressed = false);
          widget.onToggle();
        },
        onTapCancel: () {
          if (!widget.isEnabled) return;
          setState(() => _isPressed = false);
        },
        child: AnimatedScale(
          scale: _isPressed ? 0.94 : 1.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 1. Serene Ambient Halo
                AnimatedBuilder(
                  animation: _pulseGlowController,
                  builder: (context, _) {
                    final glowSpread = isLit ? 16.0 + (_pulseGlowController.value * 14.0) : 4.0;
                    final glowAlpha = isLit ? 0.35 : (widget.isEnabled ? 0.05 : 0.0);

                    return Container(
                      width: size - 24,
                      height: size - 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: glowColor.withValues(alpha: glowAlpha),
                            blurRadius: glowSpread * 2,
                            spreadRadius: glowSpread,
                          ),
                        ],
                      ),
                    );
                  },
                ),

                // 2. Outer Sculpted Track Ring
                CustomPaint(
                  size: const Size(size, size),
                  painter: _LightRingPainter(
                    isActive: isLit,
                    isEnabled: widget.isEnabled,
                    color: activeColor,
                  ),
                ),

                // 3. Central Tactile Porcelain Core
                Container(
                  width: size - 62,
                  height: size - 62,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: isLit
                          ? [
                              activeColor.withValues(alpha: 0.16),
                              Colors.white,
                              const Color(0xFFFBF9F5),
                            ]
                          : [
                              Colors.white,
                              const Color(0xFFF9F6F0),
                              const Color(0xFFEDE7DC),
                            ],
                      stops: const [0.0, 0.65, 1.0],
                    ),
                    border: Border.all(
                      color: isLit
                          ? activeColor.withValues(alpha: 0.8)
                          : (widget.isEnabled ? AppTheme.borderBright : AppTheme.border),
                      width: isLit ? 2.5 : 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF3B2E1E).withValues(alpha: 0.08),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                      if (isLit)
                        BoxShadow(
                          color: glowColor.withValues(alpha: 0.25),
                          blurRadius: 22,
                          spreadRadius: 2,
                        ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 54,
                        height: 54,
                        child: Opacity(
                          opacity: isLit ? 1.0 : (widget.isEnabled ? 0.55 : 0.30),
                          child: Image.asset(
                            'assets/icons/temple_icon_transparent.png',
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Icon(
                              isLit ? Icons.temple_hindu_rounded : Icons.temple_hindu_outlined,
                              size: 48,
                              color: isLit
                                  ? activeColor
                                  : (widget.isEnabled ? AppTheme.textSecondary : AppTheme.textMuted),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isLit ? 'LIGHTS ON' : 'LIGHTS OFF',
                        style: AppTheme.heading(
                          size: 16,
                          color: isLit
                              ? activeColor
                              : (widget.isEnabled ? AppTheme.textPrimary : AppTheme.textMuted),
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: isLit
                              ? activeColor.withValues(alpha: 0.10)
                              : AppTheme.surfaceRaised.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _modeSubtitle,
                          style: AppTheme.body(
                            size: 9.5,
                            weight: FontWeight.w600,
                            color: isLit ? activeColor : AppTheme.textMuted,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LightRingPainter extends CustomPainter {
  _LightRingPainter({
    required this.isActive,
    required this.isEnabled,
    required this.color,
  });

  final bool isActive;
  final bool isEnabled;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 4;

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = isEnabled ? AppTheme.border : AppTheme.border.withValues(alpha: 0.5);
    canvas.drawCircle(center, radius, trackPaint);

    const segmentCount = 24;
    for (var i = 0; i < segmentCount; i++) {
      final segAngle = (i * 2 * math.pi / segmentCount);
      final isMajor = i % 6 == 0;

      final p1 = Offset(
        center.dx + (radius - (isMajor ? 10 : 5)) * math.cos(segAngle),
        center.dy + (radius - (isMajor ? 10 : 5)) * math.sin(segAngle),
      );
      final p2 = Offset(
        center.dx + (radius + 2) * math.cos(segAngle),
        center.dy + (radius + 2) * math.sin(segAngle),
      );

      final segPaint = Paint()
        ..color = isActive
            ? (isMajor ? color : color.withValues(alpha: 0.5))
            : (isEnabled
                ? (isMajor ? AppTheme.borderBright : AppTheme.border.withValues(alpha: 0.6))
                : AppTheme.border.withValues(alpha: 0.3))
        ..strokeWidth = isMajor ? 2.5 : 1.5;

      canvas.drawLine(p1, p2, segPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _LightRingPainter old) =>
      old.isActive != isActive || old.isEnabled != isEnabled || old.color != color;
}
