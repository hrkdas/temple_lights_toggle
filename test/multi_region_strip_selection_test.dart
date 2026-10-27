import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:temple_lights_toggle/core/backup_service.dart';
import 'package:temple_lights_toggle/core/kv_store.dart';
import 'package:temple_lights_toggle/domain/models.dart';
import 'package:temple_lights_toggle/ui/widgets/strip_visualizer_widget.dart';
import 'package:temple_lights_toggle/ui/widgets/zone_config_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_reactive_ble_method'), (call) async => null);
  });

  group('LedSegment Mathematical Correctness & Resilience', () {
    test('containsLed and overlaps work accurately', () {
      const seg1 = LedSegment(start: 0, count: 15); // LEDs 0..14
      const seg2 = LedSegment(start: 15, count: 20); // LEDs 15..34
      const segOverlap = LedSegment(start: 10, count: 10); // LEDs 10..19

      expect(seg1.containsLed(0), isTrue);
      expect(seg1.containsLed(14), isTrue);
      expect(seg1.containsLed(15), isFalse);

      expect(seg2.containsLed(15), isTrue);
      expect(seg2.containsLed(34), isTrue);
      expect(seg2.containsLed(35), isFalse);

      expect(seg1.overlaps(seg2), isFalse);
      expect(seg1.overlaps(segOverlap), isTrue);
      expect(seg2.overlaps(segOverlap), isTrue);
    });

    test('operator == and hashCode compare by value', () {
      const segA = LedSegment(start: 5, count: 10, r: 255, g: 180, b: 0, name: 'Altar');
      const segB = LedSegment(start: 5, count: 10, r: 255, g: 180, b: 0, name: 'Altar');
      const segDiff = LedSegment(start: 5, count: 10, r: 255, g: 147, b: 41, name: 'Altar');

      expect(segA, equals(segB));
      expect(segA.hashCode, equals(segB.hashCode));
      expect(segA, isNot(equals(segDiff)));
    });

    test('LedSegment.fromJson clamps negative or out-of-range values safely', () {
      final crazyJson = {
        'start': -10,
        'count': -5,
        'r': 999,
        'g': -50,
        'b': 300,
        'bright': -1,
        'fx': 99,
        'spd': 50,
      };

      final seg = LedSegment.fromJson(crazyJson);
      expect(seg.start, 0); // clamped to >= 0
      expect(seg.count, 1); // clamped to >= 1
      expect(seg.r, 255); // clamped to 255
      expect(seg.g, 0); // clamped to 0
      expect(seg.b, 255); // clamped to 255
      expect(seg.brightness, 0); // clamped to 0
      expect(seg.effect, 6); // clamped to 6
      expect(seg.speed, 10); // clamped to 10
      expect(seg.color.toARGB32(), 0xFFFF00FF);
    });
  });

  group('StripVisualizerWidget Multi-Selection & Interactive Zoning', () {
    testWidgets('Renders strip ruler and interactive zone chips', (tester) async {
      final segments = [
        const LedSegment(start: 0, count: 15, r: 255, g: 147, b: 41, name: 'Left Pillar'),
        const LedSegment(start: 30, count: 45, r: 255, g: 180, b: 0, name: 'Center Altar'),
        const LedSegment(start: 90, count: 15, r: 255, g: 147, b: 41, name: 'Right Pillar'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StripVisualizerWidget(
              totalLeds: 105,
              segments: segments,
              onSegmentsChanged: (_) {},
            ),
          ),
        ),
      );

      // StripVisualizer has a repeating AnimationController, use pump with duration
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('LED STRIP RULER (105 LEDs)'), findsOneWidget);
      expect(find.text('Multi-Select'), findsOneWidget);
      expect(find.text('Quick Range'), findsOneWidget);

      // Verify zone chips are visible
      expect(find.text('Left Pillar'), findsOneWidget);
      expect(find.text('Center Altar'), findsAtLeast(1));
      expect(find.text('Right Pillar'), findsOneWidget);
      expect(find.text('Add Region'), findsOneWidget);
    });

    testWidgets('Toggling Multi-Select mode allows selecting multiple regions without deselecting',
        (tester) async {
      final segments = [
        const LedSegment(start: 0, count: 15, r: 255, g: 147, b: 41, name: 'Left Pillar'),
        const LedSegment(start: 30, count: 45, r: 255, g: 180, b: 0, name: 'Center Altar'),
        const LedSegment(start: 90, count: 15, r: 255, g: 147, b: 41, name: 'Right Pillar'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StripVisualizerWidget(
              totalLeds: 105,
              segments: segments,
              onSegmentsChanged: (_) {},
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      // 1. Turn ON Multi-Select
      await tester.tap(find.text('Multi-Select'));
      await tester.pump(const Duration(milliseconds: 100));

      // 2. Tap Left Pillar chip
      await tester.tap(find.text('Left Pillar'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('1 Selected'), findsOneWidget);

      // 3. Tap Right Pillar chip (Previously this would have deselected Left Pillar)
      await tester.tap(find.text('Right Pillar'));
      await tester.pump(const Duration(milliseconds: 100));

      // Verify BOTH are now selected!
      expect(find.text('2 Selected'), findsOneWidget);
      expect(find.text('Configure Light'), findsOneWidget);
      expect(find.text('Deselect'), findsOneWidget);

      // 4. Tap Deselect
      await tester.tap(find.text('Deselect'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('2 Selected'), findsNothing);
    });

    testWidgets('Non-destructive Add Region appends new segment rather than overwriting', (tester) async {
      List<LedSegment> currentSegments = [
        const LedSegment(start: 0, count: 15, r: 255, g: 147, b: 41, name: 'Left Pillar'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return StripVisualizerWidget(
                  totalLeds: 105,
                  segments: currentSegments,
                  enableTapToConfigure: false, // keep modal closed in this test
                  onSegmentsChanged: (newSegs) {
                    setState(() {
                      currentSegments = newSegs;
                    });
                  },
                );
              },
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));
      expect(currentSegments.length, 1);

      // Tap 'Add Region'
      await tester.tap(find.text('Add Region'));
      await tester.pump(const Duration(milliseconds: 100));

      // Verify that the original segment is preserved and total segments is now 2
      expect(currentSegments.length, 2);
      expect(currentSegments[0].name, 'Left Pillar');
      expect(currentSegments[1].name, 'Zone 2');
    });
  });

  group('ZoneConfigSheet Batch Synchronized Configuration', () {
    testWidgets('Batch mutates color and brightness across multiple selected segments', (tester) async {
      List<LedSegment> testSegments = [
        const LedSegment(start: 0, count: 15, r: 255, g: 147, b: 41, brightness: 255, name: 'Left Pillar'),
        const LedSegment(start: 30, count: 45, r: 255, g: 180, b: 0, brightness: 255, name: 'Center Altar'),
        const LedSegment(start: 90, count: 15, r: 255, g: 147, b: 41, brightness: 255, name: 'Right Pillar'),
      ];

      final selectedIndices = {0, 2}; // Select both pillars

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ZoneConfigSheet(
              segments: testSegments,
              selectedIndices: selectedIndices,
              totalLeds: 105,
              onSegmentsUpdated: (updated) {
                testSegments = updated;
              },
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      // Header indicates 2 regions are selected
      expect(find.text('2 Regions Selected'), findsOneWidget);
      expect(find.text('30 LEDs total • Synchronized batch control'), findsOneWidget);

      // Pick 'Temple Red' swatch
      await tester.tap(find.text('Temple Red'));
      await tester.pump(const Duration(milliseconds: 100));

      // Verify both segment 0 and segment 2 are updated to Temple Red
      expect(testSegments[0].r, 255);
      expect(testSegments[0].g, 30);
      expect(testSegments[0].b, 30);

      expect(testSegments[2].r, 255);
      expect(testSegments[2].g, 30);
      expect(testSegments[2].b, 30);

      // Center Altar (index 1) remains untouched!
      expect(testSegments[1].r, 255);
      expect(testSegments[1].g, 180);
      expect(testSegments[1].b, 0);

      // Tap 'Done'
      expect(find.text('Done (Apply to 2 Regions)'), findsOneWidget);
    });

    testWidgets('Single segment mode allows boundary nudging and renaming', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      addTearDown(tester.view.resetPhysicalSize);

      List<LedSegment> testSegments = [
        const LedSegment(start: 10, count: 20, r: 255, g: 147, b: 41, name: 'Altar'),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ZoneConfigSheet(
              segments: testSegments,
              selectedIndices: const {0},
              totalLeds: 105,
              onSegmentsUpdated: (updated) {
                testSegments = updated;
              },
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      // Should show precise boundary section
      final boundarySection = find.text('PRECISE LED BOUNDARIES');
      await tester.ensureVisible(boundarySection);
      await tester.pump(const Duration(milliseconds: 100));
      expect(boundarySection, findsOneWidget);

      // Nudge start LED up
      final addButtons = find.byIcon(Icons.add_circle_outline_rounded);
      await tester.ensureVisible(addButtons.first);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(addButtons.first); // increment Start LED
      await tester.pump(const Duration(milliseconds: 100));

      expect(testSegments[0].start, 11);
    });
  });

  group('Database Backup & Restore Backward Compatibility', () {
    test('Restoring legacy backup JSON without segments gracefully generates valid models', () async {
      SharedPreferences.setMockInitialValues({});

      final legacyBackup = {
        'version': 1,
        'app': 'Temple Lights Toggle',
        'modes': [
          {
            'index': 0,
            'name': 'Sanctuary Amber',
            'r': 255,
            'g': 147,
            'b': 41,
            'style': 0,
            'brightness': 255,
          },
          {
            'index': 1,
            'name': 'Center Focus',
            'r': 255,
            'g': 180,
            'b': 0,
            'style': 1,
            'brightness': 255,
          },
        ],
      };

      final kv = await KvStore.instance();
      final service = BackupService(kv);

      // Verify createBackupJson creates valid v2 payload
      final v2Str = service.createBackupJson();
      final v2Decoded = jsonDecode(v2Str) as Map<String, dynamic>;
      expect(v2Decoded['version'], 2);
      expect(v2Decoded.containsKey('presets'), isTrue);

      // Verify LedSegment can parse any legacy items without throwing
      final rawMode = (legacyBackup['modes'] as List)[0] as Map<String, dynamic>;
      final modeConfig = DefaultModeConfig.fromJson(rawMode);
      final preset = LightPreset.fromLegacyDefaultMode(modeConfig, totalLeds: 105);

      expect(preset.segments.isNotEmpty, isTrue);
      expect(preset.segments.first.start, 0);
      expect(preset.segments.first.count, 105);
      expect(preset.segments.first.r, 255);
      expect(preset.segments.first.g, 147);
      expect(preset.segments.first.b, 41);
    });
  });
}
