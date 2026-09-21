import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models.dart';
import '../../domain/providers.dart';
import '../theme.dart';

/// Small expandable button offering 1-click quick auto turn-off timers (10m, 15m, 20m, or custom duration).
class AutoOffTimerWidget extends ConsumerStatefulWidget {
  const AutoOffTimerWidget({
    super.key,
    this.isEnabled = true,
  });

  final bool isEnabled;

  @override
  ConsumerState<AutoOffTimerWidget> createState() => _AutoOffTimerWidgetState();
}

class _AutoOffTimerWidgetState extends ConsumerState<AutoOffTimerWidget>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  static const List<int> _presetMinutes = [10, 15, 20, 30];

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    final willExpand = !_isExpanded;
    setState(() => _isExpanded = willExpand);

    if (willExpand) {
      _scrollToEnd();
    }
  }

  void _scrollToEnd() {
    void doScroll() {
      if (!mounted || !_isExpanded) return;
      try {
        final scrollable = Scrollable.maybeOf(context);
        if (scrollable != null && scrollable.position.hasContentDimensions) {
          final maxScroll = scrollable.position.maxScrollExtent;
          scrollable.position.animateTo(
            maxScroll,
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutCubic,
          );
        } else {
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutCubic,
            alignment: 1.0,
            alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          );
        }
      } catch (_) {}
    }

    // Paced dual scroll triggers: one during expansion, one at layout completion
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 70), doScroll);
      Future.delayed(const Duration(milliseconds: 260), doScroll);
    });
  }

  void _showCustomTimePicker(BuildContext context, int currentMinutes) async {
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => _DurationPickerDialog(initialMinutes: currentMinutes),
    );

    if (picked != null && picked > 0) {
      ref.read(autoOffTimerProvider.notifier).setSelectedMinutes(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final timerState = ref.watch(autoOffTimerProvider);
    final notifier = ref.read(autoOffTimerProvider.notifier);
    final isRunning = timerState.isRunning;

    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isRunning
                ? AppTheme.gold.withValues(alpha: 0.7)
                : (_isExpanded ? AppTheme.cyan.withValues(alpha: 0.6) : AppTheme.border),
            width: isRunning || _isExpanded ? 1.5 : 1.0,
          ),
          boxShadow: [
            if (isRunning)
              BoxShadow(
                color: AppTheme.gold.withValues(alpha: 0.25),
                blurRadius: 14,
                spreadRadius: 1,
              )
            else if (_isExpanded)
              BoxShadow(
                color: AppTheme.cyan.withValues(alpha: 0.12),
                blurRadius: 12,
                spreadRadius: 0,
              ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. Collapsed Header Bar (1-Click trigger + Expand toggle)
            _buildHeaderRow(context, timerState, notifier, isRunning),

            // 2. Expanded Editor Panel
            if (_isExpanded) ...[
              const Divider(height: 1, color: AppTheme.border),
              _buildExpandedPanel(context, timerState, notifier, isRunning),
            ],
          ],
        ),
      ),
    );
  }

  /// Compact header row providing 1-click start and live countdown.
  Widget _buildHeaderRow(
    BuildContext context,
    AutoOffTimerState timerState,
    AutoOffTimerNotifier notifier,
    bool isRunning,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // Timer Icon with animated glow
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, _) {
              return Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isRunning
                      ? AppTheme.gold.withValues(alpha: 0.15 + (_pulseController.value * 0.15))
                      : AppTheme.surfaceRaised,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isRunning ? AppTheme.gold.withValues(alpha: 0.6) : AppTheme.border,
                    width: 1,
                  ),
                ),
                child: Icon(
                  isRunning ? Icons.hourglass_top_rounded : Icons.timer_outlined,
                  size: 18,
                  color: isRunning ? AppTheme.gold : AppTheme.cyan,
                ),
              );
            },
          ),
          const SizedBox(width: 10),

          // Label / Countdown Text (Tappable area)
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: widget.isEnabled ? _toggleExpanded : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        isRunning ? 'AUTO-OFF COUNTDOWN' : 'AUTO-OFF TIMER',
                        style: AppTheme.heading(
                          size: 10.5,
                          letterSpacing: 1.2,
                          color: isRunning ? AppTheme.gold : AppTheme.textSecondary,
                        ),
                      ),
                      if (isRunning) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.gold,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isRunning
                        ? '${timerState.formattedRemaining} remaining'
                        : 'Quick: ${timerState.formattedSelectedDuration}',
                    style: AppTheme.mono(
                      size: isRunning ? 14 : 12.5,
                      weight: FontWeight.w700,
                      color: isRunning ? AppTheme.gold : AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 1-Click Quick Action Button (Start or Cancel)
          if (isRunning) ...[
            TextButton.icon(
              icon: const Icon(Icons.close_rounded, size: 14, color: AppTheme.red),
              label: Text(
                'STOP',
                style: AppTheme.heading(size: 11, color: AppTheme.red, letterSpacing: 1.0),
              ),
              style: TextButton.styleFrom(
                backgroundColor: AppTheme.red.withValues(alpha: 0.15),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: const Size(64, 34),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: AppTheme.red, width: 1),
                ),
              ),
              onPressed: widget.isEnabled ? () => notifier.cancelTimer() : null,
            ),
          ] else ...[
            ElevatedButton.icon(
              icon: const Icon(Icons.play_arrow_rounded, size: 16, color: Colors.white),
              label: Text(
                'START ${timerState.formattedSelectedDuration}',
                style: AppTheme.heading(size: 11, color: Colors.white, letterSpacing: 0.8),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.amber,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: const Size(70, 34),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: widget.isEnabled ? () => notifier.startQuickTimer() : null,
            ),
          ],
          const SizedBox(width: 4),

          // Expand / Collapse Chevron Button
          IconButton(
            icon: Icon(
              _isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
              size: 20,
              color: AppTheme.textSecondary,
            ),
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: _isExpanded ? 'Collapse' : 'Edit timer duration',
            onPressed: widget.isEnabled ? _toggleExpanded : null,
          ),
        ],
      ),
    );
  }

  /// Expanded panel containing 10m, 15m, 20m presets and custom duration stepper/picker.
  Widget _buildExpandedPanel(
    BuildContext context,
    AutoOffTimerState timerState,
    AutoOffTimerNotifier notifier,
    bool isRunning,
  ) {
    final selectedMins = timerState.selectedMinutes;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SELECT AUTO-OFF TIME',
                style: AppTheme.heading(size: 11, color: AppTheme.textMuted, letterSpacing: 1.2),
              ),
              Text(
                'Lights will auto-switch OFF',
                style: AppTheme.body(size: 11, color: AppTheme.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Quick Preset Chips (10m, 15m, 20m, 30m)
          Row(
            children: _presetMinutes.map((mins) {
              final isSelected = selectedMins == mins;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: widget.isEnabled
                        ? () {
                            notifier.setSelectedMinutes(mins);
                          }
                        : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.cyan.withValues(alpha: 0.18)
                            : AppTheme.surfaceRaised,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? AppTheme.cyan : AppTheme.border,
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$mins',
                            style: AppTheme.heading(
                              size: 15,
                              color: isSelected ? AppTheme.cyan : AppTheme.textPrimary,
                            ),
                          ),
                          Text(
                            'MIN',
                            style: AppTheme.body(
                              size: 9,
                              weight: FontWeight.w600,
                              color: isSelected ? AppTheme.cyan : AppTheme.textMuted,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),

          // Custom Stepper Adjustment Row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.surfaceRaised,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                // Decrement 5m
                _buildStepperButton(
                  label: '-5m',
                  onTap: () {
                    final next = (selectedMins - 5).clamp(1, 720);
                    notifier.setSelectedMinutes(next);
                  },
                ),
                const SizedBox(width: 4),
                // Decrement 1m
                _buildStepperButton(
                  label: '-1m',
                  onTap: () {
                    final next = (selectedMins - 1).clamp(1, 720);
                    notifier.setSelectedMinutes(next);
                  },
                ),

                // Center Display
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _showCustomTimePicker(context, selectedMins),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          AutoOffTimerState.formatMinutes(selectedMins),
                          style: AppTheme.heading(
                            size: 16,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          'Tap for exact time',
                          style: AppTheme.body(size: 9.5, color: AppTheme.cyan),
                        ),
                      ],
                    ),
                  ),
                ),

                // Increment 1m
                _buildStepperButton(
                  label: '+1m',
                  onTap: () {
                    final next = (selectedMins + 1).clamp(1, 720);
                    notifier.setSelectedMinutes(next);
                  },
                ),
                const SizedBox(width: 4),
                // Increment 5m
                _buildStepperButton(
                  label: '+5m',
                  onTap: () {
                    final next = (selectedMins + 5).clamp(1, 720);
                    notifier.setSelectedMinutes(next);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // If running: Progress indicator
          if (isRunning) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: timerState.progress,
                minHeight: 6,
                backgroundColor: AppTheme.surfaceRaised,
                valueColor: const AlwaysStoppedAnimation(AppTheme.gold),
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Bottom Action Button
          if (isRunning) ...[
            ElevatedButton.icon(
              icon: const Icon(Icons.stop_circle_outlined, size: 18, color: Colors.white),
              label: Text(
                'CANCEL RUNNING TIMER (${timerState.formattedRemaining} LEFT)',
                style: AppTheme.heading(size: 12, color: Colors.white, letterSpacing: 1.0),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.red,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: widget.isEnabled ? () => notifier.cancelTimer() : null,
            ),
          ] else ...[
            ElevatedButton.icon(
              icon: const Icon(Icons.play_circle_fill_rounded, size: 18, color: Colors.white),
              label: Text(
                'START ${AutoOffTimerState.formatMinutes(selectedMins).toUpperCase()} AUTO-OFF',
                style: AppTheme.heading(size: 12.5, color: Colors.white, letterSpacing: 1.2),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.amber,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 3,
              ),
              onPressed: widget.isEnabled ? () => notifier.startTimer(selectedMins) : null,
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 220.ms).slideY(begin: 0.05, end: 0, duration: 220.ms, curve: Curves.easeOutCubic);
  }

  Widget _buildStepperButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: widget.isEnabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.border),
        ),
        child: Text(
          label,
          style: AppTheme.mono(size: 11, weight: FontWeight.w600, color: AppTheme.textSecondary),
        ),
      ),
    );
  }
}

/// Modal dialog for selecting auto-off duration in hours and minutes.
class _DurationPickerDialog extends StatefulWidget {
  const _DurationPickerDialog({required this.initialMinutes});

  final int initialMinutes;

  @override
  State<_DurationPickerDialog> createState() => _DurationPickerDialogState();
}

class _DurationPickerDialogState extends State<_DurationPickerDialog> {
  late int _minutes;
  bool _isDirectInput = false;
  late TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _minutes = widget.initialMinutes.clamp(1, 720);
    _textController = TextEditingController(text: '$_minutes');
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _updateMinutes(int mins) {
    final clamped = mins.clamp(1, 720);
    setState(() {
      _minutes = clamped;
      _textController.text = '$clamped';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceRaised,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: const Icon(
                      Icons.timer_outlined,
                      size: 20,
                      color: AppTheme.cyan,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SELECT DURATION',
                          style: AppTheme.heading(size: 14, letterSpacing: 1.2),
                        ),
                        Text(
                          'Set auto-off timer minutes',
                          style: AppTheme.body(size: 11, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _isDirectInput ? Icons.tune_rounded : Icons.keyboard_alt_outlined,
                      color: AppTheme.cyan,
                      size: 20,
                    ),
                    tooltip: _isDirectInput ? 'Switch to wheel picker' : 'Type exact minutes',
                    onPressed: () {
                      setState(() {
                        _isDirectInput = !_isDirectInput;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Prominent Duration Banner
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceRaised,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.cyan.withValues(alpha: 0.5)),
                ),
                child: Column(
                  children: [
                    Text(
                      AutoOffTimerState.formatMinutes(_minutes),
                      style: AppTheme.heading(size: 28, color: AppTheme.cyan),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'TOTAL DURATION ($_minutes MIN)',
                      style: AppTheme.body(size: 10, color: AppTheme.textSecondary, letterSpacing: 1.0),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              if (_isDirectInput) ...[
                // Keypad direct input
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _textController,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    style: AppTheme.heading(size: 24, color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Minutes (1 - 720)',
                      labelStyle: AppTheme.body(size: 12, color: AppTheme.textMuted),
                      suffixText: 'MIN',
                      suffixStyle: AppTheme.mono(size: 14, color: AppTheme.cyan),
                      filled: true,
                      fillColor: AppTheme.surfaceRaised,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.cyan),
                      ),
                    ),
                    onChanged: (val) {
                      final parsed = int.tryParse(val);
                      if (parsed != null && parsed > 0) {
                        setState(() {
                          _minutes = parsed.clamp(1, 720);
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ] else ...[
                // Wheel Picker (CupertinoTimerPicker)
                SizedBox(
                  height: 160,
                  child: CupertinoTheme(
                    data: const CupertinoThemeData(
                      brightness: Brightness.light,
                      primaryColor: AppTheme.amber,
                      textTheme: CupertinoTextThemeData(
                        pickerTextStyle: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    child: CupertinoTimerPicker(
                      key: ValueKey(_minutes),
                      mode: CupertinoTimerPickerMode.hm,
                      initialTimerDuration: Duration(minutes: _minutes),
                      onTimerDurationChanged: (Duration newDuration) {
                        final inMins = newDuration.inMinutes;
                        setState(() {
                          _minutes = inMins == 0 ? 1 : inMins.clamp(1, 720);
                          _textController.text = '$_minutes';
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Quick preset chips
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [5, 10, 15, 20, 30, 45, 60, 90, 120].map((m) {
                  final isSelected = _minutes == m;
                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _updateMinutes(m),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.amber.withValues(alpha: 0.15) : AppTheme.surfaceRaised,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected ? AppTheme.amber : AppTheme.border,
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      child: Text(
                        '${m}m',
                        style: AppTheme.mono(
                          size: 12,
                          weight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? AppTheme.amber : AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),

              // Stepper buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildStepperChip('-15m', () => _updateMinutes(_minutes - 15)),
                  const SizedBox(width: 6),
                  _buildStepperChip('-5m', () => _updateMinutes(_minutes - 5)),
                  const SizedBox(width: 6),
                  _buildStepperChip('+5m', () => _updateMinutes(_minutes + 5)),
                  const SizedBox(width: 6),
                  _buildStepperChip('+15m', () => _updateMinutes(_minutes + 15)),
                ],
              ),
              const SizedBox(height: 20),

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'CANCEL',
                      style: AppTheme.heading(size: 12, color: AppTheme.textMuted),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.amber,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => Navigator.of(context).pop(_minutes),
                    child: Text(
                      'SET DURATION',
                      style: AppTheme.heading(size: 12, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepperChip(String label, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.surfaceRaised,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.border),
        ),
        child: Text(
          label,
          style: AppTheme.mono(size: 11, color: AppTheme.textPrimary),
        ),
      ),
    );
  }
}
