import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models.dart';
import '../../domain/providers.dart';
import '../../ui/theme.dart';

/// Modal bottom sheet to create or edit an alarm-style schedule routine for Temple Lights.
class ScheduleEditorSheet extends ConsumerStatefulWidget {
  const ScheduleEditorSheet({
    super.key,
    this.initialSchedule,
  });

  final LightSchedule? initialSchedule;

  static Future<void> show(BuildContext context, {LightSchedule? schedule}) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => ScheduleEditorSheet(initialSchedule: schedule),
    );
  }

  @override
  ConsumerState<ScheduleEditorSheet> createState() => _ScheduleEditorSheetState();
}

class _ScheduleEditorSheetState extends ConsumerState<ScheduleEditorSheet> {
  late final TextEditingController _nameController;
  late bool _hasTurnOn;
  late int _turnOnHour;
  late int _turnOnMinute;
  late bool _hasTurnOff;
  late int _turnOffHour;
  late int _turnOffMinute;
  late Set<int> _repeatDays;

  // Lighting parameters for ON trigger
  late int _targetMode;
  late int _targetBrightness;
  late Color _targetColor;

  static const List<Map<String, dynamic>> _templePalette = [
    {'name': 'Warm Amber', 'color': Color(0xFFFF9329), 'r': 255, 'g': 147, 'b': 41},
    {'name': 'Saffron Gold', 'color': Color(0xFFFFB400), 'r': 255, 'g': 180, 'b': 0},
    {'name': 'Temple Red', 'color': Color(0xFFFF1E1E), 'r': 255, 'g': 30, 'b': 30},
    {'name': 'Sacred Blue', 'color': Color(0xFF0078FF), 'r': 0, 'g': 120, 'b': 255},
    {'name': 'Divine Cyan', 'color': Color(0xFF00E5FF), 'r': 0, 'g': 229, 'b': 255},
    {'name': 'Lotus Pink', 'color': Color(0xFFFF50A0), 'r': 255, 'g': 80, 'b': 160},
    {'name': 'Holy Green', 'color': Color(0xFF00E676), 'r': 0, 'g': 230, 'b': 118},
    {'name': 'Pure White', 'color': Color(0xFFFFFFFF), 'r': 255, 'g': 255, 'b': 255},
  ];

  bool get _isEditing => widget.initialSchedule != null;

  @override
  void initState() {
    super.initState();
    final s = widget.initialSchedule;
    _nameController = TextEditingController(text: s?.name ?? 'Evening Sandhya');
    _hasTurnOn = s?.hasTurnOn ?? true;
    _turnOnHour = s?.turnOnHour ?? 18;
    _turnOnMinute = s?.turnOnMinute ?? 30;
    _hasTurnOff = s?.hasTurnOff ?? true;
    _turnOffHour = s?.turnOffHour ?? 21;
    _turnOffMinute = s?.turnOffMinute ?? 0;
    _repeatDays = s != null ? Set<int>.from(s.repeatDays) : {1, 2, 3, 4, 5, 6, 7};

    _targetMode = s?.targetMode ?? 0;
    _targetBrightness = s?.targetBrightness ?? 255;
    _targetColor = s != null
        ? Color.fromARGB(255, s.targetR, s.targetG, s.targetB)
        : const Color(0xFFFF9329);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickTime({required bool isTurnOn}) async {
    final currentHour = isTurnOn ? _turnOnHour : _turnOffHour;
    final currentMinute = isTurnOn ? _turnOnMinute : _turnOffMinute;

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: currentHour, minute: currentMinute),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.amber,
              onPrimary: Colors.white,
              surface: AppTheme.surface,
              onSurface: AppTheme.textPrimary,
            ),
            timePickerTheme: TimePickerThemeData(
              backgroundColor: AppTheme.surface,
              dialBackgroundColor: AppTheme.surfaceRaised,
              dialHandColor: AppTheme.amber,
              hourMinuteColor: AppTheme.surfaceRaised,
              hourMinuteTextColor: AppTheme.amber,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isTurnOn) {
          _turnOnHour = picked.hour;
          _turnOnMinute = picked.minute;
          _hasTurnOn = true;
        } else {
          _turnOffHour = picked.hour;
          _turnOffMinute = picked.minute;
          _hasTurnOff = true;
        }
      });
    }
  }

  void _showCustomColorDialog() {
    int r = (_targetColor.r * 255.0).round().clamp(0, 255);
    int g = (_targetColor.g * 255.0).round().clamp(0, 255);
    int b = (_targetColor.b * 255.0).round().clamp(0, 255);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            final currentColor = Color.fromARGB(255, r, g, b);
            return AlertDialog(
              backgroundColor: AppTheme.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: currentColor,
                      border: Border.all(color: AppTheme.borderBright, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: currentColor.withValues(alpha: 0.4),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('Custom RGB Picker', style: AppTheme.heading(size: 16)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildRgbSlider('Red', r, Colors.red, (val) => setDlgState(() => r = val)),
                    const SizedBox(height: 8),
                    _buildRgbSlider('Green', g, Colors.green, (val) => setDlgState(() => g = val)),
                    const SizedBox(height: 8),
                    _buildRgbSlider('Blue', b, Colors.blue, (val) => setDlgState(() => b = val)),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text('Cancel', style: AppTheme.body(size: 13, color: AppTheme.textMuted)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.amber,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    setState(() {
                      _targetColor = currentColor;
                    });
                    Navigator.of(ctx).pop();
                  },
                  child: Text('Select', style: AppTheme.heading(size: 13, color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildRgbSlider(String label, int val, Color trackColor, ValueChanged<int> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: AppTheme.heading(size: 12, color: AppTheme.textSecondary)),
            Text('$val', style: AppTheme.heading(size: 12, color: AppTheme.textPrimary)),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: trackColor,
            inactiveTrackColor: AppTheme.surfaceRaised,
            thumbColor: trackColor,
            trackHeight: 4,
          ),
          child: Slider(
            value: val.toDouble(),
            min: 0,
            max: 255,
            onChanged: (newVal) => onChanged(newVal.round()),
          ),
        ),
      ],
    );
  }

  void _save() {
    if (!_hasTurnOn && !_hasTurnOff) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please enable at least Turn ON or Turn OFF time.',
            style: AppTheme.body(size: 13, color: Colors.white),
          ),
          backgroundColor: AppTheme.red,
        ),
      );
      return;
    }

    final name = _nameController.text.trim().isEmpty ? 'Temple Routine' : _nameController.text.trim();
    final schedule = LightSchedule(
      id: widget.initialSchedule?.id ?? 'sched_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      isEnabled: widget.initialSchedule?.isEnabled ?? true,
      hasTurnOn: _hasTurnOn,
      turnOnHour: _turnOnHour,
      turnOnMinute: _turnOnMinute,
      hasTurnOff: _hasTurnOff,
      turnOffHour: _turnOffHour,
      turnOffMinute: _turnOffMinute,
      repeatDays: _repeatDays.isEmpty ? [1, 2, 3, 4, 5, 6, 7] : _repeatDays.toList(),
      targetMode: _targetMode,
      targetBrightness: _targetBrightness,
      targetR: (_targetColor.r * 255.0).round().clamp(0, 255),
      targetG: (_targetColor.g * 255.0).round().clamp(0, 255),
      targetB: (_targetColor.b * 255.0).round().clamp(0, 255),
    );

    final notifier = ref.read(schedulesProvider.notifier);
    if (_isEditing) {
      notifier.updateSchedule(schedule);
    } else {
      notifier.addSchedule(schedule);
    }

    Navigator.of(context).pop();
  }

  void _delete() {
    if (widget.initialSchedule != null) {
      ref.read(schedulesProvider.notifier).deleteSchedule(widget.initialSchedule!.id);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.90,
        minChildSize: 0.50,
        maxChildSize: 0.96,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: ListView(
              controller: scrollController,
              children: [
                // Grab handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.borderBright,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _isEditing ? 'Edit Schedule Timer' : 'New Schedule Timer',
                      style: AppTheme.heading(size: 20),
                    ),
                    if (_isEditing)
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.red),
                        tooltip: 'Delete Schedule',
                        onPressed: _delete,
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // Schedule Name Input
                Text('Routine Label', style: AppTheme.heading(size: 13, color: AppTheme.textSecondary)),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameController,
                  style: AppTheme.body(size: 14),
                  decoration: InputDecoration(
                    hintText: 'e.g. Morning Aarti, Evening Sandhya, Night Ambiance',
                    hintStyle: AppTheme.body(size: 13, color: AppTheme.textMuted),
                    filled: true,
                    fillColor: AppTheme.surfaceRaised,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.amber)),
                  ),
                ),
                const SizedBox(height: 10),

                // Quick Name Preset Chips
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: ['Morning Aarti', 'Evening Sandhya', 'Night Ambiance', 'Daily Meditation'].map((preset) {
                    return ActionChip(
                      label: Text(preset, style: AppTheme.body(size: 11, color: AppTheme.textSecondary)),
                      backgroundColor: AppTheme.surfaceRaised,
                      side: const BorderSide(color: AppTheme.border),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      onPressed: () {
                        setState(() {
                          _nameController.text = preset;
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),

                // Section 1: Turn ON Alarm Card
                _buildTimePickerCard(
                  title: 'TURN ON LIGHTS',
                  subtitle: 'Illuminates temple strip at scheduled time',
                  actionColor: AppTheme.green,
                  isEnabled: _hasTurnOn,
                  hour: _turnOnHour,
                  minute: _turnOnMinute,
                  onToggleEnabled: (val) => setState(() => _hasTurnOn = val),
                  onTapPicker: () => _pickTime(isTurnOn: true),
                ),
                const SizedBox(height: 14),

                // Section 2: Lighting Preferences (Mode, Color & Brightness)
                if (_hasTurnOn) ...[
                  _buildLightingPreferencesCard(),
                  const SizedBox(height: 14),
                ],

                // Section 3: Turn OFF Alarm Card
                _buildTimePickerCard(
                  title: 'TURN OFF LIGHTS',
                  subtitle: 'Gracefully fades out and powers off strip',
                  actionColor: AppTheme.orange,
                  isEnabled: _hasTurnOff,
                  hour: _turnOffHour,
                  minute: _turnOffMinute,
                  onToggleEnabled: (val) => setState(() => _hasTurnOff = val),
                  onTapPicker: () => _pickTime(isTurnOn: false),
                ),
                const SizedBox(height: 20),

                // Section 4: Repeat Days Selector
                Text('Repeat Days', style: AppTheme.heading(size: 13, color: AppTheme.textSecondary)),
                const SizedBox(height: 10),

                // Quick Presets Row
                Row(
                  children: [
                    _buildPresetChip('Everyday', () => setState(() => _repeatDays = {1, 2, 3, 4, 5, 6, 7})),
                    const SizedBox(width: 8),
                    _buildPresetChip('Weekdays', () => setState(() => _repeatDays = {1, 2, 3, 4, 5})),
                    const SizedBox(width: 8),
                    _buildPresetChip('Weekends', () => setState(() => _repeatDays = {6, 7})),
                  ],
                ),
                const SizedBox(height: 12),

                // Day of Week Circular Badges
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (var i = 1; i <= 7; i++)
                      _buildDayChip(i),
                  ],
                ),
                const SizedBox(height: 28),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.border),
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text('Cancel', style: AppTheme.heading(size: 14, color: AppTheme.textSecondary)),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.amber,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 3,
                        ),
                        onPressed: _save,
                        child: Text(
                          _isEditing ? 'Save Changes' : 'Create Routine',
                          style: AppTheme.heading(size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTimePickerCard({
    required String title,
    required String subtitle,
    required Color actionColor,
    required bool isEnabled,
    required int hour,
    required int minute,
    required ValueChanged<bool> onToggleEnabled,
    required VoidCallback onTapPicker,
  }) {
    final formattedTime = LightSchedule.formatTime12h(hour, minute);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isEnabled ? actionColor.withValues(alpha: 0.5) : AppTheme.border,
          width: 1.2,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: actionColor.withValues(alpha: isEnabled ? 0.2 : 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  title,
                  style: AppTheme.heading(
                    size: 11,
                    color: isEnabled ? actionColor : AppTheme.textMuted,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const Spacer(),
              Switch(
                value: isEnabled,
                activeThumbColor: actionColor,
                onChanged: onToggleEnabled,
              ),
            ],
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: isEnabled ? onTapPicker : () => onToggleEnabled(true),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isEnabled ? actionColor.withValues(alpha: 0.3) : AppTheme.border,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formattedTime,
                        style: AppTheme.heading(
                          size: 28,
                          color: isEnabled ? actionColor : AppTheme.textMuted,
                          letterSpacing: 2.0,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: AppTheme.body(size: 11, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                  Icon(
                    Icons.access_time_filled_rounded,
                    color: isEnabled ? actionColor : AppTheme.textMuted,
                    size: 28,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Lighting Mode, Color, and Brightness Card
  Widget _buildLightingPreferencesCard() {
    final currentPercent = ((_targetBrightness / 255.0) * 100).round().clamp(1, 100);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.amber.withValues(alpha: 0.4), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: AppTheme.amber.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'ON-TRIGGER LIGHTING',
                  style: AppTheme.heading(
                    size: 11,
                    color: AppTheme.amber,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const Spacer(),
              Icon(Icons.tune_rounded, size: 18, color: AppTheme.amber),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Select the mode, color, and brightness to activate at turn ON',
            style: AppTheme.body(size: 11.5, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 14),

          // 1. Mode Selection Grid (4 Modes)
          Text('LIGHTING MODE', style: AppTheme.heading(size: 11, color: AppTheme.textMuted, letterSpacing: 1.0)),
          const SizedBox(height: 8),
          _buildModeSelector(),
          const SizedBox(height: 16),

          // 2. Custom Color Swatches & Picker (Visible if Mode 3 selected)
          if (_targetMode == 3) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('SELECT COLOR', style: AppTheme.heading(size: 11, color: AppTheme.textMuted, letterSpacing: 1.0)),
                InkWell(
                  onTap: _showCustomColorDialog,
                  child: Row(
                    children: [
                      Icon(Icons.colorize_rounded, size: 14, color: AppTheme.amber),
                      const SizedBox(width: 4),
                      Text('RGB Sliders', style: AppTheme.heading(size: 11, color: AppTheme.amber)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildColorPalette(),
            const SizedBox(height: 16),
          ],

          // 3. Brightness Slider & Presets
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('ACTIVATION BRIGHTNESS', style: AppTheme.heading(size: 11, color: AppTheme.textMuted, letterSpacing: 1.0)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceRaised,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Text(
                  '$currentPercent%',
                  style: AppTheme.heading(size: 12, color: AppTheme.amber),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.brightness_low_rounded, size: 18, color: AppTheme.textMuted),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppTheme.amber,
                    inactiveTrackColor: AppTheme.surfaceRaised,
                    thumbColor: AppTheme.amber,
                    trackHeight: 5,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                  ),
                  child: Slider(
                    value: _targetBrightness.toDouble().clamp(3.0, 255.0),
                    min: 3,
                    max: 255,
                    onChanged: (val) {
                      setState(() {
                        _targetBrightness = val.round();
                      });
                    },
                  ),
                ),
              ),
              const Icon(Icons.brightness_high_rounded, size: 20, color: AppTheme.amber),
            ],
          ),
          const SizedBox(height: 4),
          // Quick Brightness Presets (25%, 50%, 75%, 100%)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [25, 50, 75, 100].map((pct) {
              final val = ((pct / 100.0) * 255).round();
              final isCurrent = (_targetBrightness - val).abs() < 12;
              return GestureDetector(
                onTap: () => setState(() => _targetBrightness = val),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isCurrent ? AppTheme.amber : AppTheme.surfaceRaised,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isCurrent ? AppTheme.amber : AppTheme.borderBright),
                  ),
                  child: Text(
                    '$pct%',
                    style: AppTheme.heading(
                      size: 10.5,
                      color: isCurrent ? Colors.white : AppTheme.textSecondary,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    final modes = [
      {'mode': 0, 'title': 'Warm White', 'sub': 'All LEDs (Full)', 'color': const Color(0xFFFF9329)},
      {'mode': 1, 'title': 'Center Warm', 'sub': 'Middle 1.5m', 'color': const Color(0xFFD97706)},
      {'mode': 2, 'title': 'Pure White', 'sub': 'All LEDs (Pure)', 'color': Colors.white},
      {'mode': 3, 'title': 'Custom Color', 'sub': 'Color Palette', 'color': _targetColor},
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 4,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.2,
      ),
      itemBuilder: (context, index) {
        final item = modes[index];
        final m = item['mode'] as int;
        final isSelected = _targetMode == m;
        final color = item['color'] as Color;

        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() {
              _targetMode = m;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.surfaceRaised : AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? AppTheme.amber : AppTheme.border,
                width: isSelected ? 2.0 : 1.0,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: AppTheme.amber.withValues(alpha: 0.15),
                        blurRadius: 6,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    border: Border.all(
                      color: (color == Colors.white) ? AppTheme.borderBright : Colors.transparent,
                      width: 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.5),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item['title'] as String,
                        style: AppTheme.heading(
                          size: 11.5,
                          color: isSelected ? AppTheme.amber : AppTheme.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        item['sub'] as String,
                        style: AppTheme.body(size: 9.5, color: AppTheme.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildColorPalette() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _templePalette.map((colorItem) {
        final color = colorItem['color'] as Color;
        final r = colorItem['r'] as int;
        final g = colorItem['g'] as int;
        final b = colorItem['b'] as int;
        final curR = (_targetColor.r * 255.0).round();
        final curG = (_targetColor.g * 255.0).round();
        final curB = (_targetColor.b * 255.0).round();
        final isSelected = curR == r && curG == g && curB == b;

        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            setState(() {
              _targetColor = color;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.surfaceRaised,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? color : AppTheme.border,
                width: isSelected ? 2.0 : 1.0,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.4),
                        blurRadius: 6,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    border: Border.all(
                      color: color == Colors.white ? AppTheme.borderBright : Colors.transparent,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  colorItem['name'] as String,
                  style: AppTheme.heading(
                    size: 10.5,
                    color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPresetChip(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.surfaceRaised,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.borderBright),
        ),
        child: Text(
          label,
          style: AppTheme.heading(size: 11, color: AppTheme.amber),
        ),
      ),
    );
  }

  Widget _buildDayChip(int day) {
    const dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final isSelected = _repeatDays.contains(day);

    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            if (_repeatDays.length > 1) {
              _repeatDays.remove(day);
            }
          } else {
            _repeatDays.add(day);
          }
        });
      },
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected ? AppTheme.amber : AppTheme.surfaceRaised,
          border: Border.all(
            color: isSelected ? AppTheme.amber : AppTheme.border,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.amber.withValues(alpha: 0.25),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          dayLabels[day - 1],
          style: AppTheme.heading(
            size: 12,
            color: isSelected ? Colors.white : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}
