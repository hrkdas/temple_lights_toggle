import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/haptics.dart';
import '../../domain/models.dart';
import '../../domain/providers.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/auto_off_timer_widget.dart';
import '../../ui/widgets/connection_card.dart';
import '../../ui/widgets/deep_control_sheet.dart';
import '../../ui/widgets/kelvin_warmth_slider.dart';
import '../../ui/widgets/light_dial_button.dart';
import '../../ui/widgets/radar_sweep.dart';
import '../../ui/widgets/split_tile_card.dart';
import '../../ui/widgets/strip_visualizer_widget.dart';
import '../scanner/device_sheet.dart';
import '../settings/hardware_setup_sheet.dart';

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
    final presets = ref.watch(presetsProvider);
    final rooms = ref.watch(roomsProvider);
    final activeRoomId = ref.watch(activeRoomIdProvider);
    final paired = ref.watch(pairedDevicesProvider);
    final scenes = ref.watch(sacredScenesProvider);
    final ctrl = ref.read(lightControlProvider.notifier);
    final session = ref.read(lightSessionProvider.notifier);

    final activeRoom = rooms.where((r) => r.id == activeRoomId).firstOrNull;
    final devicesInActiveRoom = activeRoomId == null
        ? paired
        : paired.where((d) => d.effectiveRoomId == activeRoomId).toList();

    final topPadding = MediaQuery.of(context).padding.top + kToolbarHeight + 8;
    final bottomPadding = MediaQuery.of(context).padding.bottom + 80;

    return Stack(
      children: [
        // 1. Serene Living Ambient Bloom (subtle radial glow reflecting light state)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 380,
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.4),
                  radius: 1.1,
                  colors: light.isOn && light.brightness > 0
                      ? [
                          Color.fromARGB(255, light.r, light.g, light.b).withValues(alpha: 0.12),
                          Color.fromARGB(255, light.r, light.g, light.b).withValues(alpha: 0.03),
                          Colors.transparent,
                        ]
                      : [Colors.transparent, Colors.transparent],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
        ),

        // 2. Single Unified, Smooth-Scrolling Canvas
        SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(20, topPadding, 20, bottomPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Telemetry / Hero Alert when NOT connected
              if (!conn.isConnected) ...[
                ConnectionCard(
                  connState: conn,
                  isDeviceOn: light.isOn && light.brightness > 0,
                  onDisconnect: () => session.disconnect(),
                  onForget: () => session.forgetDevice(),
                  onScan: () => session.scanAndAutoConnect(),
                ),
                const SizedBox(height: 12),
              ],

              // Spatial Sanctuary Header (Streamlined Room Bar, Status & Quick Scenes)
              if (conn.isConnected && (rooms.isNotEmpty || paired.isNotEmpty || scenes.isNotEmpty)) ...[
                _buildSpatialSanctuaryHeader(paired, light, conn, rooms, activeRoomId, scenes, ref),
                const SizedBox(height: 12),
              ],

              // Room Hero Card (when a specific room is selected and has devices)
              if (conn.isConnected && activeRoom != null && devicesInActiveRoom.isNotEmpty) ...[
                _buildRoomHeroCard(activeRoom, devicesInActiveRoom, ref),
                const SizedBox(height: 12),
              ],

              // Main Control Content
              _buildCenterContent(
                context,
                conn,
                light,
                ctrl,
                session,
                defaultModes,
                presets,
                paired,
                rooms,
                activeRoomId,
                ref,
              ),

              // Bottom Reconnect Action when disconnected
              if (conn.phase == ConnPhase.failed ||
                  conn.phase == ConnPhase.disconnected ||
                  conn.phase == ConnPhase.idle) ...[
                const SizedBox(height: 16),
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
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSpatialSanctuaryHeader(
    List<PairedDevice> paired,
    LightState light,
    ConnState conn,
    List<RoomModel> rooms,
    String? activeRoomId,
    List<SacredScene> scenes,
    WidgetRef ref,
  ) {
    int activeCount = 0;
    final activeRoomNames = <String>{};

    if (conn.isConnected && light.isOn && light.brightness > 0) {
      activeCount++;
      final activeDev = ref.watch(activeDeviceProvider);
      if (activeDev != null) {
        final r = rooms.where((rm) => rm.id == activeDev.effectiveRoomId).firstOrNull;
        if (r != null) activeRoomNames.add(r.name);
      }
    }

    for (final d in paired) {
      if (d.cachedIsOn == true && (d.cachedBrightness ?? 0) > 0) {
        if (!conn.isConnected || d.id != conn.deviceId) {
          activeCount++;
          final r = rooms.where((rm) => rm.id == d.effectiveRoomId).firstOrNull;
          if (r != null) activeRoomNames.add(r.name);
        }
      }
    }

    final isAnyOn = activeCount > 0;
    final roomSummary = activeRoomNames.isEmpty
        ? 'Puja Mandir'
        : activeRoomNames.take(2).join(' & ');

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAnyOn ? AppTheme.amber.withValues(alpha: 0.35) : AppTheme.border,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B2E1E).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Room Selector Chips & Master Power
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      _buildRoomChip(
                        label: 'All Rooms',
                        icon: '🏠',
                        count: paired.length,
                        isSelected: activeRoomId == null,
                        onTap: () {
                          AppHaptics.selection();
                          ref.read(activeRoomIdProvider.notifier).state = null;
                        },
                      ),
                      const SizedBox(width: 6),
                      ...rooms.map((room) {
                        final count = paired.where((d) => d.effectiveRoomId == room.id).length;
                        final isSelected = activeRoomId == room.id;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _buildRoomChip(
                            label: room.name,
                            icon: room.iconEmoji,
                            count: count,
                            isSelected: isSelected,
                            onTap: () {
                              AppHaptics.selection();
                              ref.read(activeRoomIdProvider.notifier).state = room.id;
                            },
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              if (isAnyOn) ...[
                const SizedBox(width: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () async {
                    await AppHaptics.medium();
                    await ref.read(roomsProvider.notifier).syncRoomPower('all', false);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.amber.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.amber.withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      'ALL OFF',
                      style: AppTheme.mono(size: 9.5, color: AppTheme.amber, weight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ],
          ),

          // Row 2: Status Summary line
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Row(
              children: [
                Icon(
                  isAnyOn ? Icons.lightbulb_rounded : Icons.lightbulb_outline_rounded,
                  size: 14,
                  color: isAnyOn ? AppTheme.amber : AppTheme.textMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  isAnyOn
                      ? '$activeCount light${activeCount > 1 ? "s" : ""} on • $roomSummary'
                      : 'All lights in standby',
                  style: AppTheme.body(
                    size: 11,
                    color: isAnyOn ? AppTheme.amber : AppTheme.textMuted,
                    weight: isAnyOn ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),

          // Row 3: Sacred Quick Scenes Bar
          if (scenes.isNotEmpty)
            SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: scenes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final scene = scenes[index];
                  final sceneColor = Color.fromARGB(255, scene.r, scene.g, scene.b);

                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () async {
                      await AppHaptics.selection();
                      await ref.read(roomsProvider.notifier).syncRoomScene(
                            activeRoomId ?? 'all',
                            scene,
                          );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceRaised,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(scene.emoji, style: const TextStyle(fontSize: 12)),
                          const SizedBox(width: 5),
                          Text(
                            scene.name,
                            style: AppTheme.heading(size: 10.5, color: AppTheme.textSecondary),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: sceneColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuickBrightnessChips(LightState light, LightControlNotifier ctrl) {
    final pct = ((light.brightness / 255.0) * 100).round();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [25, 50, 75, 100].map((preset) {
        final targetVal = ((preset / 100.0) * 255).round();
        final isCurrent = light.isOn && pct == preset;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              AppHaptics.selection();
              if (!light.isOn) {
                ctrl.togglePower();
              }
              ctrl.commitBrightness(targetVal);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isCurrent ? AppTheme.amber.withValues(alpha: 0.18) : AppTheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isCurrent ? AppTheme.amber : AppTheme.border,
                  width: isCurrent ? 1.4 : 1.0,
                ),
                boxShadow: isCurrent
                    ? [
                        BoxShadow(
                          color: AppTheme.amber.withValues(alpha: 0.15),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                '$preset%',
                style: AppTheme.mono(
                  size: 11,
                  color: isCurrent ? AppTheme.amber : AppTheme.textSecondary,
                  weight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRoomHeroCard(
    RoomModel room,
    List<PairedDevice> roomDevices,
    WidgetRef ref,
  ) {
    final anyOn = roomDevices.any((d) => d.cachedIsOn == true);
    final avgBrightness = roomDevices.isEmpty
        ? 255
        : (roomDevices.map((d) => d.cachedBrightness ?? 255).reduce((a, b) => a + b) / roomDevices.length).round();
    final pct = ((avgBrightness / 255.0) * 100).round();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: anyOn ? AppTheme.amber.withValues(alpha: 0.12) : AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: anyOn ? AppTheme.amber.withValues(alpha: 0.4) : AppTheme.border),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(room.iconEmoji, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(room.name, style: AppTheme.heading(size: 13)),
                      Text(
                        '${roomDevices.length} Light${roomDevices.length != 1 ? "s" : ""} • ${anyOn ? "$pct% Brightness" : "Powered Off"}',
                        style: AppTheme.body(size: 10.5, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ],
              ),
              IconButton(
                icon: Icon(
                  Icons.power_settings_new_rounded,
                  color: anyOn ? AppTheme.amber : AppTheme.textMuted,
                  size: 22,
                ),
                onPressed: () async {
                  await AppHaptics.medium();
                  await ref.read(roomsProvider.notifier).syncRoomPower(room.id, !anyOn);
                },
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
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: avgBrightness.toDouble().clamp(0.0, 255.0),
              min: 0,
              max: 255,
              onChanged: (val) {
                ref.read(roomsProvider.notifier).syncRoomBrightness(room.id, val.round());
              },
            ),
          ),
        ],
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
    List<LightPreset> presets,
    List<PairedDevice> paired,
    List<RoomModel> rooms,
    String? activeRoomId,
    WidgetRef ref,
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

    // 3. Connected State -> Split-Tile Card, Dial, Mode Selector, Kelvin Slider, Brightness, RGB Color & Auto-Off Timer
    if (conn.isConnected) {
      final activeDev = paired.where((d) => d.id == conn.deviceId).firstOrNull;
      final activeRoom = activeDev != null
          ? rooms.where((r) => r.id == activeDev.effectiveRoomId).firstOrNull
          : null;
      final roomLabel = activeRoom?.name ?? 'Puja Mandir';

      return Column(
        children: [
          // Center Porcelain Power Dial with Rotary Touch Dimming
          LightDialButton(
            isOn: light.isOn,
            mode: light.mode,
            brightness: light.brightness,
            r: light.r,
            g: light.g,
            b: light.b,
            isEnabled: true,
            onToggle: () => ctrl.togglePower(),
            onBrightnessScrub: (val) => ctrl.setLiveBrightness(val),
            onBrightnessCommit: (val) => ctrl.commitBrightness(val),
          ).animate().scale(begin: const Offset(0.92, 0.92), end: const Offset(1, 1), curve: Curves.elasticOut),

          const SizedBox(height: 12),

          // Quick-Snap Brightness Chips directly beneath the dial
          _buildQuickBrightnessChips(light, ctrl),

          const SizedBox(height: 16),

          // Next-Gen Split-Tile Device Card (Tap body opens DeepControlSheet, drag scrubs, tap icon toggles power)
          SplitTileCard(
            name: activeDev?.displayName ?? conn.deviceName ?? 'Temple Lights',
            roomLabel: '$roomLabel • Linked',
            isOn: light.isOn,
            brightness: light.brightness,
            color: Color.fromARGB(255, light.r, light.g, light.b),
            modeLabel: light.modeName,
            onTogglePower: () => ctrl.togglePower(),
            onOpenDetail: () => DeepControlSheet.show(context),
            onBrightnessScrub: (val) => ctrl.setLiveBrightness(val),
          ),

          const SizedBox(height: 14),

          // Mode Selector Cards
          _buildModeSelector(light, ctrl, defaultModes, presets),

          const SizedBox(height: 14),

          // Dedicated Kelvin Warmth Slider (2000K to 6500K)
          KelvinWarmthSlider(
            initialKelvin: rgbToClosestKelvin(light.r, light.g, light.b),
            onChanged: (k, r, g, b) => ctrl.setLiveRgb(r, g, b),
            onChangeEnd: (k, r, g, b) => ctrl.setRgb(r, g, b),
          ),

          const SizedBox(height: 14),

          // Brightness Slider Card
          _buildBrightnessCard(light, ctrl),

          const SizedBox(height: 14),

          // Interactive LED Strip Ruler & Range Selection Card
          _buildStripRulerCard(context, light, ctrl),

          const SizedBox(height: 14),

          // Custom RGB Color Palette (always accessible)
          _buildRgbPaletteCard(context, light, ctrl),
          const SizedBox(height: 14),

          // Quick Auto-Off Timer
          const AutoOffTimerWidget(),
        ],
      );
    }

    // 4. Disconnected / Idle
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 100,
          height: 100,
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
              padding: const EdgeInsets.all(12),
              child: Image.asset(
                'assets/icons/temple_icon.png',
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
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
        if (paired.isNotEmpty) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '${paired.length} Paired device${paired.length != 1 ? "s" : ""} standing by for automatic GATT sync',
              textAlign: TextAlign.center,
              style: AppTheme.body(size: 11, color: AppTheme.amber),
            ),
          ),
        ],
      ],
    ).animate().fadeIn(duration: 200.ms);
  }

  Widget _buildRoomChip({
    required String label,
    required String icon,
    required int count,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.amber.withValues(alpha: 0.16) : AppTheme.surfaceRaised,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppTheme.amber : AppTheme.border,
            width: isSelected ? 1.6 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            Text(
              label,
              style: AppTheme.heading(
                size: 11,
                color: isSelected ? AppTheme.amber : AppTheme.textSecondary,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.amber.withValues(alpha: 0.25) : AppTheme.surface,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '$count',
                  style: AppTheme.mono(
                    size: 9,
                    color: isSelected ? AppTheme.amber : AppTheme.textMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildModeSelector(
    LightState light,
    LightControlNotifier ctrl,
    List<DefaultModeConfig> defaultModes,
    List<LightPreset> presets,
  ) {
    final m0 = defaultModes.isNotEmpty ? defaultModes[0] : DefaultModeConfig.factoryDefaults[0];
    final m1 = defaultModes.length > 1 ? defaultModes[1] : DefaultModeConfig.factoryDefaults[1];
    final m2 = defaultModes.length > 2 ? defaultModes[2] : DefaultModeConfig.factoryDefaults[2];

    final modes = <Map<String, dynamic>>[
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

    // Add any additional presets beyond the 3 factory modes
    final customPresets = presets.where((p) => p.index >= 3).toList();
    for (final p in customPresets) {
      final firstSeg = p.segments.isNotEmpty ? p.segments.first : null;
      final pColor = firstSeg != null ? Color.fromARGB(255, firstSeg.r, firstSeg.g, firstSeg.b) : AppTheme.gold;
      modes.add({
        'mode': p.index,
        'title': p.name,
        'sub': '${p.segments.length} Segs',
        'icon': Icons.tune_rounded,
        'color': pColor,
        'preset': p,
      });
    }

    String currentModeTitle;
    final activeMatchingPreset = presets.where((p) => p.index == light.activePreset).firstOrNull;
    if (activeMatchingPreset != null && light.activePreset > 0) {
      currentModeTitle = activeMatchingPreset.name;
    } else if (light.mode == 0) {
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
          if (modes.length <= 4)
            Row(
              children: modes.map((m) => Expanded(child: _buildModeTile(m, light, ctrl))).toList(),
            )
          else
            SizedBox(
              height: 76,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: modes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, idx) => SizedBox(
                  width: 82,
                  child: _buildModeTile(modes[idx], light, ctrl),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildModeTile(
    Map<String, dynamic> m,
    LightState light,
    LightControlNotifier ctrl,
  ) {
    final modeIdx = m['mode'] as int;
    final isSelected = ((light.mode == modeIdx && !m.containsKey('preset')) ||
            (light.activePreset == modeIdx && m.containsKey('preset'))) &&
        light.isOn &&
        light.brightness > 0;
    final modeColor = m['color'] as Color;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          if (m.containsKey('preset')) {
            final p = m['preset'] as LightPreset;
            await ctrl.setPreset(p.index);
          } else {
            await ctrl.setMode(modeIdx);
          }
        },
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.body(
                  size: 8.5,
                  color: isSelected ? modeColor.withValues(alpha: 0.8) : AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
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

  Widget _buildStripRulerCard(
    BuildContext context,
    LightState light,
    LightControlNotifier ctrl,
  ) {
    final stripCount = light.ledCount > 0 ? light.ledCount : 105;
    final hasActiveSegments = light.segments.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasActiveSegments
              ? AppTheme.amber.withValues(alpha: 0.45)
              : AppTheme.border,
          width: hasActiveSegments ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: hasActiveSegments
                ? AppTheme.amber.withValues(alpha: 0.08)
                : const Color(0xFF3B2E1E).withValues(alpha: 0.04),
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
                  const Icon(Icons.linear_scale_rounded, size: 16, color: AppTheme.amber),
                  const SizedBox(width: 8),
                  Text(
                    'LED STRIP RULER & RANGES',
                    style: AppTheme.heading(size: 11, color: AppTheme.textMuted, letterSpacing: 1.2),
                  ),
                ],
              ),
              if (hasActiveSegments)
                GestureDetector(
                  onTap: () async {
                    AppHaptics.selection();
                    await ctrl.setRgb(light.r, light.g, light.b);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.amber.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.restart_alt_rounded, size: 12, color: AppTheme.amber),
                        const SizedBox(width: 4),
                        Text(
                          'Reset Full',
                          style: AppTheme.heading(size: 10, color: AppTheme.amber),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          StripVisualizerWidget(
            totalLeds: stripCount,
            height: 70,
            segments: light.segments.isNotEmpty
                ? light.segments
                : [
                    LedSegment(
                      start: 0,
                      count: stripCount,
                      r: light.r,
                      g: light.g,
                      b: light.b,
                      name: 'Full Strip',
                    ),
                  ],
            onSegmentsChanged: (newSegs) {
              ctrl.setSegments(newSegs);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRgbPaletteCard(BuildContext context, LightState light, LightControlNotifier ctrl) {
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
              Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => HardwareSetupSheet.show(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.amber.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.amber.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.tune_rounded, size: 12, color: AppTheme.amber),
                          const SizedBox(width: 4),
                          Text('Calibrate', style: AppTheme.heading(size: 10.5, color: AppTheme.amber)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _showCustomColorDialog(context, light, ctrl),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.cyan.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.cyan.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.colorize_rounded, size: 12, color: AppTheme.cyan),
                          const SizedBox(width: 4),
                          Text('Sliders', style: AppTheme.heading(size: 10.5, color: AppTheme.cyan)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
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
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ...palette.map((colorItem) {
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
              }),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _showCustomColorDialog(context, light, ctrl),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceRaised,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppTheme.cyan.withValues(alpha: 0.5),
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add_rounded, size: 14, color: AppTheme.cyan),
                      const SizedBox(width: 4),
                      Text(
                        'Custom RGB',
                        style: AppTheme.body(
                          size: 11,
                          color: AppTheme.cyan,
                          weight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showCustomColorDialog(BuildContext context, LightState light, LightControlNotifier ctrl) {
    int curR = light.r;
    int curG = light.g;
    int curB = light.b;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final currentColor = Color.fromARGB(255, curR, curG, curB);

            Widget buildColorSlider({
              required String label,
              required int value,
              required Color activeColor,
              required ValueChanged<int> onChanged,
            }) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(label, style: AppTheme.heading(size: 12, color: activeColor)),
                      Text('$value', style: AppTheme.mono(size: 12, color: AppTheme.textSecondary)),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(dialogCtx).copyWith(
                      activeTrackColor: activeColor,
                      inactiveTrackColor: AppTheme.surfaceRaised,
                      thumbColor: activeColor,
                      trackHeight: 4,
                    ),
                    child: Slider(
                      value: value.toDouble(),
                      min: 0,
                      max: 255,
                      onChanged: (v) {
                        final rounded = v.round();
                        setDialogState(() => onChanged(rounded));
                        ctrl.setLiveRgb(curR, curG, curB);
                      },
                      onChangeEnd: (v) {
                        ctrl.setRgb(curR, curG, curB);
                      },
                    ),
                  ),
                ],
              );
            }

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
                      border: Border.all(color: Colors.white, width: 1.5),
                      boxShadow: [
                        BoxShadow(color: currentColor.withValues(alpha: 0.6), blurRadius: 8),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text('Custom RGB Color', style: AppTheme.heading(size: 16)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 48,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: currentColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.borderBright),
                      boxShadow: [
                        BoxShadow(color: currentColor.withValues(alpha: 0.35), blurRadius: 10),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        'RGB($curR, $curG, $curB)',
                        style: TextStyle(
                          color: (curR * 0.299 + curG * 0.587 + curB * 0.114) > 160 ? Colors.black : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  buildColorSlider(
                    label: 'RED',
                    value: curR,
                    activeColor: Colors.redAccent,
                    onChanged: (v) => curR = v,
                  ),
                  buildColorSlider(
                    label: 'GREEN',
                    value: curG,
                    activeColor: Colors.greenAccent,
                    onChanged: (v) => curR = v,
                  ),
                  buildColorSlider(
                    label: 'BLUE',
                    value: curB,
                    activeColor: Colors.lightBlueAccent,
                    onChanged: (v) => curB = v,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text('Done', style: AppTheme.heading(size: 13, color: AppTheme.amber)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
