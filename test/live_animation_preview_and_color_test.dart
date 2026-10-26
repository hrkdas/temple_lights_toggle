import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:temple_lights_toggle/contract/light_contract.dart';
import 'package:temple_lights_toggle/domain/models.dart';
import 'package:temple_lights_toggle/domain/providers.dart';
import 'package:temple_lights_toggle/ui/widgets/live_animation_preview_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('flutter_reactive_ble_method'), (call) async => null);

  group('Fast Binary RGB Protocol & Live Audition Contracts', () {
    test('encodeFastRgb encodes 4-byte stream packet with 0x43 opcode and 0..255 clamping', () {
      final pkt = LightPacketEncoder.encodeFastRgb(255, 147, 41);
      expect(pkt.length, 4);
      expect(pkt[0], 0x43); // 'C' opcode
      expect(pkt[1], 255);
      expect(pkt[2], 147);
      expect(pkt[3], 41);

      // Clamping test
      final clamped = LightPacketEncoder.encodeFastRgb(-10, 300, 128);
      expect(clamped[0], 0x43);
      expect(clamped[1], 0);
      expect(clamped[2], 255);
      expect(clamped[3], 128);
    });

    test('encodeAnimPreview formats JSON packet for immediate physical strip audition', () {
      final pkt = LightPacketEncoder.encodeAnimPreview(
        transitionStyle: 4, // Dual Convergence
        ambientStyle: 4,    // Amber Embers
        depth: 12,
      );
      final json = jsonDecode(utf8.decode(pkt)) as Map<String, dynamic>;
      expect(json['cmd'], 'anim_preview');
      expect(json['trans'], 4);
      expect(json['ambient'], 4);
      expect(json['depth'], 12);
    });

    test('All 7 Devotional Transitions and 7 Living Ambient Auras are specified in LightState', () {
      expect(LightState.transitionStyleNames.length, 7);
      expect(LightState.transitionStyleNames[0], 'Center-Out Dawn');
      expect(LightState.transitionStyleNames[1], 'Sunrise Flow');
      expect(LightState.transitionStyleNames[2], 'Uniform Smooth Fade');
      expect(LightState.transitionStyleNames[3], 'Sunset Cascade');
      expect(LightState.transitionStyleNames[4], 'Dual Convergence');
      expect(LightState.transitionStyleNames[5], 'Sparkle Ignition');
      expect(LightState.transitionStyleNames[6], 'Segment Domino');

      expect(LightState.ambientStyleNames.length, 7);
      expect(LightState.ambientStyleNames[0], 'Pure Solid');
      expect(LightState.ambientStyleNames[1], 'Gentle Breathing');
      expect(LightState.ambientStyleNames[2], 'Diya Candle Flutter');
      expect(LightState.ambientStyleNames[3], 'Starlight Twinkle');
      expect(LightState.ambientStyleNames[4], 'Sacred Amber Embers');
      expect(LightState.ambientStyleNames[5], 'Aurora Flow');
      expect(LightState.ambientStyleNames[6], 'Rainbow Cycle');
    });
  });

  group('LiveAnimationPreviewWidget UI & Canvas Rendering', () {
    testWidgets('Renders LiveAnimationPreviewWidget with active style tags and replay button', (tester) async {
      bool auditionTapped = false;

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: LiveAnimationPreviewWidget(
                  transitionStyle: 4, // Dual Convergence
                  ambientStyle: 2,    // Diya Candle Flutter
                  ambientDepth: 10,
                  r: 255,
                  g: 147,
                  b: 41,
                  brightness: 255,
                  onAudition: () {
                    auditionTapped = true;
                  },
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('LIVE ANIMATION PREVIEW'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.byType(OutlinedButton), findsOneWidget);
      expect(find.byType(ElevatedButton), findsOneWidget);

      // Verify Audition button triggers callback
      await tester.tap(find.text('Audition on Strip'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(auditionTapped, isTrue);

      // Verify Replay button can be triggered
      await tester.tap(find.byType(OutlinedButton));
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('LiveAnimationPreviewWidget updates smoothly across all 7 transitions', (tester) async {
      for (int t = 0; t < 7; t++) {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: LiveAnimationPreviewWidget(
                  transitionStyle: t,
                  ambientStyle: t % 7,
                  ambientDepth: 8,
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.byType(LiveAnimationPreviewWidget), findsOneWidget);
      }
    });
  });

  group('Domain LightControlNotifier Live RGB & Color State Management', () {
    test('setLiveRgb instantly updates local state and switches to mode 3 with empty segments', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(lightControlProvider.notifier);
      expect(container.read(lightControlProvider).mode, 0);

      notifier.setLiveRgb(255, 30, 30); // Temple Red
      final state = container.read(lightControlProvider);
      expect(state.mode, 3);
      expect(state.r, 255);
      expect(state.g, 30);
      expect(state.b, 30);
      expect(state.segments, isEmpty);
      expect(state.isOn, isTrue);
    });

    test('Color Order Calibration: contracts, models and notifier update', () {
      final pktOrder = LightPacketEncoder.encodeSetColorOrder(1);
      final jsonOrder = jsonDecode(utf8.decode(pktOrder)) as Map<String, dynamic>;
      expect(jsonOrder['cmd'], 'set_color_order');
      expect(jsonOrder['order'], 1);

      final pktHw = LightPacketEncoder.encodeSetHwConfig(leds: 150, maxCurrentMa: 3000, colorOrder: 0);
      final jsonHw = jsonDecode(utf8.decode(pktHw)) as Map<String, dynamic>;
      expect(jsonHw['cmd'], 'set_hw_config');
      expect(jsonHw['color_order'], 0);

      expect(LightState.colorOrderNames.length, 4);
      expect(LightState.colorOrderNames[0], contains('RGB'));
      expect(LightState.colorOrderNames[1], contains('GRB'));

      final dev = PairedDevice(
        id: 'test_dev',
        name: 'Mandir',
        lastSeen: DateTime.now(),
        colorOrder: 0,
      );
      final devJson = dev.toJson();
      expect(devJson['colorOrder'], 0);
      final parsedDev = PairedDevice.fromJson(devJson);
      expect(parsedDev.colorOrder, 0);
      expect(parsedDev.effectiveColorOrder, 0);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(lightControlProvider.notifier);
      expect(container.read(lightControlProvider).colorOrder, 0); // Default RGB
      notifier.setColorOrder(1);
      expect(container.read(lightControlProvider).colorOrder, 1);
    });
  });
}
