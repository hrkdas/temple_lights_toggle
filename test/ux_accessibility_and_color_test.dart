import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:temple_lights_toggle/domain/models.dart';
import 'package:temple_lights_toggle/ui/theme.dart';
import 'package:temple_lights_toggle/ui/widgets/kelvin_warmth_slider.dart';
import 'package:temple_lights_toggle/ui/widgets/light_dial_button.dart';
import 'package:temple_lights_toggle/ui/widgets/split_tile_card.dart';
import 'package:temple_lights_toggle/ui/widgets/status_pill.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RSSI Color & Telemetry Threshold Tests', () {
    test('Strong RSSI (>= -72 dBm) maps to green', () {
      const conn = ConnState(phase: ConnPhase.connected, rssi: -65);
      expect(conn.signalColor, const Color(0xFF059669)); // Green
      expect(conn.signalQualityLabel, 'Good (Moderate)');
    });

    test('Moderate RSSI (-73 to -84 dBm) maps to amber', () {
      const conn = ConnState(phase: ConnPhase.connected, rssi: -78);
      expect(conn.signalColor, const Color(0xFFD97706)); // Amber
      expect(conn.signalQualityLabel, 'Fair (Distant)');
    });

    test('Critical weak RSSI (<= -85 dBm) maps to red instead of green', () {
      const conn102 = ConnState(phase: ConnPhase.connected, rssi: -102);
      expect(conn102.signalColor, const Color(0xFFDC2626)); // Red
      expect(conn102.signalQualityLabel, 'Weak (Far Range)');

      const conn88 = ConnState(phase: ConnPhase.connected, rssi: -88);
      expect(conn88.signalColor, const Color(0xFFDC2626)); // Red
    });

    test('Disconnected state maps to muted color', () {
      const conn = ConnState(phase: ConnPhase.disconnected);
      expect(conn.signalColor, const Color(0xFF8C867D));
    });
  });

  group('Accessibility & Semantics Tests', () {
    testWidgets('SplitTileCard power button exposes accessible Semantics button and state', (tester) async {
      var toggled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SplitTileCard(
              name: 'Puja Temple lights',
              roomLabel: 'Puja Mandir',
              isOn: true,
              brightness: 255,
              color: AppTheme.amber,
              modeLabel: 'Warm White',
              onTogglePower: () => toggled = true,
              onOpenDetail: () {},
              onBrightnessScrub: (_) {},
            ),
          ),
        ),
      );

      final semanticsFinder = find.byWidgetPredicate(
        (w) => w is Semantics && (w.properties.label?.contains('Power toggle for Puja Temple lights') ?? false),
      );
      expect(semanticsFinder, findsOneWidget);

      final semantics = tester.widget<Semantics>(semanticsFinder);
      expect(semantics.properties.button, true);
      expect(semantics.properties.label, contains('On at 100%'));

      // Tap power button via semantics
      await tester.tap(semanticsFinder);
      expect(toggled, true);
    });

    testWidgets('LightDialButton exposes detailed accessible Semantics label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LightDialButton(
              isOn: true,
              mode: 0,
              brightness: 128,
              r: 255,
              g: 147,
              b: 41,
              isEnabled: true,
              onToggle: () {},
            ),
          ),
        ),
      );

      final dialSemanticsFinder = find.byWidgetPredicate(
        (w) => w is Semantics && (w.properties.label?.contains('Currently lit at 50% brightness') ?? false),
      );
      expect(dialSemanticsFinder, findsOneWidget);
    });

    testWidgets('KelvinWarmthSlider provides formatted semantic label for screen readers', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KelvinWarmthSlider(
              initialKelvin: 2700,
              onChanged: (_, __, ___, ____) {},
            ),
          ),
        ),
      );

      final sliderFinder = find.byType(Slider);
      expect(sliderFinder, findsOneWidget);

      final slider = tester.widget<Slider>(sliderFinder);
      expect(slider.semanticFormatterCallback, isNotNull);
      final formatted = slider.semanticFormatterCallback!(2700);
      expect(formatted, contains('2700 Kelvin'));
      expect(formatted, contains('Warm White'));
    });

    testWidgets('StatusPill exposes liveRegion with connection status label', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatusPill(
              connState: ConnState(phase: ConnPhase.connected, rssi: -68),
              isRelayOn: true,
            ),
          ),
        ),
      );

      final pillSemanticsFinder = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.liveRegion == true,
      );
      expect(pillSemanticsFinder, findsOneWidget);

      final semantics = tester.widget<Semantics>(pillSemanticsFinder);
      expect(semantics.properties.label, contains('RELAY CLOSED • ON (-68 dBm)'));
    });
  });

  group('Dark Mode Theme Tests', () {
    test('AppTheme.buildDark() produces valid Material 3 dark theme with sacred palette', () {
      final darkTheme = AppTheme.buildDark();
      expect(darkTheme.brightness, Brightness.dark);
      expect(darkTheme.scaffoldBackgroundColor, AppTheme.darkBackground);
      expect(darkTheme.colorScheme.surface, AppTheme.darkSurface);
      expect(darkTheme.colorScheme.onSurface, AppTheme.darkTextPrimary);
    });
  });
}
