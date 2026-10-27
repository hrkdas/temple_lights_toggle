import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/haptics.dart';
import '../../../domain/models.dart';
import '../../../domain/providers.dart';
import '../../../ui/theme.dart';

enum GlowTestMode {
  diya(
    label: 'Diya Flutter',
    description: 'Warm 2200K sacred flickering candle flame',
    icon: Icons.local_fire_department_rounded,
    color: AppTheme.amber,
  ),
  aarti(
    label: 'Aarti Breathe',
    description: 'Golden meditative breathing pulse 10%–100%',
    icon: Icons.brightness_auto_rounded,
    color: AppTheme.gold,
  ),
  align(
    label: 'Strip Alignment',
    description: 'Start (Red) • Center (Green) • End (Blue)',
    icon: Icons.straighten_rounded,
    color: AppTheme.cyan,
  ),
  identify(
    label: '3-Blink Locate',
    description: 'Rapid white strobe to spot physical strip',
    icon: Icons.highlight_rounded,
    color: AppTheme.green,
  );

  const GlowTestMode({
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
  });

  final String label;
  final String description;
  final IconData icon;
  final Color color;
}

/// Pulsing indicator dot replacing a generic spinner when hardware test is active.
/// Adapted from Boturo's `_PulsingDot` with sacred temple styling.
class PulsingStatusDot extends StatefulWidget {
  const PulsingStatusDot({
    super.key,
    required this.color,
    this.size = 8.0,
  });

  final Color color;
  final double size;

  @override
  State<PulsingStatusDot> createState() => _PulsingStatusDotState();
}

class _PulsingStatusDotState extends State<PulsingStatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    )..repeat(reverse: true);

    _scale = Tween<double>(begin: 0.65, end: 1.15).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    _opacity = Tween<double>(begin: 0.35, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) => Opacity(
          opacity: _opacity.value,
          child: Transform.scale(
            scale: _scale.value,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color,
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.6),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dedicated Glow Test Panel allowing users to test live hardware patterns with
/// a 5-second auto-timeout, tap-to-stop, and live feedback.
class GlowTestPanel extends ConsumerStatefulWidget {
  const GlowTestPanel({
    super.key,
    required this.device,
    required this.isConnected,
    this.onConnectRequested,
  });

  final PairedDevice device;
  final bool isConnected;
  final VoidCallback? onConnectRequested;

  @override
  ConsumerState<GlowTestPanel> createState() => _GlowTestPanelState();
}

class _GlowTestPanelState extends ConsumerState<GlowTestPanel> {
  GlowTestMode _selectedMode = GlowTestMode.diya;
  bool _isRunning = false;
  int _secondsLeft = 5;
  Timer? _countdownTimer;

  static const int _kTestDurationSec = 5;

  @override
  void dispose() {
    _cancelTest(silent: true);
    super.dispose();
  }

  void _cancelTest({bool silent = false}) {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    if (_isRunning) {
      if (!silent) {
        AppHaptics.selection();
      }
      if (mounted) {
        setState(() {
          _isRunning = false;
          _secondsLeft = _kTestDurationSec;
        });
      }
    }
  }

  Future<void> _startTest() async {
    if (!widget.isConnected) {
      AppHaptics.warning();
      return;
    }

    AppHaptics.medium();
    setState(() {
      _isRunning = true;
      _secondsLeft = _kTestDurationSec;
    });

    final ctrl = ref.read(lightControlProvider.notifier);

    // Dispatch hardware pattern according to selected mode
    switch (_selectedMode) {
      case GlowTestMode.diya:
        await ctrl.previewAnimation(
          transitionStyle: 0,
          ambientStyle: 1, // Diya Candle
          depth: 8,
        );
        break;
      case GlowTestMode.aarti:
        await ctrl.previewAnimation(
          transitionStyle: 0,
          ambientStyle: 0, // Gentle Breathe
          depth: 6,
        );
        break;
      case GlowTestMode.align:
        await ctrl.triggerHwTest(); // Start (Red), Center (Green), End (Blue)
        break;
      case GlowTestMode.identify:
        await ctrl.identifyDevice(); // 3 crisp white flashes
        break;
    }

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        _cancelTest();
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Header: Icon + Title + Status Pill
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  size: 18,
                  color: AppTheme.amber,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TEST LIGHT GLOW',
                      style: AppTheme.heading(
                        size: 12,
                        color: AppTheme.textMuted,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Preview light patterns on physical hardware',
                      style: AppTheme.body(size: 11, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              if (_isRunning) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _selectedMode.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _selectedMode.color.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PulsingStatusDot(color: _selectedMode.color, size: 7),
                      const SizedBox(width: 6),
                      Text(
                        '${_secondsLeft}s',
                        style: AppTheme.mono(
                          size: 11,
                          color: _selectedMode.color,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 14),

          // Disconnected Banner if offline
          if (!widget.isConnected) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.bluetooth_disabled_rounded,
                    size: 18,
                    color: AppTheme.textMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Connect via Bluetooth to test live glow patterns',
                      style: AppTheme.body(size: 11, color: AppTheme.textMuted),
                    ),
                  ),
                  if (widget.onConnectRequested != null)
                    TextButton(
                      onPressed: widget.onConnectRequested,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: AppTheme.cyan,
                      ),
                      child: Text(
                        'Connect',
                        style: AppTheme.heading(size: 11, color: AppTheme.cyan),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // 4-Mode Chips Grid
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = (constraints.maxWidth - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: GlowTestMode.values.map((mode) {
                  final isSelected = _selectedMode == mode;
                  final isModeRunning = _isRunning && isSelected;

                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _isRunning
                        ? null
                        : () {
                            AppHaptics.selection();
                            setState(() => _selectedMode = mode);
                          },
                    child: Container(
                      width: itemWidth,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.surface : AppTheme.surface.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? mode.color
                              : AppTheme.border.withValues(alpha: 0.8),
                          width: isSelected ? 1.5 : 1.0,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: mode.color.withValues(alpha: 0.12),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            mode.icon,
                            size: 18,
                            color: isSelected ? mode.color : AppTheme.textMuted,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  mode.label,
                                  style: AppTheme.heading(
                                    size: 11.5,
                                    color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  isModeRunning ? 'Active...' : mode.description.split('•').first,
                                  style: AppTheme.body(
                                    size: 9.5,
                                    color: isModeRunning ? mode.color : AppTheme.textMuted,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            Icon(
                              Icons.check_circle_rounded,
                              size: 14,
                              color: mode.color,
                            ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),

          const SizedBox(height: 14),

          // Main Trigger Button (Start Test / Cancel Test)
          SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton.icon(
              onPressed: !widget.isConnected
                  ? null
                  : _isRunning
                      ? _cancelTest
                      : _startTest,
              icon: Icon(
                _isRunning ? Icons.stop_circle_rounded : Icons.play_circle_filled_rounded,
                size: 19,
              ),
              label: Text(
                _isRunning
                    ? 'Cancel Test (${_secondsLeft}s remaining)'
                    : 'Run ${_selectedMode.label}',
                style: AppTheme.heading(size: 13, color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isRunning ? AppTheme.red : _selectedMode.color,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                disabledBackgroundColor: AppTheme.borderBright.withValues(alpha: 0.5),
                disabledForegroundColor: AppTheme.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
