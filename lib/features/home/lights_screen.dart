import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/haptics.dart';
import '../../domain/models.dart';
import '../../domain/providers.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/auto_off_timer_widget.dart';
import '../../ui/widgets/connection_card.dart';
import '../../ui/widgets/light_dial_button.dart';
import '../../ui/widgets/radar_sweep.dart';
import '../scanner/device_sheet.dart';

/// Main screen featuring BLE auto-connect telemetry, mode controls, brightness slider, and RGB picker.
class LightsScreen extends ConsumerWidget {
  const LightsScreen({super.key});

  void _openDevicePicker(BuildContext context) {
    DevicePickerSheet.show(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(lightSessionProvider);
    final light = ref.watch(lightControlProvider);
    final defaultModes = ref.watch(defaultModesProvider);
    final ctrl = ref.read(lightControlProvider.notifier);
    final session = ref.read(lightSessionProvider.notifier);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          children: [
            // 1. Prominent Connection & Signal Telemetry Card
            ConnectionCard(
              connState: conn,
              isDeviceOn: light.isOn && light.brightness > 0,
              onDisconnect: () => session.disconnect(),
              onForget: () => session.forgetDevice(),
              onScan: () => session.scanAndAutoConnect(),
            ),
            const SizedBox(height: 12),

            // 2. Main Control Body
            Expanded(
              child: Center(
                child: _buildCenterContent(context, conn, light, ctrl, session, defaultModes),
              ),
            ),

            // 3. Bottom Controls (When disconnected or failed)
            if (conn.phase == ConnPhase.failed ||
                conn.phase == ConnPhase.disconnected ||
                conn.phase == ConnPhase.idle) ...[
              ElevatedButton.icon(
                icon: const Icon(Icons.radar_rounded, size: 20),
                label: Text(
                  conn.isTargetPaired ? 'RECONNECT PAIRED LIGHTS' : 'SCAN & AUTO-CONNECT',
                  style: AppTheme.heading(size: 14, letterSpacing: 1.5),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.amber,
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 4,
                ),
                onPressed: () => session.scanAndAutoConnect(),
              ).animate().fadeIn().slideY(begin: 0.2, end: 0),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterContent(
    BuildContext context,
    ConnState conn,
    LightState light,
    LightControlNotifier ctrl,
    LightSessionNotifier session,
    List<DefaultModeConfig> defaultModes,
  ) {
    // 1. Scanning State -> Radar Sweep
    if (conn.isScanning) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const RadarSweep(size: 210),
          const SizedBox(height: 22),
          Text(
            conn.isTargetPaired ? 'LOCATING TEMPLE LIGHTS...' : 'SEARCHING FOR LIGHTS...',
            style: AppTheme.heading(size: 15, color: AppTheme.amber, letterSpacing: 1.8),
          ),
          const SizedBox(height: 6),
          Text(
            conn.isTargetPaired
                ? 'Standing by to link as soon as strip is powered on'
                : 'Will auto-connect to nearest Temple Lights strip',
            textAlign: TextAlign.center,
            style: AppTheme.body(size: 12.5, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            icon: const Icon(Icons.list_alt_rounded, size: 18, color: AppTheme.amber),
            label: Text('Select Manually', style: AppTheme.heading(size: 12, color: AppTheme.amber)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppTheme.borderBright),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => _openDevicePicker(context),
          ),
        ],
      ).animate().fadeIn(duration: 300.ms);
    }

    // 2. Connecting / Reconnecting State
    if (conn.isConnecting || conn.isReconnecting) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 80,
            height: 80,
            child: CircularProgressIndicator(
              strokeWidth: 3.5,
              valueColor: AlwaysStoppedAnimation(
                conn.isReconnecting ? AppTheme.gold : AppTheme.amber,
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            conn.isReconnecting ? 'AUTO-RECONNECTING...' : 'ESTABLISHING BLE LINK...',
            style: AppTheme.heading(
              size: 15,
              color: conn.isReconnecting ? AppTheme.gold : AppTheme.amber,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              conn.isReconnecting
                  ? 'Device is out of range or rebooting. The app will auto-link continuously.'
                  : 'Negotiating GATT connection with ${conn.deviceName ?? "Temple Lights"}...',
              textAlign: TextAlign.center,
              style: AppTheme.body(size: 12.5, color: AppTheme.textSecondary),
            ),
          ),
        ],
      ).animate().fadeIn(duration: 250.ms);
    }

    // 3. Connected State -> Dial, Mode Selector, Brightness, RGB Color & Auto-Off Timer
    if (conn.isConnected) {
      return SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(top: 4, bottom: 20),
        child: Column(
          children: [
            // Center Power Dial
            LightDialButton(
              isOn: light.isOn,
              mode: light.mode,
              brightness: light.brightness,
              r: light.r,
              g: light.g,
              b: light.b,
              isEnabled: true,
              onToggle: () => ctrl.togglePower(),
            ).animate().scale(begin: const Offset(0.92, 0.92), end: const Offset(1, 1), curve: Curves.elasticOut),

            const SizedBox(height: 18),

            // Mode Selector Cards
            _buildModeSelector(light, ctrl, defaultModes),

            const SizedBox(height: 14),

            // Brightness Slider Card
            _buildBrightnessCard(light, ctrl),

            const SizedBox(height: 14),

            // Custom RGB Color Palette (shown when Mode 3 is active or for direct pick)
            if (light.mode == 3) ...[
              _buildRgbPaletteCard(light, ctrl),
              const SizedBox(height: 14),
            ],

            // Quick Auto-Off Timer
            const AutoOffTimerWidget(),
          ],
        ),
      );
    }

    // 4. Disconnected / Idle
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 110,
          height: 110,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppTheme.surfaceRaised,
            border: Border.all(color: AppTheme.amber.withValues(alpha: 0.35), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: AppTheme.amber.withValues(alpha: 0.12),
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ClipOval(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Image.asset(
                'assets/icons/temple_icon.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          conn.isTargetPaired ? 'TEMPLE LIGHTS DISCONNECTED' : 'NO LIGHTS CONNECTED',
          style: AppTheme.heading(size: 15, color: AppTheme.textSecondary, letterSpacing: 1.5),
        ),
        const SizedBox(height: 6),
        Text(
          conn.errorMessage ?? 'Power on your light strip to establish link',
          textAlign: TextAlign.center,
          style: AppTheme.body(size: 12.5, color: AppTheme.textMuted),
        ),
      ],
    ).animate().fadeIn(duration: 200.ms);
  }

  Widget _buildModeSelector(
    LightState light,
    LightControlNotifier ctrl,
    List<DefaultModeConfig> defaultModes,
  ) {
    final m0 = defaultModes.isNotEmpty ? defaultModes[0] : DefaultModeConfig.factoryDefaults[0];
    final m1 = defaultModes.length > 1 ? defaultModes[1] : DefaultModeConfig.factoryDefaults[1];
    final m2 = defaultModes.length > 2 ? defaultModes[2] : DefaultModeConfig.factoryDefaults[2];

    final modes = [
      {
        'mode': 0,
        'title': m0.name,
        'sub': m0.styleLabel,
        'icon': Icons.wb_sunny_rounded,
        'color': Color.fromARGB(255, m0.r, m0.g, m0.b),
      },
      {
        'mode': 1,
        'title': m1.name,
        'sub': m1.styleLabel,
        'icon': Icons.adjust_rounded,
        'color': Color.fromARGB(255, m1.r, m1.g, m1.b),
      },
      {
        'mode': 2,
        'title': m2.name,
        'sub': m2.styleLabel,
        'icon': Icons.wb_incandescent_rounded,
        'color': Color.fromARGB(255, m2.r, m2.g, m2.b),
      },
      {
        'mode': 3,
        'title': 'Custom RGB',
        'sub': 'Color Palette',
        'icon': Icons.palette_rounded,
        'color': const Color(0xFF0284C7),
      },
    ];

    String currentModeTitle;
    if (light.mode == 0) {
      currentModeTitle = m0.name;
    } else if (light.mode == 1) {
      currentModeTitle = m1.name;
    } else if (light.mode == 2) {
      currentModeTitle = m2.name;
    } else {
      currentModeTitle = light.modeName;
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B2E1E).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'LIGHTING MODES',
                style: AppTheme.heading(size: 11, color: AppTheme.textMuted, letterSpacing: 1.2),
              ),
              Text(
                'Current: $currentModeTitle',
                style: AppTheme.body(size: 11, color: AppTheme.amber, weight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: modes.map((m) {
              final modeIdx = m['mode'] as int;
              final isSelected = light.mode == modeIdx && light.isOn && light.brightness > 0;
              final modeColor = m['color'] as Color;

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => ctrl.setMode(modeIdx),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                      decoration: BoxDecoration(
                        color: isSelected ? modeColor.withValues(alpha: 0.16) : AppTheme.surfaceRaised,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? modeColor : AppTheme.border,
                          width: isSelected ? 1.6 : 1.0,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: modeColor.withValues(alpha: 0.25),
                                  blurRadius: 10,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            m['icon'] as IconData,
                            size: 20,
                            color: isSelected ? modeColor : AppTheme.textSecondary,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            m['title'] as String,
                            textAlign: TextAlign.center,
                            style: AppTheme.heading(
                              size: 10.5,
                              color: isSelected ? modeColor : AppTheme.textPrimary,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            m['sub'] as String,
                            textAlign: TextAlign.center,
                            style: AppTheme.body(
                              size: 8.5,
                              color: isSelected ? modeColor.withValues(alpha: 0.8) : AppTheme.textMuted,
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
        ],
      ),
    );
  }

  Widget _buildBrightnessCard(LightState light, LightControlNotifier ctrl) {
    final pct = ((light.brightness / 255.0) * 100).round();

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B2E1E).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
              trackHeight: 6,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            ),
            child: Slider(
              value: light.brightness.toDouble(),
              min: 0,
              max: 255,
              onChangeStart: (_) {
                ctrl.startBrightnessDrag();
              },
              onChanged: (val) {
                ctrl.setLiveBrightness(val.round());
              },
              onChangeEnd: (val) {
                ctrl.commitBrightness(val.round());
              },
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

  Widget _buildRgbPaletteCard(LightState light, LightControlNotifier ctrl) {
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

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B2E1E).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.palette_outlined, size: 16, color: AppTheme.cyan),
                  const SizedBox(width: 8),
                  Text(
                    'CUSTOM RGB PALETTE',
                    style: AppTheme.heading(size: 11, color: AppTheme.textMuted, letterSpacing: 1.2),
                  ),
                ],
              ),
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color.fromARGB(255, light.r, light.g, light.b),
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Color.fromARGB(255, light.r, light.g, light.b).withValues(alpha: 0.6),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: palette.map((colorItem) {
              final r = colorItem['r'] as int;
              final g = colorItem['g'] as int;
              final b = colorItem['b'] as int;
              final color = Color.fromARGB(255, r, g, b);
              final isSelected = light.r == r && light.g == g && light.b == b;

              return InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => ctrl.setRgb(r, g, b),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                              blurRadius: 8,
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
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        colorItem['name'] as String,
                        style: AppTheme.body(
                          size: 11,
                          color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
                          weight: isSelected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
