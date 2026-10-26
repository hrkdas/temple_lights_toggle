import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/haptics.dart';
import '../../domain/models.dart';
import '../../domain/providers.dart';
import '../theme.dart';
import 'auto_off_timer_widget.dart';
import 'kelvin_warmth_slider.dart';
import 'strip_visualizer_widget.dart';

/// Modal bottom sheet implementing Apple Home style deep control drawer.
/// Backed by frosted backdrop blur, fluid spring curves, and comprehensive lighting controls.
class DeepControlSheet extends ConsumerStatefulWidget {
  const DeepControlSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (ctx) => const DeepControlSheet(),
    );
  }

  @override
  ConsumerState<DeepControlSheet> createState() => _DeepControlSheetState();
}

class _DeepControlSheetState extends ConsumerState<DeepControlSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final light = ref.watch(lightControlProvider);
    final ctrl = ref.read(lightControlProvider.notifier);
    final defaultModes = ref.watch(defaultModesProvider);
    final presets = ref.watch(presetsProvider);
    final activeDevice = ref.watch(activeDeviceProvider);
    final rooms = ref.watch(roomsProvider);

    final roomName = activeDevice != null
        ? (rooms.where((r) => r.id == activeDevice.effectiveRoomId).firstOrNull?.name ?? 'Puja Mandir')
        : 'Puja Mandir';

    final deviceName = activeDevice?.displayName ?? 'Temple Lights';
    final currentColor = Color.fromARGB(255, light.r, light.g, light.b);
    final pct = ((light.brightness / 255.0) * 100).round();

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1A16).withValues(alpha: 0.92),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: AppTheme.borderBright.withValues(alpha: 0.4)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Grab Handle
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4.5,
                decoration: BoxDecoration(
                  color: AppTheme.textMuted.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),

              // 2. Header: Title, Room Badge & Power Button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          deviceName,
                          style: AppTheme.heading(size: 17, letterSpacing: 0.6),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: light.isOn ? AppTheme.green : AppTheme.textMuted,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '$roomName • ${light.isOn ? "$pct% Brightness" : "Powered Off"}',
                              style: AppTheme.body(size: 12, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.power_settings_new_rounded,
                            color: light.isOn ? AppTheme.amber : AppTheme.textMuted,
                            size: 24,
                          ),
                          onPressed: () {
                            AppHaptics.medium();
                            ctrl.togglePower();
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted, size: 22),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const Divider(color: AppTheme.border, height: 1),

              // 3. Scrollable Controls Body
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Master Brightness Scrubber
                      _buildBrightnessScrubber(light, ctrl, currentColor, pct),

                      const SizedBox(height: 16),

                      // Tabs for Fine-Grained Controls
                      Container(
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceRaised,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: TabBar(
                          controller: _tabController,
                          indicator: BoxDecoration(
                            color: AppTheme.amber.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.amber, width: 1.2),
                          ),
                          labelColor: AppTheme.amber,
                          unselectedLabelColor: AppTheme.textMuted,
                          labelStyle: AppTheme.heading(size: 11),
                          tabs: const [
                            Tab(text: 'Warmth'),
                            Tab(text: 'Palette'),
                            Tab(text: 'Presets'),
                            Tab(text: 'Ruler'),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Tab View Body
                      SizedBox(
                        height: 290,
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            // Tab 1: Kelvin Warmth Slider
                            SingleChildScrollView(
                              child: KelvinWarmthSlider(
                                initialKelvin: rgbToClosestKelvin(light.r, light.g, light.b),
                                onChanged: (k, r, g, b) {
                                  ctrl.setLiveRgb(r, g, b);
                                },
                                onChangeEnd: (k, r, g, b) {
                                  ctrl.setRgb(r, g, b);
                                },
                              ),
                            ),

                            // Tab 2: Custom RGB Palette
                            SingleChildScrollView(
                              child: _buildPaletteTab(light, ctrl),
                            ),

                            // Tab 3: Presets & Modes
                            SingleChildScrollView(
                              child: _buildPresetsTab(light, ctrl, defaultModes, presets),
                            ),

                            // Tab 4: LED Strip Visualizer & Ruler
                            SingleChildScrollView(
                              child: StripVisualizerWidget(
                                totalLeds: light.ledCount > 0 ? light.ledCount : 105,
                                segments: light.segments.isNotEmpty
                                    ? light.segments
                                    : [
                                        LedSegment(
                                          start: 0,
                                          count: light.ledCount > 0 ? light.ledCount : 105,
                                          r: light.r,
                                          g: light.g,
                                          b: light.b,
                                          name: 'Sanctum Strip',
                                        ),
                                      ],
                                onSegmentsChanged: (newSegs) {
                                  ctrl.setSegments(newSegs);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Auto-Off Timer
                      const AutoOffTimerWidget(),

                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBrightnessScrubber(
    LightState light,
    LightControlNotifier ctrl,
    Color currentColor,
    int pct,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.brightness_6_rounded, size: 16, color: AppTheme.amber),
                  const SizedBox(width: 8),
                  Text(
                    'BRIGHTNESS',
                    style: AppTheme.heading(size: 11, color: AppTheme.textMuted, letterSpacing: 1.2),
                  ),
                ],
              ),
              Text(
                '$pct%',
                style: AppTheme.heading(size: 14, color: AppTheme.amber),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: AppTheme.amber,
              inactiveTrackColor: AppTheme.surfaceRaised,
              thumbColor: AppTheme.amber,
              overlayColor: AppTheme.amber.withValues(alpha: 0.2),
              trackHeight: 8,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11),
            ),
            child: Slider(
              value: light.brightness.toDouble(),
              min: 0,
              max: 255,
              onChangeStart: (_) => ctrl.startBrightnessDrag(),
              onChanged: (val) => ctrl.setLiveBrightness(val.round()),
              onChangeEnd: (val) => ctrl.commitBrightness(val.round()),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [25, 50, 75, 100].map((preset) {
              final targetVal = ((preset / 100.0) * 255).round();
              final isCurrent = pct == preset;

              return InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  AppHaptics.selection();
                  ctrl.commitBrightness(targetVal);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isCurrent ? AppTheme.amber.withValues(alpha: 0.15) : AppTheme.surfaceRaised,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isCurrent ? AppTheme.amber : AppTheme.border,
                    ),
                  ),
                  child: Text(
                    '$preset%',
                    style: AppTheme.mono(
                      size: 11,
                      color: isCurrent ? AppTheme.amber : AppTheme.textSecondary,
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

  Widget _buildPaletteTab(LightState light, LightControlNotifier ctrl) {
    const palette = [
      {'name': 'Warm Amber', 'r': 255, 'g': 147, 'b': 41},
      {'name': 'Saffron Gold', 'r': 255, 'g': 180, 'b': 0},
      {'name': 'Temple Red', 'r': 255, 'g': 30, 'b': 30},
      {'name': 'Sacred Blue', 'r': 0, 'g': 120, 'b': 255},
      {'name': 'Divine Cyan', 'r': 0, 'g': 229, 'b': 255},
      {'name': 'Lotus Pink', 'r': 255, 'g': 80, 'b': 160},
      {'name': 'Holy Green', 'r': 0, 'g': 230, 'b': 118},
      {'name': 'Pure White', 'r': 255, 'g': 255, 'b': 255},
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: palette.map((item) {
        final r = item['r'] as int;
        final g = item['g'] as int;
        final b = item['b'] as int;
        final color = Color.fromARGB(255, r, g, b);
        final isSelected = light.r == r && light.g == g && light.b == b;

        return InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            AppHaptics.selection();
            ctrl.setRgb(r, g, b);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                        color: color.withValues(alpha: 0.35),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  item['name'] as String,
                  style: AppTheme.body(
                    size: 11.5,
                    color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
                    weight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPresetsTab(
    LightState light,
    LightControlNotifier ctrl,
    List<DefaultModeConfig> defaultModes,
    List<LightPreset> presets,
  ) {
    return Column(
      children: [
        ...defaultModes.map((m) {
          final isSelected = light.mode == m.index && light.isOn;
          final color = Color.fromARGB(255, m.r, m.g, m.b);

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                AppHaptics.selection();
                ctrl.setMode(m.index);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? color.withValues(alpha: 0.16) : AppTheme.surfaceRaised,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? color : AppTheme.border,
                    width: isSelected ? 1.6 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      m.index == 0
                          ? Icons.wb_sunny_rounded
                          : m.index == 1
                              ? Icons.adjust_rounded
                              : Icons.wb_incandescent_rounded,
                      color: isSelected ? color : AppTheme.textSecondary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.name, style: AppTheme.heading(size: 12, color: isSelected ? color : AppTheme.textPrimary)),
                          Text(m.styleLabel, style: AppTheme.body(size: 10, color: AppTheme.textMuted)),
                        ],
                      ),
                    ),
                    if (isSelected)
                      Icon(Icons.check_circle_rounded, color: color, size: 18),
                  ],
                ),
              ),
            ),
          );
        }),
        ...presets.where((p) => p.index >= 3).map((p) {
          final isSelected = light.activePreset == p.index && light.isOn;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                AppHaptics.selection();
                await ctrl.setSegments(p.segments);
                await ctrl.setAnimConfig(
                  transitionStyle: p.transitionStyle,
                  ambientStyle: p.ambientStyle,
                  ambientDepth: p.ambientDepth,
                );
                await ctrl.setPreset(p.index);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.gold.withValues(alpha: 0.16) : AppTheme.surfaceRaised,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? AppTheme.gold : AppTheme.border,
                    width: isSelected ? 1.6 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.tune_rounded, color: AppTheme.gold, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name, style: AppTheme.heading(size: 12, color: isSelected ? AppTheme.gold : AppTheme.textPrimary)),
                          Text('${p.segments.length} Segments • ${p.ambientStyleName}', style: AppTheme.body(size: 10, color: AppTheme.textMuted)),
                        ],
                      ),
                    ),
                    if (isSelected)
                      const Icon(Icons.check_circle_rounded, color: AppTheme.gold, size: 18),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}
