import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:temple_lights_toggle/contract/light_contract.dart';
import 'package:temple_lights_toggle/core/kv_store.dart';
import 'package:temple_lights_toggle/domain/models.dart';
import 'package:temple_lights_toggle/domain/providers.dart';
import 'package:temple_lights_toggle/features/settings/hardware_setup_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late KvStore testKv;
  final testDev = PairedDevice(
    id: 'dev_test_123',
    name: 'Mandir Altar',
    lastSeen: DateTime.now(),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    testKv = await KvStore.instance();
  });

  group('HardwareSetupSheet Orientation Calibration Tests', () {
    testWidgets('Renders LED Strip Mounting & Orientation section with LTR and RTL options', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            kvStoreProvider.overrideWithValue(testKv),
            activeDeviceProvider.overrideWithValue(testDev),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: HardwareSetupSheet(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Header & Description
      expect(find.text('LED Strip Mounting & Orientation'), findsOneWidget);
      expect(find.textContaining('Calibrates whether your physical strip wire begins on the left or right'), findsOneWidget);

      // Verify Direction Option Cards
      expect(find.text('Left to Right'), findsOneWidget);
      expect(find.text('DIN on Left (Standard)'), findsOneWidget);
      expect(find.text('Right to Left'), findsOneWidget);
      expect(find.text('DIN on Right (Inverted)'), findsOneWidget);

      // Verify Direction Glyphs
      expect(find.text('🔴 ──► 🔵'), findsOneWidget);
      expect(find.text('🔵 ◄── 🔴'), findsOneWidget);

      // Verify Visual Shrine Perspective Diagram
      expect(find.text('SHRINE PERSPECTIVE (FRONT VIEW)'), findsOneWidget);
      expect(find.text('Left (#1)'), findsOneWidget);
      expect(find.text('Right (#150)'), findsOneWidget);

      // Verify Strip Alignment & Orientation Test
      expect(find.text('Strip Alignment & Orientation Test'), findsOneWidget);
      expect(find.textContaining('RED must illuminate on your LEFT (#1)'), findsOneWidget);
      expect(find.textContaining('BLUE must illuminate on your RIGHT'), findsOneWidget);
    });

    testWidgets('Tapping Right to Left updates selection, live diagram, and auditions orientation', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          kvStoreProvider.overrideWithValue(testKv),
          activeDeviceProvider.overrideWithValue(testDev),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: HardwareSetupSheet(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initial state is LTR (0)
      expect(container.read(lightControlProvider).stripOrientation, 0);
      expect(find.text('Standard (LTR)'), findsOneWidget);

      // Tap 'Right to Left'
      await tester.tap(find.text('Right to Left'));
      await tester.pumpAndSettle();

      // Selection badge updates to Inverted (RTL)
      expect(find.text('Inverted (RTL)'), findsOneWidget);
      expect(find.text('Hardware Inverted'), findsOneWidget);
      expect(find.text('◄── Inverted ──'), findsOneWidget);

      // Auditioned immediately to notifier
      expect(container.read(lightControlProvider).stripOrientation, 1);
    });

    testWidgets('Saving Hardware Calibration saves stripOrientation to state and device cache', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          kvStoreProvider.overrideWithValue(testKv),
          activeDeviceProvider.overrideWithValue(testDev),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => HardwareSetupSheet.show(context),
                  child: const Text('Open Calibration'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open sheet
      await tester.tap(find.text('Open Calibration'));
      await tester.pumpAndSettle();

      // Select Right to Left
      await tester.tap(find.text('Right to Left'));
      await tester.pumpAndSettle();

      // Tap Save
      await tester.tap(find.text('Save Hardware Calibration'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // Verify SnackBar feedback mentions orientation
      expect(find.textContaining('Right to Left (Inverted)'), findsOneWidget);
      expect(container.read(lightControlProvider).stripOrientation, 1);
    });
  });

  group('Backward Compatibility & Contract Safety Tests', () {
    test('Legacy PairedDevice JSON without stripOrientation restores seamlessly to default LTR', () {
      final legacyRawJson = {
        'id': 'legacy_node_123',
        'name': 'Temple Shrine Lights',
        'lastSeen': DateTime.now().toIso8601String(),
        'ledCount': 120,
        'maxCurrentMa': 3000,
        'colorOrder': 0,
        // Notice stripOrientation is completely absent
      };

      final restored = PairedDevice.fromJson(legacyRawJson);
      expect(restored.stripOrientation, isNull);
      expect(restored.effectiveStripOrientation, 0); // Safe fallback to 0 (LTR)

      // Serialization includes stripOrientation
      final serialized = restored.toJson();
      expect(serialized.containsKey('stripOrientation'), true);
      expect(serialized['stripOrientation'], isNull);
    });

    test('LightPacketEncoder.encodeSetHwConfig produces compliant JSON payload with strip_dir', () {
      final bytes = LightPacketEncoder.encodeSetHwConfig(
        leds: 180,
        maxCurrentMa: 3500,
        colorOrder: 1,
        stripDirection: 1,
      );
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

      expect(json['cmd'], 'set_hw_config');
      expect(json['leds'], 180);
      expect(json['max_ma'], 3500);
      expect(json['color_order'], 1);
      expect(json['strip_dir'], 1);
    });
  });
}
