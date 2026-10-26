import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/haptics.dart';
import '../../domain/models.dart';
import '../../domain/providers.dart';
import '../theme.dart';

/// Real-time visual preview and physical audition widget for LED strip animations.
/// Simulates all 7 devotional transitions and 7 living ambient auras on an animated canvas,
/// and allows 1-tap live audition on the connected ESP32 strip.
class LiveAnimationPreviewWidget extends ConsumerStatefulWidget {
  const LiveAnimationPreviewWidget({
    super.key,
    required this.transitionStyle,
    required this.ambientStyle,
    this.ambientDepth = 8,
    this.r = 255,
    this.g = 147,
    this.b = 41,
    this.brightness = 255,
    this.onAudition,
    this.showAuditionButton = true,
  });

  final int transitionStyle;
  final int ambientStyle;
  final int ambientDepth;
  final int r;
  final int g;
  final int b;
  final int brightness;
  final VoidCallback? onAudition;
  final bool showAuditionButton;

  @override
  ConsumerState<LiveAnimationPreviewWidget> createState() => _LiveAnimationPreviewWidgetState();
}

class _LiveAnimationPreviewWidgetState extends ConsumerState<LiveAnimationPreviewWidget>
    with TickerProviderStateMixin {
  late final AnimationController _ambientController;
  late final AnimationController _transitionController;
  bool _isPlayingTransition = false;
  bool _auditionSuccess = false;

  @override
  void initState() {
    super.initState();
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _transitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _transitionController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _isPlayingTransition = false);
      }
    });

    // Auto-play the transition once on mount
    _playTransition();
  }

  @override
  void didUpdateWidget(covariant LiveAnimationPreviewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transitionStyle != widget.transitionStyle) {
      _playTransition();
    }
  }

  @override
  void dispose() {
    _ambientController.dispose();
    _transitionController.dispose();
    super.dispose();
  }

  void _playTransition() {
    setState(() => _isPlayingTransition = true);
    _transitionController.forward(from: 0.0);
    AppHaptics.selection();
  }

  void _handleReplay() {
    _playTransition();
    // Also trigger strip audition if connected so physical strip replays in unison
    ref.read(lightControlProvider.notifier).previewAnimation(
          transitionStyle: widget.transitionStyle,
          ambientStyle: widget.ambientStyle,
          depth: widget.ambientDepth,
        );
  }

  Future<void> _auditionOnStrip() async {
    widget.onAudition?.call();
    _playTransition(); // Synchronize on-screen preview with physical strip ignition
    await AppHaptics.medium();
    await ref.read(lightControlProvider.notifier).previewAnimation(
          transitionStyle: widget.transitionStyle,
          ambientStyle: widget.ambientStyle,
          depth: widget.ambientDepth,
        );

    if (mounted) {
      setState(() => _auditionSuccess = true);
      Future.delayed(const Duration(milliseconds: 1400), () {
        if (mounted) setState(() => _auditionSuccess = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final transName = (widget.transitionStyle >= 0 &&
            widget.transitionStyle < LightState.transitionStyleNames.length)
        ? LightState.transitionStyleNames[widget.transitionStyle]
        : 'Center-Out Dawn';

    final ambName = (widget.ambientStyle >= 0 &&
            widget.ambientStyle < LightState.ambientStyleNames.length)
        ? LightState.ambientStyleNames[widget.ambientStyle]
        : 'Gentle Breathing';

    final baseColor = Color.fromARGB(255, widget.r, widget.g, widget.b);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: baseColor.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header / Labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: baseColor,
                      boxShadow: [
                        BoxShadow(
                          color: baseColor.withValues(alpha: 0.6),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'LIVE ANIMATION PREVIEW',
                    style: AppTheme.heading(size: 11, color: AppTheme.textMuted, letterSpacing: 1.2),
                  ),
                ],
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Text(
                      _isPlayingTransition ? 'Transitioning' : ambName,
                      style: AppTheme.mono(size: 10, color: _isPlayingTransition ? AppTheme.amber : AppTheme.cyan),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Animated LED Canvas
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 58,
              width: double.infinity,
              color: Colors.black.withValues(alpha: 0.85),
              child: AnimatedBuilder(
                animation: Listenable.merge([_ambientController, _transitionController]),
                builder: (context, _) {
                  return CustomPaint(
                    painter: _AnimationPreviewPainter(
                      transitionStyle: widget.transitionStyle,
                      ambientStyle: widget.ambientStyle,
                      ambientDepth: widget.ambientDepth,
                      baseColor: baseColor,
                      brightness: widget.brightness,
                      transitionProgress: _isPlayingTransition ? _transitionController.value : 1.0,
                      ambientPhase: _ambientController.value,
                    ),
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: 10),

          // Action Controls (Replay & Audition on Hardware)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: Icon(
                    _isPlayingTransition ? Icons.refresh_rounded : Icons.play_arrow_rounded,
                    size: 16,
                    color: AppTheme.amber,
                  ),
                  label: Text(
                    _isPlayingTransition ? 'Replaying...' : 'Replay $transName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.heading(size: 11.5, color: AppTheme.amber),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppTheme.amber.withValues(alpha: 0.4)),
                    backgroundColor: AppTheme.amber.withValues(alpha: 0.08),
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _handleReplay,
                ),
              ),
              if (widget.showAuditionButton) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: Icon(
                      _auditionSuccess ? Icons.check_circle_rounded : Icons.bluetooth_audio_rounded,
                      size: 16,
                      color: Colors.black,
                    ),
                    label: Text(
                      _auditionSuccess ? 'Auditioning!' : 'Audition on Strip',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.heading(size: 11.5, color: Colors.black),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _auditionSuccess ? AppTheme.green : AppTheme.amber,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 1,
                    ),
                    onPressed: _auditionOnStrip,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _AnimationPreviewPainter extends CustomPainter {
  _AnimationPreviewPainter({
    required this.transitionStyle,
    required this.ambientStyle,
    required this.ambientDepth,
    required this.baseColor,
    required this.brightness,
    required this.transitionProgress,
    required this.ambientPhase,
  });

  final int transitionStyle;
  final int ambientStyle;
  final int ambientDepth;
  final Color baseColor;
  final int brightness;
  final double transitionProgress;
  final double ambientPhase;

  static const int kLedCount = 60;

  @override
  void paint(Canvas canvas, Size size) {
    final ledSpacing = size.width / (kLedCount + 1);
    final centerY = size.height / 2;

    // Background track guide
    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.04)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(ledSpacing, centerY), Offset(size.width - ledSpacing, centerY), trackPaint);

    for (int i = 0; i < kLedCount; i++) {
      final x = ledSpacing * (i + 1);
      final normDist = _getNormalizedSpatialDist(i, kLedCount, transitionStyle);

      // 1. Transition Progress Factor for this specific LED
      final tFactor = _computeTransitionFactor(normDist, transitionProgress);
      if (tFactor <= 0.001) {
        // LED is currently unlit in transition
        final unlitPaint = Paint()..color = const Color(0xFF222222);
        canvas.drawCircle(Offset(x, centerY), 2.2, unlitPaint);
        continue;
      }

      // 2. Ambient Aura Factor
      final aFactor = _computeAmbientFactor(i, kLedCount, ambientStyle, ambientDepth, ambientPhase);

      // 3. Chromatic color modulation (Rainbow Cycle / Prismatic Aura)
      Color finalColor = baseColor;
      if (ambientStyle == 6) {
        final hue = ((ambientPhase * 360) + (i * 360.0 / kLedCount)) % 360.0;
        final rainbow = HSVColor.fromAHSV(1.0, hue, 0.85, 1.0).toColor();
        final depth = (ambientDepth / 100.0).clamp(0.0, 1.0);
        finalColor = Color.lerp(baseColor, rainbow, depth) ?? rainbow;
      }

      final effBright = (brightness / 255.0) * tFactor * aFactor;
      final ledColor = finalColor.withValues(alpha: effBright.clamp(0.0, 1.0));

      // Draw outer ambient glow
      if (effBright > 0.15) {
        final glowPaint = Paint()
          ..color = ledColor.withValues(alpha: (effBright * 0.45).clamp(0.0, 0.6))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0);
        canvas.drawCircle(Offset(x, centerY), 5.5, glowPaint);
      }

      // Draw primary LED dot
      final dotPaint = Paint()..color = ledColor;
      canvas.drawCircle(Offset(x, centerY), 2.8, dotPaint);

      // Draw intense white/core reflection highlight
      if (effBright > 0.6) {
        final corePaint = Paint()
          ..color = Colors.white.withValues(alpha: ((effBright - 0.6) / 0.4 * 0.75).clamp(0.0, 0.8));
        canvas.drawCircle(Offset(x, centerY), 1.2, corePaint);
      }
    }
  }

  double _getNormalizedSpatialDist(int i, int total, int style) {
    if (total <= 1) return 0.0;
    switch (style) {
      case 1: // Sunrise Flow (Left to Right)
        return i / (total - 1);
      case 2: // Uniform Smooth Fade
        return 0.0;
      case 3: // Sunset Cascade (Right to Left)
        return 1.0 - (i / (total - 1));
      case 4: // Dual Convergence (Ends to Center)
        final center = (total - 1) / 2.0;
        final cDist = (i - center).abs() / center;
        return 1.0 - cDist;
      case 5: // Sparkle Ignition (Pseudo-random hash)
        return ((i * 37 + 13) % 100) / 100.0;
      case 6: // Segment Domino (5-step cascade)
        return ((i * 5) ~/ total) * 0.20;
      case 0: // Center-Out Dawn
      default:
        final center = (total - 1) / 2.0;
        return (i - center).abs() / center;
    }
  }

  double _computeTransitionFactor(double normDist, double progress) {
    if (progress >= 1.0) return 1.0;
    if (transitionStyle == 2) {
      // Uniform smooth fade
      return _smootherstep(progress);
    }

    // Propagation delay: 50% propagation time, 50% fade time per LED
    const propWeight = 0.55;
    const fadeWeight = 0.45;
    final startT = normDist * propWeight;
    final endT = startT + fadeWeight;

    if (progress <= startT) return 0.0;
    if (progress >= endT) return 1.0;

    final u = (progress - startT) / fadeWeight;
    return _smootherstep(u);
  }

  double _computeAmbientFactor(
    int i,
    int total,
    int style,
    int depthPct,
    double phase,
  ) {
    final depth = (depthPct / 100.0).clamp(0.02, 0.5);

    switch (style) {
      case 0: // Pure Solid
        return 1.0;
      case 1: // Gentle Breathing
        final sinVal = (1.0 - math.cos(phase * 2 * math.pi)) * 0.5;
        return 1.0 - (depth * sinVal);
      case 2: // Diya Candle Flutter
        final flicker = (math.sin(phase * 28 + (i * 0.4)) * 0.5 +
            math.cos(phase * 47 + (i * 0.7)) * 0.3 +
            math.sin(phase * 83) * 0.2);
        return 1.0 - (depth * 0.5 * (1.0 + flicker));
      case 3: // Starlight Twinkle
        final shimmer = math.sin((phase * 16) + (i * 2.39));
        return 1.0 - (depth * 0.4 * (1.0 + shimmer));
      case 4: // Amber Embers
        final slowWave = 0.5 * (1.0 + math.sin(phase * 2 * math.pi));
        final fastPulse = 0.5 * (1.0 + math.sin(phase * 8 * math.pi + (i * 0.2)));
        return 1.0 - (depth * (0.6 * slowWave + 0.4 * fastPulse));
      case 5: // Aurora Flow
        final wave = 0.5 * (1.0 + math.sin((phase * 2 * math.pi) + (i * 4 * math.pi / total)));
        return 1.0 - (depth * 0.6 * wave);
      case 6: // Rainbow Cycle
        return 1.0;
      default:
        return 1.0;
    }
  }

  double _smootherstep(double t) {
    final c = t.clamp(0.0, 1.0);
    return c * c * c * (c * (c * 6 - 15) + 10);
  }

  @override
  bool shouldRepaint(covariant _AnimationPreviewPainter oldDelegate) {
    return oldDelegate.transitionProgress != transitionProgress ||
        oldDelegate.ambientPhase != ambientPhase ||
        oldDelegate.transitionStyle != transitionStyle ||
        oldDelegate.ambientStyle != ambientStyle ||
        oldDelegate.ambientDepth != ambientDepth ||
        oldDelegate.baseColor != baseColor ||
        oldDelegate.brightness != brightness;
  }
}
