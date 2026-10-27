import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:temple_lights_toggle/contract/light_contract.dart';
import 'package:temple_lights_toggle/core/kv_store.dart';
import 'package:temple_lights_toggle/domain/models.dart';
import 'package:temple_lights_toggle/domain/providers.dart';
import 'package:temple_lights_toggle/features/home/lights_screen.dart';
import 'package:temple_lights_toggle/ui/widgets/light_dial_button.dart';

void main() {
  group('Temple Lights BLE Contract & Encoder Tests', () {
    test('LightBleUuids target detection', () {
      expect(LightBleUuids.isTargetDevice(name: 'Temple Lights'), isTrue);
      expect(LightBleUuids.isTargetDevice(name: 'temple lights'), isTrue);
      expect(LightBleUuids.isTargetDevice(name: 'My Temple Light Strip'), isTrue);
      expect(
        LightBleUuids.isTargetDevice(
          name: 'Unknown',
          serviceUuids: [LightBleUuids.defaultService],
        ),
        isTrue,
      );
      expect(LightBleUuids.isTargetDevice(name: 'Random BLE Beacon'), isFalse);
    });

    test('LightPacketEncoder encodes all light control commands accurately', () {
      // 1. set_mode
      final pMode = LightPacketEncoder.encodeSetMode(2);
      final jMode = jsonDecode(utf8.decode(pMode)) as Map<String, dynamic>;
      expect(jMode['cmd'], 'set_mode');
      expect(jMode['mode'], 2);

      // 2. next_mode
      final pNext = LightPacketEncoder.encodeNextMode();
      final jNext = jsonDecode(utf8.decode(pNext)) as Map<String, dynamic>;
      expect(jNext['cmd'], 'next_mode');

      // 3. set_bright (JSON and fast 2-byte binary)
      final pBright = LightPacketEncoder.encodeSetBrightness(180);
      final jBright = jsonDecode(utf8.decode(pBright)) as Map<String, dynamic>;
      expect(jBright['cmd'], 'set_bright');
      expect(jBright['val'], 180);

      final pFastBright = LightPacketEncoder.encodeFastBrightness(220);
      expect(pFastBright.length, 2);
      expect(pFastBright[0], 0x42); // 'B'
      expect(pFastBright[1], 220);

      // 4. set_rgb
      final pRgb = LightPacketEncoder.encodeSetRgb(255, 147, 41);
      final jRgb = jsonDecode(utf8.decode(pRgb)) as Map<String, dynamic>;
      expect(jRgb['cmd'], 'set_rgb');
      expect(jRgb['r'], 255);
      expect(jRgb['g'], 147);
      expect(jRgb['b'], 41);

      // 5. on and off
      final pOn = LightPacketEncoder.encodeOn();
      final jOn = jsonDecode(utf8.decode(pOn)) as Map<String, dynamic>;
      expect(jOn['cmd'], 'on');

      final pOff = LightPacketEncoder.encodeOff();
      final jOff = jsonDecode(utf8.decode(pOff)) as Map<String, dynamic>;
      expect(jOff['cmd'], 'off');

      // 6. get_state
      final pState = LightPacketEncoder.encodeGetState();
      final jState = jsonDecode(utf8.decode(pState)) as Map<String, dynamic>;
      expect(jState['cmd'], 'get_state');

      // 7. time sync
      final now = DateTime(2026, 9, 21, 12, 0, 0);
      final pTime = LightPacketEncoder.encodeTimeSync(now);
      final jTime = jsonDecode(utf8.decode(pTime)) as Map<String, dynamic>;
      expect(jTime['cmd'], 'time');
      expect(jTime['y'], 2026);
      expect(jTime['mon'], 9);
      expect(jTime['d'], 21);
      expect(jTime['h'], 12);
      expect(jTime['m'], 0);
      expect(jTime['s'], 0);
      expect(jTime['epoch'], now.millisecondsSinceEpoch ~/ 1000);

      // 8. auto-off timer commands
      final pTimer = LightPacketEncoder.encodeStartTimer(seconds: 1200);
      final jTimer = jsonDecode(utf8.decode(pTimer)) as Map<String, dynamic>;
      expect(jTimer['cmd'], 'timer');
      expect(jTimer['sec'], 1200);

      final pCancel = LightPacketEncoder.encodeCancelTimer();
      final jCancel = jsonDecode(utf8.decode(pCancel)) as Map<String, dynamic>;
      expect(jCancel['cmd'], 'timer_cancel');

      // 9. schedules commands
      final pScheds = LightPacketEncoder.encodeGetSchedules();
      final jScheds = jsonDecode(utf8.decode(pScheds)) as Map<String, dynamic>;
      expect(jScheds['cmd'], 'get_scheds');

      final pSave = LightPacketEncoder.encodeSaveSchedule(
        id: 'sc_01',
        name: 'Evening Aarti',
        isEnabled: true,
        hasTurnOn: true,
        turnOnHour: 18,
        turnOnMinute: 30,
        hasTurnOff: true,
        turnOffHour: 20,
        turnOffMinute: 0,
        repeatDays: [1, 2, 3, 4, 5, 6, 7],
        targetMode: 3,
        targetBrightness: 255,
        targetR: 255,
        targetG: 180,
        targetB: 0,
      );
      final jSave = jsonDecode(utf8.decode(pSave)) as Map<String, dynamic>;
      expect(jSave['cmd'], 'save_sched');
      expect(jSave['id'], 'sc_01');
      expect(jSave['name'], 'Evening Aarti');
      expect(jSave['en'], isTrue);
      expect(jSave['on_h'], 18);
      expect(jSave['on_m'], 30);
      expect(jSave['off_h'], 20);
      expect(jSave['off_m'], 0);
      expect(jSave['tgt_mode'], 3);
      expect(jSave['tgt_bright'], 255);
      expect(jSave['tgt_r'], 255);
      expect(jSave['tgt_g'], 180);
      expect(jSave['tgt_b'], 0);

      final pToggle = LightPacketEncoder.encodeToggleSchedule('sc_01', false);
      final jToggle = jsonDecode(utf8.decode(pToggle)) as Map<String, dynamic>;
      expect(jToggle['cmd'], 'toggle_sched');
      expect(jToggle['id'], 'sc_01');
      expect(jToggle['en'], isFalse);

      final pDel = LightPacketEncoder.encodeDeleteSchedule('sc_01');
      final jDel = jsonDecode(utf8.decode(pDel)) as Map<String, dynamic>;
      expect(jDel['cmd'], 'del_sched');
      expect(jDel['id'], 'sc_01');

      // 10. mode config commands
      final pGetModes = LightPacketEncoder.encodeGetModes();
      final jGetModes = jsonDecode(utf8.decode(pGetModes)) as Map<String, dynamic>;
      expect(jGetModes['cmd'], 'get_modes');

      final pSaveMode = LightPacketEncoder.encodeSaveMode(
        index: 1,
        name: 'Center Sanctum',
        r: 255,
        g: 180,
        b: 0,
        style: 1,
        brightness: 200,
      );
      final jSaveMode = jsonDecode(utf8.decode(pSaveMode)) as Map<String, dynamic>;
      expect(jSaveMode['cmd'], 'save_mode');
      expect(jSaveMode['idx'], 1);
      expect(jSaveMode['name'], 'Center Sanctum');
      expect(jSaveMode['r'], 255);
      expect(jSaveMode['g'], 180);
      expect(jSaveMode['b'], 0);
      expect(jSaveMode['style'], 1);
      expect(jSaveMode['bright'], 200);

      final pResetModes = LightPacketEncoder.encodeResetModes();
      final jResetModes = jsonDecode(utf8.decode(pResetModes)) as Map<String, dynamic>;
      expect(jResetModes['cmd'], 'reset_modes');
    });

    test('DefaultModeConfig factory defaults and JSON roundtrip', () {
      expect(DefaultModeConfig.factoryDefaults.length, 3);
      expect(DefaultModeConfig.factoryDefaults[0].name, 'Warm White');
      expect(DefaultModeConfig.factoryDefaults[1].isCenterFocus, isTrue);
      expect(DefaultModeConfig.factoryDefaults[2].name, 'Pure White');

      final original = DefaultModeConfig(
        index: 0,
        name: 'Custom Amber',
        r: 255,
        g: 120,
        b: 30,
        style: 0,
        brightness: 180,
      );
      final json = original.toJson();
      final revived = DefaultModeConfig.fromJson(json);

      expect(revived.index, 0);
      expect(revived.name, 'Custom Amber');
      expect(revived.r, 255);
      expect(revived.g, 120);
      expect(revived.b, 30);
      expect(revived.style, 0);
      expect(revived.brightness, 180);
      expect(revived.isFullStrip, isTrue);
      expect(revived.brightnessPercent, 71);
    });
  });

  group('LightSchedule Evaluation & Persistence', () {
    test('LightSchedule correctly triggers turnOn and turnOff on scheduled weekdays', () {
      const schedule = LightSchedule(
        id: 'daily_puja',
        name: 'Daily Puja',
        isEnabled: true,
        hasTurnOn: true,
        turnOnHour: 6,
        turnOnMinute: 0,
        hasTurnOff: true,
        turnOffHour: 7,
        turnOffMinute: 30,
        repeatDays: [1, 2, 3, 4, 5], // Monday through Friday
        targetMode: 1,
        targetBrightness: 200,
      );

      // 2026-09-21 is Monday (weekday = 1)
      final mondayOn = DateTime(2026, 9, 21, 6, 0);
      expect(schedule.evaluateTrigger(mondayOn), ScheduleTriggerAction.turnOn);

      final mondayOff = DateTime(2026, 9, 21, 7, 30);
      expect(schedule.evaluateTrigger(mondayOff), ScheduleTriggerAction.turnOff);

      // Other minute -> null
      final mondayOther = DateTime(2026, 9, 21, 6, 15);
      expect(schedule.evaluateTrigger(mondayOther), isNull);

      // Sunday (2026-09-27) is not in repeatDays -> null
      final sundayOn = DateTime(2026, 9, 27, 6, 0);
      expect(schedule.evaluateTrigger(sundayOn), isNull);
    });

    test('LightSchedule roundtrip serialization', () {
      const original = LightSchedule(
        id: 'sched_abc',
        name: 'Special Aarti',
        isEnabled: true,
        hasTurnOn: true,
        turnOnHour: 19,
        turnOnMinute: 15,
        hasTurnOff: false,
        turnOffHour: 21,
        turnOffMinute: 0,
        repeatDays: [6, 7],
        targetMode: 3,
        targetBrightness: 240,
        targetR: 255,
        targetG: 180,
        targetB: 0,
      );

      final json = original.toJson();
      final revived = LightSchedule.fromJson(json);

      expect(revived.id, original.id);
      expect(revived.name, original.name);
      expect(revived.turnOnHour, original.turnOnHour);
      expect(revived.turnOnMinute, original.turnOnMinute);
      expect(revived.hasTurnOff, original.hasTurnOff);
      expect(revived.repeatDays, original.repeatDays);
      expect(revived.targetMode, original.targetMode);
      expect(revived.targetBrightness, original.targetBrightness);
      expect(revived.targetR, original.targetR);
      expect(revived.targetG, original.targetG);
      expect(revived.targetB, original.targetB);
    });
  });

  group('LightLogEntry & Hardware Telemetry Parsing', () {
    test('Decodes ESP32 live log notification JSON payload without error', () {
      // Exact string pattern produced by ESP32 firmware record_light_log
      const espLogPayload =
          '{"type":"log","id":"42","on":true,"mode":0,"bright":255,"epoch":1726915200,"y":2026,"mon":9,"d":21,"h":11,"m":30,"s":0,"dur":120,"src":"App Mode Change"}';

      final json = jsonDecode(espLogPayload) as Map<String, dynamic>;
      final entry = LightLogEntry.fromJson(json);

      expect(entry.id, '42');
      expect(entry.isOn, isTrue);
      expect(entry.mode, 0);
      expect(entry.brightness, 255);
      expect(entry.durationSeconds, 120);
      expect(entry.source, 'App Mode Change');
      expect(entry.timestamp.year, 2026);
      expect(entry.timestamp.month, 9);
      expect(entry.timestamp.day, 21);
      expect(entry.timestamp.hour, 11);
      expect(entry.timestamp.minute, 30);
      expect(entry.formattedDuration, '2m 0s');
    });

    test('Decodes ESP32 hydration log item with idx and total', () {
      const espHydrateLog =
          '{"type":"log","idx":0,"total":1,"id":"1","on":false,"mode":1,"bright":0,"epoch":1726915000,"y":2026,"mon":9,"d":21,"h":11,"m":0,"s":0,"dur":3600,"src":"Timer Auto-Off"}';

      final json = jsonDecode(espHydrateLog) as Map<String, dynamic>;
      final entry = LightLogEntry.fromJson(json);

      expect(entry.id, '1');
      expect(entry.isOn, isFalse);
      expect(entry.durationSeconds, 3600);
      expect(entry.formattedDuration, '1h 0s');
      expect(entry.source, 'Timer Auto-Off');
    });
  });

  group('AutoOffTimerState Calculations', () {
    test('Calculates countdown progress and format string properly', () {
      final timer = AutoOffTimerState(
        isRunning: true,
        totalSeconds: 600, // 10 minutes
        remainingSeconds: 300, // 5 minutes left
        selectedMinutes: 10,
      );

      expect(timer.progress, 0.5);
      expect(timer.formattedRemaining, '05:00');
      expect(AutoOffTimerState.formatMinutes(15), '15 min');
      expect(AutoOffTimerState.formatMinutes(90), '1h 30m');
      expect(AutoOffTimerState.formatMinutes(120), '2 hr');
    });
  });

  group('LightState Mode and Power Logic', () {
    test('LightState reports power and human-readable mode names', () {
      const state0 = LightState(isOn: true, mode: 0, brightness: 255);
      expect(state0.isOff, isFalse);
      expect(state0.modeName, 'Warm White (All 2.5m)');

      const state1 = LightState(isOn: true, mode: 1, brightness: 255);
      expect(state1.modeName, 'Warm White (Center 1.5m)');

      const state2 = LightState(isOn: true, mode: 2, brightness: 255);
      expect(state2.modeName, 'Pure White (All 2.5m)');

      const state3 = LightState(isOn: true, mode: 3, brightness: 255);
      expect(state3.modeName, 'Custom RGB');

      const offState = LightState(isOn: false, brightness: 0);
      expect(offState.isOff, isTrue);
    });
  });

  group('LightDialButton Widget Tests', () {
    testWidgets('Renders outline containers and texts properly when lights are ON', (tester) async {
      var toggled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LightDialButton(
              isOn: true,
              mode: 0,
              brightness: 255,
              r: 255,
              g: 147,
              b: 41,
              isEnabled: true,
              onToggle: () => toggled = true,
            ),
          ),
        ),
      );

      // Verify 'LIGHTS ON' and subtitle texts are present and visible
      expect(find.text('LIGHTS ON'), findsOneWidget);
      expect(find.text('MODE 1 • ALL 2.5M WARM'), findsOneWidget);

      // Tap to toggle
      await tester.tap(find.byType(LightDialButton));
      expect(toggled, isTrue);
    });

    testWidgets('Renders outline containers and standby texts when lights are OFF', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LightDialButton(
              isOn: false,
              mode: 0,
              brightness: 0,
              r: 255,
              g: 147,
              b: 41,
              isEnabled: true,
              onToggle: () {},
            ),
          ),
        ),
      );

      expect(find.text('LIGHTS OFF'), findsOneWidget);
      expect(find.text('TAP TO TURN ON'), findsOneWidget);
    });

    testWidgets('Maintains high-contrast obsidian text when Custom RGB is Pure White', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LightDialButton(
              isOn: true,
              mode: 3,
              brightness: 255,
              r: 255,
              g: 255,
              b: 255,
              isEnabled: true,
              onToggle: () {},
            ),
          ),
        ),
      );

      final textFinder = find.text('LIGHTS ON');
      expect(textFinder, findsOneWidget);
      final textWidget = tester.widget<Text>(textFinder);
      // Ensure text is not white (luminance < 0.1 so it contrasts with white porcelain)
      expect(textWidget.style?.color, const Color(0xFF1C1917));
    });

    testWidgets('Tapping LightDialButton toggles power with haptic tap and scale animation', (tester) async {
      bool toggled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: LightDialButton(
                isOn: true,
                mode: 0,
                brightness: 128,
                r: 255,
                g: 147,
                b: 41,
                isEnabled: true,
                onToggle: () => toggled = true,
              ),
            ),
          ),
        ),
      );

      // Tap to toggle
      await tester.tap(find.byType(LightDialButton));
      await tester.pump();
      expect(toggled, isTrue);
    });

    testWidgets('Tapping LightDialButton inside SingleChildScrollView triggers onToggle', (tester) async {
      bool toggled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LightDialButton(
                isOn: true,
                mode: 0,
                brightness: 128,
                r: 255,
                g: 147,
                b: 41,
                isEnabled: true,
                onToggle: () => toggled = true,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(LightDialButton));
      await tester.pump();

      expect(toggled, isTrue);
    });

    testWidgets('Disabled LightDialButton does not trigger onToggle', (tester) async {
      bool toggled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: LightDialButton(
                isOn: false,
                mode: 0,
                brightness: 0,
                r: 255,
                g: 147,
                b: 41,
                isEnabled: false,
                onToggle: () => toggled = true,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(LightDialButton));
      await tester.pump();

      expect(toggled, isFalse);
    });

    testWidgets('LightDialButton with custom subtitle displays provided subtitle', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: LightDialButton(
                isOn: false,
                mode: 0,
                brightness: 0,
                r: 255,
                g: 147,
                b: 41,
                isEnabled: true,
                subtitle: 'TAP TO POWER ON & CONNECT',
                onToggle: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('TAP TO POWER ON & CONNECT'), findsOneWidget);
    });

    testWidgets('When disconnected, LightsScreen renders interactive LightDialButton that triggers scan & toggle', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final kv = await KvStore.instance();

      final container = ProviderContainer(
        overrides: [
          kvStoreProvider.overrideWithValue(kv),
        ],
      );

      container.read(lightSessionProvider.notifier).state = const ConnState(
        phase: ConnPhase.disconnected,
        isTargetPaired: true,
      );

      container.read(lightControlProvider.notifier).state = const LightState(
        isOn: false,
        brightness: 0,
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: LightsScreen()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Dial is rendered even when disconnected
      final dial = find.byType(LightDialButton);
      expect(dial, findsOneWidget);
      expect(find.text('TAP TO POWER ON & CONNECT'), findsOneWidget);

      // Tapping it triggers power on
      await tester.tap(dial);
      await tester.pump(const Duration(milliseconds: 200));

      expect(container.read(lightControlProvider).isOn, isTrue);
    });

    testWidgets('Toggling power between ON and OFF does not crash AnimatedContainer RadialGradient.lerp', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final kv = await KvStore.instance();

      final container = ProviderContainer(
        overrides: [
          kvStoreProvider.overrideWithValue(kv),
        ],
      );

      container.read(lightSessionProvider.notifier).state = const ConnState(
        phase: ConnPhase.connected,
        deviceId: '11:22:33:44:55:66',
        deviceName: 'Temple Lights',
      );

      // Start with power ON
      container.read(lightControlProvider.notifier).state = const LightState(
        isOn: true,
        brightness: 255,
        r: 255,
        g: 147,
        b: 41,
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: LightsScreen()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      // Tap dial to turn power OFF
      await tester.tap(find.byType(LightDialButton));
      // Pump across the 600ms RadialGradient animation
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(container.read(lightControlProvider).isOn, isFalse);

      // Tap dial to turn power back ON
      await tester.tap(find.byType(LightDialButton));
      for (int i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(container.read(lightControlProvider).isOn, isTrue);
    });
  });
}
