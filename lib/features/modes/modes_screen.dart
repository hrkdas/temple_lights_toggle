import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/haptics.dart';
import '../../domain/models.dart';
import '../../domain/providers.dart';
import '../../ui/theme.dart';

/// Dedicated screen to view, customize, test, and save the 3 default boot modes to ESP32 flash memory.
class ModesScreen extends ConsumerStatefulWidget {
  const ModesScreen({super.key});

  @override
  ConsumerState<ModesScreen> createState() => _ModesScreenState();
}

class _ModesScreenState extends ConsumerState<ModesScreen> {
  // Local edit copies for each of the 3 modes
  final Map<int, DefaultModeConfig> _editConfigs = {};

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

  DefaultModeConfig _getConfig(int index, List<DefaultModeConfig> sourceList) {
    if (_editConfigs.containsKey(index)) {
      return _editConfigs[index]!;
    }
    if (index < sourceList.length) {
      return sourceList[index];
    }
    return DefaultModeConfig.factoryDefaults[index];
  }

  void _updateConfig(DefaultModeConfig updated) {
    setState(() {
      _editConfigs[updated.index] = updated;
    });
  }

  void _showCustomColorDialog(int index, DefaultModeConfig current) {
    int r = current.r;
    int g = current.g;
    int b = current.b;

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
                  Text('Custom RGB for Mode ${index + 1}', style: AppTheme.heading(size: 16)),
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
                    _updateConfig(current.copyWith(r: r, g: g, b: b));
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

  void _showRenameDialog(DefaultModeConfig current) {
    final controller = TextEditingController(text: current.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Rename Mode ${current.index + 1}', style: AppTheme.heading(size: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: AppTheme.body(size: 14),
          decoration: InputDecoration(
            hintText: 'e.g. Evening Sandhya, Sanctum Focus',
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
                _updateConfig(current.copyWith(name: newName));
              }
              Navigator.of(ctx).pop();
            },
            child: Text('Save Name', style: AppTheme.heading(size: 13, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _saveModeToDevice(DefaultModeConfig config) async {
    await AppHaptics.medium();
    await ref.read(defaultModesProvider.notifier).saveMode(config);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Mode ${config.index + 1} ("${config.name}") saved to ESP32 flash!',
          style: AppTheme.body(size: 13, color: Colors.white),
        ),
        backgroundColor: AppTheme.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final modes = ref.watch(defaultModesProvider);
    final light = ref.watch(lightControlProvider);
    final notifier = ref.read(defaultModesProvider.notifier);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Header Banner with Cycle Test & Reset Action
              _buildHeaderBanner(notifier, light.mode),
              const SizedBox(height: 14),

              // 2. 3 Mode Cards List
              Expanded(
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: 3,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (context, index) {
                    final config = _getConfig(index, modes);
                    final isCurrentActive = light.isOn && light.mode == index;
                    return _buildModeCard(config, isCurrentActive, notifier)
                        .animate()
                        .fadeIn(duration: 220.ms, delay: (index * 80).ms)
                        .slideY(begin: 0.08, end: 0, duration: 220.ms);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderBanner(DefaultModesNotifier notifier, int activeMode) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.auto_awesome_rounded, color: AppTheme.amber, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '3 BOOT CYCLE MODES',
                      style: AppTheme.heading(size: 13, color: AppTheme.amber, letterSpacing: 1.2),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Cycles 1 → 2 → 3 → 1 on power toggle',
                      style: AppTheme.body(size: 11.5, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              // Cycle Next Mode Button
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
                  await notifier.cycleNextMode();
                },
              ),
              // Reset Menu
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: AppTheme.textMuted, size: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (val) {
                  if (val == 'reset') {
                    _confirmResetDefaults(notifier);
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
        ],
      ),
    );
  }

  void _confirmResetDefaults(DefaultModesNotifier notifier) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Reset to Factory Defaults?', style: AppTheme.heading(size: 16)),
        content: Text(
          'This will restore Mode 1 (Warm White All), Mode 2 (Center Warm 1.5m), and Mode 3 (Pure White All) in the ESP32 memory.',
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
            onPressed: () {
              setState(() {
                _editConfigs.clear();
              });
              notifier.resetToDefaults();
              Navigator.of(ctx).pop();
            },
            child: Text('Reset Defaults', style: AppTheme.heading(size: 13, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildModeCard(
    DefaultModeConfig config,
    bool isCurrentActive,
    DefaultModesNotifier notifier,
  ) {
    final modeColor = Color.fromARGB(255, config.r, config.g, config.b);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isCurrentActive ? AppTheme.amber : AppTheme.border,
          width: isCurrentActive ? 2.0 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isCurrentActive
                ? AppTheme.amber.withValues(alpha: 0.12)
                : const Color(0xFF3B2E1E).withValues(alpha: 0.04),
            blurRadius: isCurrentActive ? 14 : 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Mode Header, Name, Active Pill
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'MODE ${config.index + 1}',
                  style: AppTheme.heading(
                    size: 11,
                    color: AppTheme.amber,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () => _showRenameDialog(config),
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          config.name,
                          style: AppTheme.heading(size: 15),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
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
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.green,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'ACTIVE NOW',
                        style: AppTheme.heading(size: 9.5, color: AppTheme.green, letterSpacing: 1.0),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Row 2: Simulated Mini LED Strip Visualizer
          _buildStripVisualizer(config, modeColor),
          const SizedBox(height: 14),

          // Row 3: Color Palette & Custom Picker
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('COLOR PALETTE', style: AppTheme.heading(size: 10.5, color: AppTheme.textMuted, letterSpacing: 1.0)),
              InkWell(
                onTap: () => _showCustomColorDialog(config.index, config),
                child: Row(
                  children: [
                    Icon(Icons.colorize_rounded, size: 13, color: AppTheme.amber),
                    const SizedBox(width: 4),
                    Text('Custom RGB', style: AppTheme.heading(size: 10.5, color: AppTheme.amber)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _buildColorChips(config),
          const SizedBox(height: 14),

          // Row 4: Coverage / Style Toggle (Full Strip vs Center 1.5m)
          Text('ZONE COVERAGE', style: AppTheme.heading(size: 10.5, color: AppTheme.textMuted, letterSpacing: 1.0)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _buildStyleToggleOption(
                  label: 'Full Strip (2.5m)',
                  isSelected: config.isFullStrip,
                  onTap: () => _updateConfig(config.copyWith(style: 0)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildStyleToggleOption(
                  label: 'Center Focus (1.5m)',
                  isSelected: config.isCenterFocus,
                  onTap: () => _updateConfig(config.copyWith(style: 1)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Row 5: Default Brightness Slider
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
                  '${config.brightnessPercent}%',
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
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: config.brightness.toDouble().clamp(3.0, 255.0),
              min: 3,
              max: 255,
              onChanged: (val) {
                _updateConfig(config.copyWith(brightness: val.round()));
              },
            ),
          ),
          const SizedBox(height: 10),

          // Row 6: Bottom Action Buttons (Preview on Lights & Save to ESP32)
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.play_arrow_rounded, size: 16),
                  label: Text('Preview', style: AppTheme.heading(size: 12)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.border),
                    foregroundColor: AppTheme.textPrimary,
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    await AppHaptics.light();
                    // Save and immediately activate
                    await notifier.saveMode(config);
                    await notifier.activateMode(config.index);
                  },
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
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 2,
                  ),
                  onPressed: () => _saveModeToDevice(config),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStripVisualizer(DefaultModeConfig config, Color modeColor) {
    const totalSegments = 20;
    const centerStart = 4;
    const centerEnd = 15;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1917), // Deep obsidian background
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(totalSegments, (i) {
              final isIlluminated = config.isFullStrip || (i >= centerStart && i <= centerEnd);
              final segColor = isIlluminated ? modeColor : const Color(0xFF2E2B27);

              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1.2),
                  height: 10,
                  decoration: BoxDecoration(
                    color: segColor,
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: isIlluminated
                        ? [
                            BoxShadow(
                              color: modeColor.withValues(alpha: 0.6),
                              blurRadius: 4,
                            ),
                          ]
                        : null,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                config.styleLabel,
                style: AppTheme.body(size: 10.5, color: Colors.white70),
              ),
              Text(
                '${config.brightnessPercent}% • RGB(${config.r},${config.g},${config.b})',
                style: AppTheme.body(size: 10.5, color: AppTheme.amber),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildColorChips(DefaultModeConfig config) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: _templePalette.map((item) {
        final r = item['r'] as int;
        final g = item['g'] as int;
        final b = item['b'] as int;
        final color = item['color'] as Color;
        final isSelected = config.r == r && config.g == g && config.b == b;

        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            _updateConfig(config.copyWith(r: r, g: g, b: b));
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.surfaceRaised,
              borderRadius: BorderRadius.circular(8),
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
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    border: Border.all(
                      color: color == Colors.white ? AppTheme.borderBright : Colors.transparent,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  item['name'] as String,
                  style: AppTheme.heading(
                    size: 10,
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

  Widget _buildStyleToggleOption({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.surfaceRaised : AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppTheme.amber : AppTheme.border,
            width: isSelected ? 1.8 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: AppTheme.heading(
            size: 11,
            color: isSelected ? AppTheme.amber : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}
