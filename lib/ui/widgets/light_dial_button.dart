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
        return const Color(0xFFE2E8F0);
      case 3:
        return Color.fromARGB(255, widget.r, widget.g, widget.b);
      default:
        return AppTheme.amber;
    }
  }

  /// High-contrast outline container border color
  Color get _contrastBorderColor {
    if (!widget.isOn || widget.brightness == 0) {
      return widget.isEnabled ? AppTheme.borderBright : AppTheme.border;
    }
    final color = _activeColor;
    // Guard against very bright colors (e.g. pure white RGB) on light porcelain
    if (color.computeLuminance() > 0.60) {
      return const Color(0xFFB45309);
    }
    if (color.computeLuminance() < 0.06) {
      return AppTheme.textPrimary;
    }
    return color;
  }

  /// High-contrast readable text color for the primary status badge
  Color get _contrastTextColor {
    if (!widget.isOn || widget.brightness == 0) {
      return widget.isEnabled ? AppTheme.textPrimary : AppTheme.textMuted;
    }
    final color = _activeColor;
    // If color is too light to read against light porcelain/container, fall back to deep obsidian
    if (color.computeLuminance() > 0.42) {
      return const Color(0xFF1C1917);
    }
    return color;
  }

  /// High-contrast readable text color for subtitle badge
  Color get _contrastSubtitleColor {
    if (!widget.isOn || widget.brightness == 0) {
      return widget.isEnabled ? AppTheme.textSecondary : AppTheme.textMuted;
    }
    final color = _activeColor;
    if (color.computeLuminance() > 0.42) {
      return const Color(0xFF44403C);
    }
    return color;
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
    final borderColor = _contrastBorderColor;
    final textColor = _contrastTextColor;
    final subtitleColor = _contrastSubtitleColor;
    final isLit = widget.isOn && widget.brightness > 0;
    const size = 240.0;

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
                // 1. Serene Ambient Halo with dual-layer bloom
                AnimatedBuilder(
                  animation: _pulseGlowController,
                  builder: (context, _) {
                    final glowSpread = isLit ? 16.0 + (_pulseGlowController.value * 14.0) : 4.0;
                    final glowAlpha = isLit ? 0.32 : (widget.isEnabled ? 0.05 : 0.0);

                    return Container(
                      width: size - 20,
                      height: size - 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: glowColor.withValues(alpha: glowAlpha),
                            blurRadius: glowSpread * 2.2,
                            spreadRadius: glowSpread,
                          ),
                          if (isLit)
                            BoxShadow(
                              color: glowColor.withValues(alpha: glowAlpha * 0.7),
                              blurRadius: glowSpread * 1.2,
                              spreadRadius: glowSpread * 0.4,
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

                // 3. Concentric Subtle Bevel Ring
                Container(
                  width: size - 40,
                  height: size - 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isLit
                        ? borderColor.withValues(alpha: 0.04)
                        : AppTheme.surfaceRaised.withValues(alpha: 0.5),
                    border: Border.all(
                      color: isLit
                          ? borderColor.withValues(alpha: 0.30)
                          : AppTheme.border,
                      width: 1.2,
                    ),
                  ),
                ),

                // 4. Central Tactile Porcelain Core
                Container(
                  width: size - 48,
                  height: size - 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: const Alignment(0, -0.2),
                      radius: 0.85,
                      colors: isLit
                          ? [
                              Colors.white,
                              borderColor.withValues(alpha: 0.09),
                              const Color(0xFFFAF7F2),
                            ]
                          : [
                              Colors.white,
                              const Color(0xFFF9F6F0),
                              const Color(0xFFEFE8DC),
                            ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                    border: Border.all(
                      color: isLit
                          ? borderColor.withValues(alpha: 0.85)
                          : (widget.isEnabled ? AppTheme.borderBright : AppTheme.border),
                      width: isLit ? 2.2 : 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF3B2E1E).withValues(alpha: 0.10),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                      if (isLit)
                        BoxShadow(
                          color: glowColor.withValues(alpha: 0.22),
                          blurRadius: 22,
                          spreadRadius: 2,
                        ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Temple Icon Framed Medallion
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isLit
                              ? borderColor.withValues(alpha: 0.08)
                              : AppTheme.surfaceRaised.withValues(alpha: 0.45),
                          border: Border.all(
                            color: isLit
                                ? borderColor.withValues(alpha: 0.22)
                                : AppTheme.border.withValues(alpha: 0.70),
                            width: 1.0,
                          ),
                        ),
                        padding: const EdgeInsets.all(7),
                        child: Opacity(
                          opacity: isLit ? 1.0 : (widget.isEnabled ? 0.60 : 0.30),
                          child: Image.asset(
                            'assets/icons/temple_icon_transparent.png',
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Icon(
                              isLit ? Icons.temple_hindu_rounded : Icons.temple_hindu_outlined,
                              size: 30,
                              color: isLit
                                  ? textColor
                                  : (widget.isEnabled ? AppTheme.textSecondary : AppTheme.textMuted),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 7),

                      // Primary State Outline Container (LIGHTS ON / LIGHTS OFF)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.0),
                        decoration: BoxDecoration(
                          color: isLit
                              ? Colors.white.withValues(alpha: 0.95)
                              : AppTheme.surface.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: borderColor.withValues(alpha: isLit ? 0.85 : 0.65),
                            width: 1.4,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (isLit ? glowColor : const Color(0xFF3B2E1E)).withValues(alpha: isLit ? 0.16 : 0.04),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Luminous status indicator dot
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isLit ? borderColor : AppTheme.textMuted.withValues(alpha: 0.45),
                                boxShadow: isLit
                                    ? [
                                        BoxShadow(
                                          color: glowColor.withValues(alpha: 0.65),
                                          blurRadius: 4,
                                          spreadRadius: 1,
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isLit ? 'LIGHTS ON' : 'LIGHTS OFF',
                              style: AppTheme.heading(
                                size: 12.0,
                                color: textColor,
                                weight: FontWeight.w700,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 5),

                      // Secondary Subtitle Outline Container
                      Container(
                        constraints: const BoxConstraints(maxWidth: 160),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.0),
                        decoration: BoxDecoration(
                          color: isLit
                              ? borderColor.withValues(alpha: 0.08)
                              : AppTheme.surfaceRaised.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isLit
                                ? borderColor.withValues(alpha: 0.40)
                                : (widget.isEnabled ? AppTheme.borderBright : AppTheme.border),
                            width: 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Text(
                          _modeSubtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: AppTheme.body(
                            size: 8.5,
                            weight: FontWeight.w600,
                            color: subtitleColor,
                            letterSpacing: 0.6,
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

    // Outer track circle
    final outerTrackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = isEnabled ? AppTheme.border : AppTheme.border.withValues(alpha: 0.5);
    canvas.drawCircle(center, radius, outerTrackPaint);

    // Inner guide track circle
    final innerTrackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = isEnabled ? AppTheme.border.withValues(alpha: 0.6) : AppTheme.border.withValues(alpha: 0.3);
    canvas.drawCircle(center, radius - 11, innerTrackPaint);

    const segmentCount = 24;
    for (var i = 0; i < segmentCount; i++) {
      final segAngle = (i * 2 * math.pi / segmentCount);
      final isMajor = i % 6 == 0;

      final p1 = Offset(
        center.dx + (radius - (isMajor ? 11 : 6)) * math.cos(segAngle),
        center.dy + (radius - (isMajor ? 11 : 6)) * math.sin(segAngle),
      );
      final p2 = Offset(
        center.dx + radius * math.cos(segAngle),
        center.dy + radius * math.sin(segAngle),
      );

      final segPaint = Paint()
        ..strokeCap = StrokeCap.round
        ..color = isActive
            ? (isMajor ? color : color.withValues(alpha: 0.60))
            : (isEnabled
                ? (isMajor ? AppTheme.borderBright : AppTheme.border.withValues(alpha: 0.6))
                : AppTheme.border.withValues(alpha: 0.3))
        ..strokeWidth = isMajor ? 2.4 : 1.4;

      canvas.drawLine(p1, p2, segPaint);

      // Cardinal gemstone pips at major points
      if (isMajor) {
        final pipCenter = Offset(
          center.dx + (radius - 13) * math.cos(segAngle),
          center.dy + (radius - 13) * math.sin(segAngle),
        );
        final pipPaint = Paint()
          ..style = PaintingStyle.fill
          ..color = isActive
              ? color
              : (isEnabled ? AppTheme.borderBright : AppTheme.border.withValues(alpha: 0.4));
        canvas.drawCircle(pipCenter, 2.2, pipPaint);

        if (isActive) {
          final pipGlowPaint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0
            ..color = color.withValues(alpha: 0.35);
          canvas.drawCircle(pipCenter, 4.0, pipGlowPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LightRingPainter old) =>
      old.isActive != isActive || old.isEnabled != isEnabled || old.color != color;
}
