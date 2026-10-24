import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:temple_lights_toggle/domain/models.dart';
import 'package:temple_lights_toggle/ui/widgets/kelvin_warmth_slider.dart';
import 'package:temple_lights_toggle/ui/widgets/split_tile_card.dart';
import 'package:temple_lights_toggle/ui/widgets/strip_visualizer_widget.dart';

void main() {
  group('Planckian Blackbody Kelvin Warmth Conversion Tests', () {
    test('kelvinToRgbComponents generates authentic warm Diya amber at 2000K', () {
      final comp = kelvinToRgbComponents(2000);
      expect(comp.r, 255);
      expect(comp.g, inInclusiveRange(130, 160));
      expect(comp.b, inInclusiveRange(10, 60));
      expect(comp.color, isA<Color>());
    });

    test('kelvinToRgbComponents generates cozy golden warmth at 2700K', () {
      final comp = kelvinToRgbComponents(2700);
      expect(comp.r, 255);
      expect(comp.g, inInclusiveRange(160, 195));
      expect(comp.b, inInclusiveRange(80, 140));
    });

    test('kelvinToRgbComponents generates balanced dawn white at 4000K', () {
      final comp = kelvinToRgbComponents(4000);
      expect(comp.r, 255);
      expect(comp.g, inInclusiveRange(200, 235));
      expect(comp.b, inInclusiveRange(160, 210));
    });

    test('kelvinToRgbComponents generates pure sanctum daylight at 6500K', () {
      final comp = kelvinToRgbComponents(6500);
      expect(comp.r, inInclusiveRange(245, 255));
      expect(comp.g, inInclusiveRange(245, 255));
      expect(comp.b, inInclusiveRange(245, 255));
    });

    test('rgbToClosestKelvin maps Diya amber and pure daylight accurately', () {
      expect(rgbToClosestKelvin(255, 147, 41), inInclusiveRange(2000, 2300));
      expect(rgbToClosestKelvin(255, 255, 255), inInclusiveRange(6300, 6500));
    });
  });

  group('StripVisualizerWidget Architectural Snap Presets Tests', () {
    testWidgets('Full Strip preset creates full-range segment', (tester) async {
      List<LedSegment> updated = [];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StripVisualizerWidget(
              totalLeds: 105,
              segments: const [],
              onSegmentsChanged: (segs) => updated = segs,
            ),
          ),
        ),
      );

      final fullStripButton = find.text('Full Strip');
      expect(fullStripButton, findsOneWidget);
      await tester.tap(fullStripButton);
      await tester.pump();

      expect(updated.length, 1);
      expect(updated[0].start, 0);
      expect(updated[0].count, 105);
      expect(updated[0].end, 104);
    });

    testWidgets('Pillars & Halo preset creates exact 1-6 and 100-105 segments on 105 LEDs', (tester) async {
      List<LedSegment> updated = [];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StripVisualizerWidget(
              totalLeds: 105,
              segments: const [],
              onSegmentsChanged: (segs) => updated = segs,
            ),
          ),
        ),
      );

      final pillarsButton = find.text('Pillars & Halo');
      expect(pillarsButton, findsOneWidget);
      await tester.tap(pillarsButton);
      await tester.pump();

      expect(updated.length, 2);
      // Segment 1: Pillars (LEDs 1..6 -> indices 0..5, count 6)
      expect(updated[0].start, 0);
      expect(updated[0].count, 6);
      expect(updated[0].end, 5);

      // Segment 2: Halo (LEDs 100..105 -> indices 99..104, count 6)
      expect(updated[1].start, 99);
      expect(updated[1].count, 6);
      expect(updated[1].end, 104);
    });

    testWidgets('Center Altar preset creates centered middle segment', (tester) async {
      List<LedSegment> updated = [];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StripVisualizerWidget(
              totalLeds: 100,
              segments: const [],
              onSegmentsChanged: (segs) => updated = segs,
            ),
          ),
        ),
      );

      final altarButton = find.text('Center Altar');
      expect(altarButton, findsOneWidget);
      await tester.tap(altarButton);
      await tester.pump();

      expect(updated.length, 1);
      expect(updated[0].start, 20);
      expect(updated[0].count, 60);
      expect(updated[0].end, 79);
    });
  });

  group('SplitTileCard Widget Interaction Tests', () {
    testWidgets('Decouples power toggle from card body deep-sheet tap', (tester) async {
      bool powerToggled = false;
      bool detailOpened = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SplitTileCard(
              name: 'Sanctum Strip',
              roomLabel: '🛕 Puja Mandir',
              isOn: true,
              brightness: 200,
              color: const Color(0xFFFF9329),
              modeLabel: 'Warm Temple',
              onTogglePower: () => powerToggled = true,
              onOpenDetail: () => detailOpened = true,
              onBrightnessScrub: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Sanctum Strip'), findsOneWidget);
      expect(find.text('78%'), findsOneWidget); // (200/255)*100 = 78%

      // Tap power icon
      final powerIcon = find.byIcon(Icons.power_settings_new_rounded);
      expect(powerIcon, findsOneWidget);
      await tester.tap(powerIcon);
      await tester.pump();

      expect(powerToggled, isTrue);
      expect(detailOpened, isFalse);

      // Tap card body
      await tester.tap(find.text('Sanctum Strip'));
      await tester.pump();

      expect(detailOpened, isTrue);
    });
  });

  group('Sacred Scenes Definition & Model Tests', () {
    test('Default sacred scenes cover Morning Aarti, Evening Diya, Starlight and Night', () {
      final scenes = SacredScene.defaultScenes;
      expect(scenes.length, greaterThanOrEqualTo(5));

      final aarti = scenes.firstWhere((s) => s.id == 'scene_aarti');
      expect(aarti.name, 'Morning Aarti');
      expect(aarti.brightness, 255);
      expect(aarti.ambientStyle, 1); // Breathe

      final diya = scenes.firstWhere((s) => s.id == 'scene_diya');
      expect(diya.name, 'Evening Diya');
      expect(diya.ambientStyle, 2); // Diya Flutter
      expect(diya.kelvin, 2200);

      final night = scenes.firstWhere((s) => s.id == 'scene_night');
      expect(night.brightness, 35);
      expect(night.kelvin, 2000);
    });
  });
}
