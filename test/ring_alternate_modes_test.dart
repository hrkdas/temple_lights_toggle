import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:temple_lights_toggle/contract/light_contract.dart';
import 'package:temple_lights_toggle/core/backup_service.dart';
import 'package:temple_lights_toggle/core/kv_store.dart';
import 'package:temple_lights_toggle/domain/models.dart';
import 'package:temple_lights_toggle/ui/widgets/strip_visualizer_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_reactive_ble_method'), (call) async => null);
  });

  group('LedSegment Strided Alternate Mathematical Correctness', () {
    test('alternateOdd and alternateEven constructors generate correct stride and offset', () {
      final odd = LedSegment.alternateOdd(totalLeds: 60, r: 255, g: 147, b: 41);
      final even = LedSegment.alternateEven(totalLeds: 60, r: 0, g: 120, b: 255);

      expect(odd.start, 0);
      expect(odd.count, 60);
      expect(odd.stride, 2);
      expect(odd.offset, 0);
      expect(odd.isAlternateOdd, isTrue);
      expect(odd.isAlternateEven, isFalse);

      expect(even.start, 0);
      expect(even.count, 60);
      expect(even.stride, 2);
      expect(even.offset, 1);
      expect(even.isAlternateOdd, isFalse);
      expect(even.isAlternateEven, isTrue);

      // Verify interleaving across indices:
      // Index 0 (Human LED #1) should be in Odd, not Even
      expect(odd.containsLed(0), isTrue);
      expect(even.containsLed(0), isFalse);

      // Index 1 (Human LED #2) should be in Even, not Odd
      expect(odd.containsLed(1), isFalse);
      expect(even.containsLed(1), isTrue);

      // Index 2 (Human LED #3) should be in Odd
      expect(odd.containsLed(2), isTrue);
      expect(even.containsLed(2), isFalse);

      // Interleaving check: odd and even on the same range DO NOT overlap
      expect(odd.overlaps(even), isFalse);
    });

    test('LedSegment JSON serialization preserves stride and offset with backward compatibility', () {
      final odd = LedSegment.alternateOdd(
        totalLeds: 150,
        r: 255,
        g: 180,
        b: 0,
        brightness: 200,
        effect: 3, // Twinkle
        speed: 7,
      );

      final jsonMap = odd.toJson();
      expect(jsonMap['stride'], 2);
      expect(jsonMap['offset'], isNull); // offset 0 is omitted for compact wire size
      expect(jsonMap['fx'], 3);

      final even = LedSegment.alternateEven(totalLeds: 150, r: 0, g: 229, b: 255);
      final evenJson = even.toJson();
      expect(evenJson['stride'], 2);
      expect(evenJson['offset'], 1);

      // Deserialization round-trip
      final restoredOdd = LedSegment.fromJson(jsonMap);
      expect(restoredOdd.stride, 2);
      expect(restoredOdd.offset, 0);
      expect(restoredOdd.effect, 3);
      expect(restoredOdd.r, 255);
      expect(restoredOdd.g, 180);

      final restoredEven = LedSegment.fromJson(evenJson);
      expect(restoredEven.stride, 2);
      expect(restoredEven.offset, 1);
      expect(restoredEven.r, 0);
      expect(restoredEven.g, 229);

      // Legacy JSON without stride or offset safely defaults to stride=1, offset=0
      final legacyJson = {
        'start': 10,
        'count': 20,
        'r': 255,
        'g': 255,
        'b': 255,
      };
      final legacyRestored = LedSegment.fromJson(legacyJson);
      expect(legacyRestored.stride, 1);
      expect(legacyRestored.offset, 0);
      expect(legacyRestored.isAlternate, isFalse);
    });
  });

  group('BLE Contract Packet Encoding with Strided Segments', () {
    test('encodeSetSegments includes stride and offset for alternate segments', () {
      final odd = LedSegment.alternateOdd(totalLeds: 60, r: 255, g: 147, b: 41, effect: 3);
      final even = LedSegment.alternateEven(totalLeds: 60, r: 0, g: 120, b: 255, effect: 3);

      final packetBytes = LightPacketEncoder.encodeSetSegments([odd, even]);
      final jsonStr = utf8.decode(packetBytes);
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;

      expect(decoded['cmd'], 'set_segs');
      final segs = decoded['segs'] as List<dynamic>;
      expect(segs.length, 2);

      // Odd segment
      expect(segs[0]['stride'], 2);
      expect(segs[0]['fx'], 3);
      expect(segs[0]['r'], 255);

      // Even segment
      expect(segs[1]['stride'], 2);
      expect(segs[1]['offset'], 1);
      expect(segs[1]['fx'], 3);
      expect(segs[1]['b'], 255);
    });

    test('encodeSavePreset preserves alternate strided segments', () {
      final preset = LightPreset(
        index: 3,
        name: 'Sparkling Ring',
        segments: [
          LedSegment.alternateOdd(totalLeds: 100, r: 255, g: 180, b: 0, effect: 3),
          LedSegment.alternateEven(totalLeds: 100, r: 255, g: 255, b: 255, effect: 3),
        ],
      );

      final bytes = LightPacketEncoder.encodeSavePreset(preset);
      final jsonStr = utf8.decode(bytes);
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;

      expect(decoded['cmd'], 'save_preset');
      expect(decoded['name'], 'Sparkling Ring');
      final segs = decoded['segs'] as List<dynamic>;
      expect(segs.length, 2);
      expect(segs[0]['stride'], 2);
      expect(segs[1]['offset'], 1);
    });
  });

  group('Backup & Restore Service Backward Compatibility', () {
    test('Backup JSON snapshot preserves alternate strided presets seamlessly', () async {
      SharedPreferences.setMockInitialValues({});
      final kv = await KvStore.instance();

      final presetWithAlternate = LightPreset(
        index: 4,
        name: 'Diwali Alternate',
        segments: [
          LedSegment.alternateOdd(totalLeds: 60, r: 255, g: 30, b: 30),
          LedSegment.alternateEven(totalLeds: 60, r: 255, g: 180, b: 0),
        ],
      );

      await kv.putJson(KvKeys.savedPresets, [presetWithAlternate.toJson()]);

      final backupService = BackupService(kv);
      final backupJson = backupService.createBackupJson();

      final decoded = jsonDecode(backupJson) as Map<String, dynamic>;
      expect(decoded['version'], 2);
      final presetsList = decoded['presets'] as List<dynamic>;
      expect(presetsList.length, 1);
      final segs = presetsList[0]['segs'] as List<dynamic>;
      expect(segs.length, 2);
      expect(segs[0]['stride'], 2);
      expect(segs[1]['offset'], 1);
    });
  });

  group('StripVisualizerWidget Alternate Modes & Ring Projection UI Tests', () {
    testWidgets('Renders Mode Selector Bar and switches to Alternate mode', (tester) async {
      List<LedSegment> updated = [];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StripVisualizerWidget(
                totalLeds: 60,
                segments: const [],
                onSegmentsChanged: (segs) => updated = segs,
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      // Verify Mode Selector Bar tabs exist
      expect(find.text('✨ All LEDs'), findsOneWidget);
      expect(find.text('⚡ Alternate (Odd / Even)'), findsOneWidget);
      expect(find.text('🎨 Custom Zones'), findsOneWidget);

      // Verify Projection Toggle exists (defaults to Strip Ruler)
      expect(find.text('Strip Ruler'), findsOneWidget);

      // Tap Alternate Mode
      await tester.tap(find.text('⚡ Alternate (Odd / Even)'));
      await tester.pump(const Duration(milliseconds: 100));

      // Should have emitted 2 alternate segments (Odd and Even)
      expect(updated.length, 2);
      expect(updated[0].isAlternateOdd, isTrue);
      expect(updated[1].isAlternateEven, isTrue);
      expect(updated[0].count, 60);
      expect(updated[1].count, 60);
    });

    testWidgets('Tapping Harmonious Temple Duos applies coordinated colors', (tester) async {
      List<LedSegment> updated = [];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StripVisualizerWidget(
                totalLeds: 60,
                segments: [
                  LedSegment.alternateOdd(totalLeds: 60),
                  LedSegment.alternateEven(totalLeds: 60),
                ],
                onSegmentsChanged: (segs) => updated = segs,
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      // In Alternate mode, Temple Duos should be visible
      expect(find.text('Sanctum Dawn'), findsOneWidget);
      expect(find.text('Diwali Diya'), findsOneWidget);
      expect(find.text('Radha Krishna'), findsOneWidget);

      // Tap "Radha Krishna" (Sacred Blue + Lotus Pink)
      await tester.tap(find.text('Radha Krishna'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(updated.length, 2);
      // Odd is Sacred Blue (0, 120, 255)
      expect(updated[0].r, 0);
      expect(updated[0].g, 120);
      expect(updated[0].b, 255);

      // Even is Lotus Pink (255, 80, 160)
      expect(updated[1].r, 255);
      expect(updated[1].g, 80);
      expect(updated[1].b, 160);
    });

    testWidgets('Tapping Swap button inverts Odd and Even colors', (tester) async {
      List<LedSegment> updated = [];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StripVisualizerWidget(
                totalLeds: 60,
                segments: [
                  LedSegment.alternateOdd(totalLeds: 60, r: 255, g: 147, b: 41), // Amber
                  LedSegment.alternateEven(totalLeds: 60, r: 0, g: 120, b: 255), // Blue
                ],
                onSegmentsChanged: (segs) => updated = segs,
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      // Tap Swap button
      final swapButton = find.byTooltip('Swap Colors');
      expect(swapButton, findsOneWidget);
      await tester.tap(swapButton);
      await tester.pump(const Duration(milliseconds: 100));

      expect(updated.length, 2);
      // Odd is now Blue
      expect(updated[0].r, 0);
      expect(updated[0].b, 255);

      // Even is now Amber
      expect(updated[1].r, 255);
      expect(updated[1].b, 41);
    });

    testWidgets('Tapping Starlight Twinkle (Sparkling) dynamic sets effect to 3', (tester) async {
      List<LedSegment> updated = [];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StripVisualizerWidget(
                totalLeds: 60,
                segments: [
                  LedSegment.alternateOdd(totalLeds: 60),
                  LedSegment.alternateEven(totalLeds: 60),
                ],
                onSegmentsChanged: (segs) => updated = segs,
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      final sparkleChip = find.text('🌟 Starlight Twinkle (Sparkling)');
      expect(sparkleChip, findsOneWidget);
      await tester.tap(sparkleChip);
      await tester.pump(const Duration(milliseconds: 100));

      expect(updated.length, 2);
      expect(updated[0].effect, 3);
      expect(updated[1].effect, 3);
      expect(find.text('Sparkling Active'), findsOneWidget);
    });

    testWidgets('Toggling Projection Toggle switches between Strip Ruler and Ring Halo view', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StripVisualizerWidget(
                totalLeds: 60,
                segments: const [],
                onSegmentsChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      // Initially shows 'Strip Ruler' view
      expect(find.text('Strip Ruler'), findsOneWidget);
      expect(find.text('LED #1 (Left)'), findsOneWidget);

      // Tap to switch to Ring view
      await tester.tap(find.text('Strip Ruler'));
      await tester.pump(const Duration(milliseconds: 100));

      // Now shows 'Ring Halo' view
      expect(find.text('Ring Halo'), findsOneWidget);
      expect(find.text("LED #1 (Top • 12 o'clock)"), findsOneWidget);

      // Tap to switch back to Strip view
      await tester.tap(find.text('Ring Halo'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Strip Ruler'), findsOneWidget);
      expect(find.text('LED #1 (Left)'), findsOneWidget);
    });
  });
}
