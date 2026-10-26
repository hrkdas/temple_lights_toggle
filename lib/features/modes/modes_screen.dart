import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/haptics.dart';
import '../../domain/models.dart';
import '../../domain/providers.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/strip_visualizer_widget.dart';
import '../../ui/widgets/live_animation_preview_widget.dart';

/// Dynamic Presets & Multi-Segment Studio Screen.
/// Supports arbitrary LED range selection (e.g. 1-6, 100-105), living auras,
/// wall-switch cycle toggles, and >3 customizable presets saved to ESP32 flash memory.
class ModesScreen extends ConsumerStatefulWidget {
  const ModesScreen({super.key});

  @override
  ConsumerState<ModesScreen> createState() => _ModesScreenState();
}

class _ModesScreenState extends ConsumerState<ModesScreen> {
  int _selectedPresetIndex = 0;
  final Map<int, LightPreset> _editPresets = {};

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

  static const List<String> _segmentEffects = [
    'Solid Static',
    'Gentle Breathe',
    'Diya Flutter',
    'Starlight Twinkle',
    'Amber Embers',
    'Aurora Wave',
    'Divine Rainbow',
  ];

  LightPreset _getPreset(int index, List<LightPreset> sourceList) {
    if (_editPresets.containsKey(index)) {
      return _editPresets[index]!;
    }
    final match = sourceList.where((p) => p.index == index).firstOrNull;
    if (match != null) return match;
    final defaults = LightPreset.defaultPresets();
    if (index < defaults.length) return defaults[index];
    return defaults.first;
  }

  void _updatePreset(LightPreset updated) {
    setState(() {
      _editPresets[updated.index] = updated;
    });
  }

  void _showColorPickerForSegment(int segIdx, LedSegment segment, LightPreset preset) {
    int r = segment.r;
    int g = segment.g;
    int b = segment.b;

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
                  Text('Segment ${segIdx + 1} Color', style: AppTheme.heading(size: 16)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Quick Palette Chips
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _templePalette.map((p) {
                        final pr = p['r'] as int;
                        final pg = p['g'] as int;
                        final pb = p['b'] as int;
                        final isSel = r == pr && g == pg && b == pb;
                        return InkWell(
                          onTap: () => setDlgState(() {
                            r = pr;
                            g = pg;
                            b = pb;
                          }),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: p['color'] as Color,
                              border: Border.all(
                                color: isSel ? Colors.white : AppTheme.border,
                                width: isSel ? 2.5 : 1.0,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
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
                    final updatedSegs = List<LedSegment>.from(preset.segments);
                    if (segIdx < updatedSegs.length) {
                      updatedSegs[segIdx] = updatedSegs[segIdx].copyWith(r: r, g: g, b: b);
                      _updatePreset(preset.copyWith(segments: updatedSegs));
                    }
                    Navigator.of(ctx).pop();
                  },
                  child: Text('Apply Color', style: AppTheme.heading(size: 13, color: Colors.white)),
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

  void _showRenameDialog(LightPreset current) {
    final controller = TextEditingController(text: current.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Rename Preset ${current.index + 1}', style: AppTheme.heading(size: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: AppTheme.body(size: 14),
          decoration: InputDecoration(
            hintText: 'e.g. Sanctum Sunrise, Diwali Embers',
            filled: true,
            fillColor: AppTheme.surfaceRaised,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.border)),
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
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                _updatePreset(current.copyWith(name: newName));
              }
              Navigator.of(ctx).pop();
            },
            child: Text('Save Name', style: AppTheme.heading(size: 13, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showAddPresetDialog(int nextIndex, int totalLeds) {
    final controller = TextEditingController(text: 'Mode ${nextIndex + 1}');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.add_circle_outline_rounded, color: AppTheme.amber, size: 22),
            const SizedBox(width: 8),
            Text('Add Custom Preset', style: AppTheme.heading(size: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Create a new preset beyond the default 3 modes. You can configure individual LED segments and effects.',
              style: AppTheme.body(size: 12.5, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              style: AppTheme.body(size: 14),
              decoration: InputDecoration(
                labelText: 'Preset Name',
                hintText: 'e.g. Dual Altar Accent',
                filled: true,
                fillColor: AppTheme.surfaceRaised,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.border)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: AppTheme.body(size: 13, color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.amber,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final name = controller.text.trim().isEmpty ? 'Mode ${nextIndex + 1}' : controller.text.trim();
              Navigator.of(ctx).pop();
              final newPreset = LightPreset(
                index: nextIndex,
                name: name,
                transitionStyle: 2, // Uniform Fade
                ambientStyle: 1,    // Breathe
                brightness: 200,
                cycleEnabled: true,
                segments: [
                  LedSegment(start: 0, count: (totalLeds / 2).round(), r: 255, g: 147, b: 41, effect: 1),
                  LedSegment(start: (totalLeds / 2).round(), count: (totalLeds / 2).round(), r: 0, g: 229, b: 255, effect: 2),
                ],
              );
              await ref.read(presetsProvider.notifier).addPreset(newPreset);
              setState(() {
                _selectedPresetIndex = nextIndex;
              });
            },
            child: Text('Create Preset', style: AppTheme.heading(size: 13, color: Colors.black)),
          ),
        ],
      ),
    );
  }

  Future<void> _savePresetToDevice(LightPreset preset, int totalLeds) async {
    await AppHaptics.medium();
    await ref.read(presetsProvider.notifier).savePreset(preset);

    // Sync with defaultModesProvider if it's one of the first 3 modes (100% backward compatibility)
    if (preset.index < 3) {
      final firstSeg = preset.segments.isNotEmpty ? preset.segments.first : const LedSegment(start: 0, count: 150);
      final legacyConfig = DefaultModeConfig(
        index: preset.index,
        name: preset.name,
        r: firstSeg.r,
        g: firstSeg.g,
        b: firstSeg.b,
        style: (preset.segments.isNotEmpty && preset.segments.first.count < totalLeds) ? 1 : 0,
        brightness: preset.brightness,
      );
      await ref.read(defaultModesProvider.notifier).saveMode(legacyConfig);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Preset ${preset.index + 1} ("${preset.name}") saved to ESP32 flash!',
          style: AppTheme.body(size: 13, color: Colors.white),
        ),
        backgroundColor: AppTheme.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _previewPreset(LightPreset preset) async {
    await AppHaptics.light();
    final ctrl = ref.read(lightControlProvider.notifier);
    if (preset.segments.isNotEmpty && preset.index >= 3) {
      await ctrl.setSegments(preset.segments);
    } else {
      await ctrl.setPreset(preset.index);
    }
    await ctrl.previewAnimation(
      transitionStyle: preset.transitionStyle,
      ambientStyle: preset.ambientStyle,
      depth: preset.ambientDepth,
    );
  }

  @override
  Widget build(BuildContext context) {
    final presets = ref.watch(presetsProvider);
    final light = ref.watch(lightControlProvider);
    final totalLeds = light.ledCount > 0 ? light.ledCount : 150;

    // Ensure valid selected index
    if (!presets.any((p) => p.index == _selectedPresetIndex) && presets.isNotEmpty) {
      _selectedPresetIndex = presets.first.index;
    }
    final activePreset = _getPreset(_selectedPresetIndex, presets);
    final isCurrentActiveOnDevice = light.isOn && light.activePreset == activePreset.index;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Header Banner with Next Mode Cycle & Reset Action
              _buildHeaderBanner(presets),
              const SizedBox(height: 12),

              // 2. Horizontal Presets Chip Selector Bar (+ Add Preset button)
              _buildPresetsSelectorBar(presets, totalLeds),
              const SizedBox(height: 14),

              // 3. Active Preset Studio Card
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: _buildPresetStudioCard(activePreset, isCurrentActiveOnDevice, totalLeds)
                      .animate()
                      .fadeIn(duration: 200.ms),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderBanner(List<LightPreset> presets) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.amber.withValues(alpha: 0.35), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: AppTheme.amber.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: AppTheme.amber, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PRESETS & MULTI-SEGMENT STUDIO',
                  style: AppTheme.heading(size: 12, color: AppTheme.amber, letterSpacing: 1.1),
                ),
                const SizedBox(height: 2),
                Text(
                  'Configure ranges (e.g. 1-6, 100-105) & living auras',
                  style: AppTheme.body(size: 11, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          // Next Mode Cycle Button
          ElevatedButton.icon(
            icon: const Icon(Icons.rotate_right_rounded, size: 16, color: Colors.white),
            label: Text('Next Mode', style: AppTheme.heading(size: 11, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.amber,
              foregroundColor: Colors.white,
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            onPressed: () async {
              await AppHaptics.selection();
              await ref.read(defaultModesProvider.notifier).cycleNextMode();
            },
          ),
          // Reset Menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: AppTheme.textMuted, size: 20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (val) {
              if (val == 'reset') {
                _confirmResetDefaults();
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'reset',
                child: Row(
                  children: [
                    const Icon(Icons.restore_rounded, color: AppTheme.red, size: 18),
                    const SizedBox(width: 8),
                    Text('Reset Defaults', style: AppTheme.body(size: 13, color: AppTheme.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPresetsSelectorBar(List<LightPreset> presets, int totalLeds) {
    final nextIdx = presets.isEmpty ? 0 : (presets.map((p) => p.index).reduce((a, b) => a > b ? a : b) + 1);

    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          ...presets.map((p) {
            final isSelected = p.index == _selectedPresetIndex;
            final firstColor = p.segments.isNotEmpty
                ? Color.fromARGB(255, p.segments.first.r, p.segments.first.g, p.segments.first.b)
                : AppTheme.amber;

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  AppHaptics.selection();
                  setState(() => _selectedPresetIndex = p.index);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.amber.withValues(alpha: 0.18) : AppTheme.surfaceRaised,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? AppTheme.amber : AppTheme.border,
                      width: isSelected ? 1.8 : 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: firstColor,
                          border: Border.all(color: Colors.white, width: 1),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        p.name,
                        style: AppTheme.heading(
                          size: 11.5,
                          color: isSelected ? AppTheme.amber : AppTheme.textPrimary,
                        ),
                      ),
                      if (p.cycleEnabled) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.sync_rounded, size: 12, color: AppTheme.textMuted),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),
          // Add Preset Button
          if (presets.length < 16)
            ElevatedButton.icon(
              icon: const Icon(Icons.add_rounded, size: 16, color: Colors.black),
              label: Text('New Mode', style: AppTheme.heading(size: 11.5, color: Colors.black)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.amber,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => _showAddPresetDialog(nextIdx, totalLeds),
            ),
        ],
      ),
    );
  }

  Widget _buildPresetStudioCard(
    LightPreset preset,
    bool isCurrentActive,
    int totalLeds,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isCurrentActive ? AppTheme.amber : AppTheme.border,
          width: isCurrentActive ? 2.0 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isCurrentActive
                ? AppTheme.amber.withValues(alpha: 0.12)
                : const Color(0xFF3B2E1E).withValues(alpha: 0.04),
            blurRadius: isCurrentActive ? 16 : 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Header, Name, Active Pill, Delete (if index >= 3)
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'PRESET ${preset.index + 1}',
                  style: AppTheme.heading(size: 11, color: AppTheme.amber, letterSpacing: 1.1),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () => _showRenameDialog(preset),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          preset.name,
                          style: AppTheme.heading(size: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.edit_rounded, size: 14, color: AppTheme.textMuted),
                    ],
                  ),
                ),
              ),
              if (isCurrentActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.green.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: AppTheme.green),
                      ),
                      const SizedBox(width: 4),
                      Text('ACTIVE NOW', style: AppTheme.heading(size: 9.5, color: AppTheme.green)),
                    ],
                  ),
                ),
              if (preset.index >= 3) ...[
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.red, size: 20),
                  tooltip: 'Delete Preset',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () async {
                    await ref.read(presetsProvider.notifier).deletePreset(preset.index);
                    setState(() => _selectedPresetIndex = 0);
                  },
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),

          // Wall Switch Cycle Checkbox
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surfaceRaised,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.power_settings_new_rounded, size: 18, color: AppTheme.amber),
                    const SizedBox(width: 8),
                    Text(
                      'Include in Physical Wall Switch Cycle',
                      style: AppTheme.body(size: 12, color: AppTheme.textPrimary),
                    ),
                  ],
                ),
                Switch(
                  value: preset.cycleEnabled,
                  activeThumbColor: AppTheme.amber,
                  onChanged: (val) {
                    _updatePreset(preset.copyWith(cycleEnabled: val));
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Interactive Multi-Segment LED Strip Visualizer
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('LED STRIP SEGMENT RANGES', style: AppTheme.heading(size: 11, color: AppTheme.textMuted, letterSpacing: 1.1)),
              Text('${preset.segments.length} segment(s) • $totalLeds LEDs total', style: AppTheme.mono(size: 10.5, color: AppTheme.amber)),
            ],
          ),
          const SizedBox(height: 8),

          StripVisualizerWidget(
            totalLeds: totalLeds,
            segments: preset.segments,
            onSegmentsChanged: (newSegs) {
              _updatePreset(preset.copyWith(segments: newSegs));
            },
          ),
          const SizedBox(height: 14),

          // Segments Customization Cards List
          ...preset.segments.asMap().entries.map((entry) {
            final segIdx = entry.key;
            final seg = entry.value;
            return _buildSegmentCard(segIdx, seg, preset, totalLeds);
          }),
          const SizedBox(height: 8),

          // Add Segment Button
          if (preset.segments.length < 8)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.add_circle_outline_rounded, size: 16, color: AppTheme.amber),
                label: Text('+ Add New LED Range Segment', style: AppTheme.heading(size: 12, color: AppTheme.amber)),
                onPressed: () {
                  final lastEnd = preset.segments.isEmpty ? 0 : preset.segments.last.end;
                  final newStart = (lastEnd + 1).clamp(0, totalLeds - 1);
                  final newCount = (totalLeds - newStart).clamp(1, 20);
                  final newSeg = LedSegment(
                    start: newStart,
                    count: newCount,
                    r: 255,
                    g: 180,
                    b: 0,
                    effect: 1,
                  );
                  _updatePreset(preset.copyWith(segments: [...preset.segments, newSeg]));
                },
              ),
            ),
          const SizedBox(height: 14),

          // Live Interactive Animation Preview & Audition for Preset
          LiveAnimationPreviewWidget(
            transitionStyle: preset.transitionStyle,
            ambientStyle: preset.ambientStyle,
            ambientDepth: preset.ambientDepth,
            r: preset.r,
            g: preset.g,
            b: preset.b,
            brightness: preset.brightness,
            onAudition: () => _previewPreset(preset),
          ),

          const SizedBox(height: 14),

          // Devotional Transition Style & Living Aura Selectors
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TRANSITION STYLE', style: AppTheme.heading(size: 10.5, color: AppTheme.textMuted, letterSpacing: 1.0)),
                    const SizedBox(height: 6),
                    _buildDropdown(
                      value: preset.transitionStyle.clamp(0, LightState.transitionStyleNames.length - 1),
                      items: LightState.transitionStyleNames,
                      onChanged: (val) {
                        if (val != null) _updatePreset(preset.copyWith(transitionStyle: val));
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('LIVING AURA SHADER', style: AppTheme.heading(size: 10.5, color: AppTheme.textMuted, letterSpacing: 1.0)),
                    const SizedBox(height: 6),
                    _buildDropdown(
                      value: preset.ambientStyle.clamp(0, LightState.ambientStyleNames.length - 1),
                      items: LightState.ambientStyleNames,
                      onChanged: (val) {
                        if (val != null) _updatePreset(preset.copyWith(ambientStyle: val));
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Default Brightness Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('DEFAULT BRIGHTNESS', style: AppTheme.heading(size: 10.5, color: AppTheme.textMuted, letterSpacing: 1.0)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceRaised,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Text(
                  '${((preset.brightness / 255.0) * 100).round()}%',
                  style: AppTheme.heading(size: 11.5, color: AppTheme.amber),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppTheme.amber,
              inactiveTrackColor: AppTheme.surfaceRaised,
              thumbColor: AppTheme.amber,
              trackHeight: 4,
            ),
            child: Slider(
              value: preset.brightness.toDouble().clamp(3.0, 255.0),
              min: 3,
              max: 255,
              onChanged: (val) {
                _updatePreset(preset.copyWith(brightness: val.round()));
              },
            ),
          ),
          const SizedBox(height: 12),

          // Bottom Action Buttons (Preview on Lights & Save to ESP32 Flash)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.play_arrow_rounded, size: 16),
                  label: Text('Preview', style: AppTheme.heading(size: 12)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.border),
                    foregroundColor: AppTheme.textPrimary,
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _previewPreset(preset),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.save_rounded, size: 16, color: Colors.white),
                  label: Text('Save to ESP32', style: AppTheme.heading(size: 12, color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.amber,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 2,
                  ),
                  onPressed: () => _savePresetToDevice(preset, totalLeds),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentCard(int segIdx, LedSegment seg, LightPreset preset, int totalLeds) {
    final segColor = Color.fromARGB(255, seg.r, seg.g, seg.b);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Segment color circle
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _showColorPickerForSegment(segIdx, seg, preset),
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: segColor,
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: segColor.withValues(alpha: 0.5),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Segment ${segIdx + 1}: LEDs ${seg.start + 1}–${seg.end + 1} (${seg.count} LEDs)',
                      style: AppTheme.heading(size: 12),
                    ),
                    Text(
                      'RGB(${seg.r}, ${seg.g}, ${seg.b}) • ${_segmentEffects[seg.effect.clamp(0, _segmentEffects.length - 1)]}',
                      style: AppTheme.mono(size: 10.5, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              // Effect Selector Dropdown
              DropdownButton<int>(
                value: seg.effect.clamp(0, _segmentEffects.length - 1),
                dropdownColor: AppTheme.surface,
                underline: const SizedBox(),
                icon: const Icon(Icons.arrow_drop_down, color: AppTheme.amber, size: 18),
                items: _segmentEffects.asMap().entries.map((e) {
                  return DropdownMenuItem<int>(
                    value: e.key,
                    child: Text(e.value, style: AppTheme.body(size: 11)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    final updatedSegs = List<LedSegment>.from(preset.segments);
                    updatedSegs[segIdx] = seg.copyWith(effect: val);
                    _updatePreset(preset.copyWith(segments: updatedSegs));
                  }
                },
              ),
              if (preset.segments.length > 1) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16, color: AppTheme.textMuted),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: () {
                    final updatedSegs = List<LedSegment>.from(preset.segments);
                    updatedSegs.removeAt(segIdx);
                    _updatePreset(preset.copyWith(segments: updatedSegs));
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required int value,
    required List<String> items,
    required ValueChanged<int?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.surfaceRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          isExpanded: true,
          value: value,
          dropdownColor: AppTheme.surface,
          items: items.asMap().entries.map((e) {
            return DropdownMenuItem<int>(
              value: e.key,
              child: Text(
                e.value,
                style: AppTheme.body(size: 12),
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  void _confirmResetDefaults() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Reset to Factory Defaults?', style: AppTheme.heading(size: 16)),
        content: Text(
          'This will restore Mode 1 (Warm Sanctuary), Mode 2 (Center Focus 1.5m), and Mode 3 (Pure White) in the ESP32 memory and reset custom presets.',
          style: AppTheme.body(size: 13, color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: AppTheme.body(size: 13, color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              setState(() {
                _editPresets.clear();
                _selectedPresetIndex = 0;
              });
              await ref.read(presetsProvider.notifier).resetToDefaults();
              await ref.read(defaultModesProvider.notifier).resetToDefaults();
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: Text('Reset Defaults', style: AppTheme.heading(size: 13, color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
