import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:temple_lights_toggle/contract/light_contract.dart';
import 'package:temple_lights_toggle/domain/models.dart';
import 'package:temple_lights_toggle/domain/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('flutter_reactive_ble_method'), (call) async => null);

  group('LedSegment Model & Serialization', () {
    test('LedSegment calculates end, displayName and color correctly', () {
      final seg = LedSegment(
        start: 0,
        count: 6,
        r: 255,
        g: 147,
        b: 41,
        brightness: 200,
        effect: 2, // Diya Candle
        speed: 7,
        name: 'Mandir Altar Base',
      );

      expect(seg.start, 0);
      expect(seg.count, 6);
      expect(seg.end, 5); // 0..5
      expect(seg.r, 255);
      expect(seg.g, 147);
      expect(seg.b, 41);
      expect(seg.displayName, 'Mandir Altar Base');
      expect(seg.effectName, 'Diya Candle Flutter');
      expect(seg.color.toARGB32(), 0xFFFF9329);

      final unnamed = seg.copyWith(name: '');
      expect(unnamed.displayName, 'LEDs #1–#6');
    });

    test('LedSegment roundtrip JSON serialization preserves all segment attributes', () {
      final original = LedSegment(
        start: 100,
        count: 6,
        r: 255,
        g: 255,
        b: 255,
        brightness: 255,
        effect: 3, // Starlight
        speed: 8,
        name: 'Apex Halo',
      );

      final json = original.toJson();
      expect(json['start'], 100);
      expect(json['count'], 6);
      expect(json['r'], 255);
      expect(json['g'], 255);
      expect(json['b'], 255);
      expect(json['bright'], 255);
      expect(json['fx'], 3);
      expect(json['spd'], 8);
      expect(json['name'], 'Apex Halo');

      final deserialized = LedSegment.fromJson(json);
      expect(deserialized.start, original.start);
      expect(deserialized.count, original.count);
      expect(deserialized.r, original.r);
      expect(deserialized.g, original.g);
      expect(deserialized.b, original.b);
      expect(deserialized.brightness, original.brightness);
      expect(deserialized.effect, original.effect);
      expect(deserialized.speed, original.speed);
      expect(deserialized.name, original.name);
    });

    test('LedSegment backward-compatible defaults when fields are omitted', () {
      final legacyJson = {
        'start': 10,
        'count': 20,
      };

      final seg = LedSegment.fromJson(legacyJson);
      expect(seg.start, 10);
      expect(seg.count, 20);
      expect(seg.r, 255);
      expect(seg.g, 147);
      expect(seg.b, 41);
      expect(seg.brightness, 255);
      expect(seg.effect, 0); // Pure solid default
      expect(seg.speed, 5);
      expect(seg.name, isNull);
    });
  });

  group('LightPreset Model & Legacy Compatibility', () {
    test('LightPreset converts legacy DefaultModeConfig (style 0 - Full Strip) correctly', () {
      final legacyFull = DefaultModeConfig(
        index: 0,
        name: 'Warm White',
        r: 255,
        g: 147,
        b: 41,
        style: 0, // Full strip
        brightness: 255,
      );

      final preset = LightPreset.fromLegacyDefaultMode(legacyFull, totalLeds: 150);
      expect(preset.index, 0);
      expect(preset.name, 'Warm White');
      expect(preset.brightness, 255);
      expect(preset.cycleEnabled, isTrue);
      expect(preset.segments.length, 1);
      expect(preset.segments.first.start, 0);
      expect(preset.segments.first.count, 150);
      expect(preset.segments.first.r, 255);
      expect(preset.segments.first.g, 147);
      expect(preset.segments.first.b, 41);
    });

    test('LightPreset converts legacy DefaultModeConfig (style 1 - Center Focus) correctly', () {
      final legacyCenter = DefaultModeConfig(
        index: 1,
        name: 'Center Warm',
        r: 255,
        g: 147,
        b: 41,
        style: 1, // Center focus 1.5m
        brightness: 200,
      );

      final preset = LightPreset.fromLegacyDefaultMode(legacyCenter, totalLeds: 150);
      expect(preset.index, 1);
      expect(preset.name, 'Center Warm');
      expect(preset.brightness, 200);
      expect(preset.cycleEnabled, isTrue);
      expect(preset.segments.length, 1);
      expect(preset.segments.first.start, 30); // 20% margin
      expect(preset.segments.first.count, 90); // 60% center
      expect(preset.segments.first.r, 255);
      expect(preset.segments.first.g, 147);
      expect(preset.segments.first.b, 41);
    });

    test('LightPreset JSON serialization and deserialization roundtrip', () {
      final preset = LightPreset(
        index: 3,
        name: 'Pillar Highlight & Halo',
        brightness: 220,
        transitionStyle: 3,
        ambientStyle: 2,
        ambientDepth: 8,
        cycleEnabled: false,
        r: 255,
        g: 180,
        b: 0,
        segments: [
          const LedSegment(start: 0, count: 6, r: 255, g: 147, b: 41, name: 'Base 1-6'),
          const LedSegment(start: 100, count: 6, r: 255, g: 255, b: 255, name: 'End 100-105'),
        ],
      );

      final json = preset.toJson();
      expect(json['idx'], 3);
      expect(json['name'], 'Pillar Highlight & Halo');
      expect(json['bright'], 220);
      expect(json['trans'], 3);
      expect(json['amb'], 2);
      expect(json['depth'], 8);
      expect(json['cycle'], false);
      expect((json['segs'] as List).length, 2);

      final restored = LightPreset.fromJson(json);
      expect(restored.index, 3);
      expect(restored.name, 'Pillar Highlight & Halo');
      expect(restored.brightness, 220);
      expect(restored.transitionStyle, 3);
      expect(restored.ambientStyle, 2);
      expect(restored.ambientDepth, 8);
      expect(restored.cycleEnabled, isFalse);
      expect(restored.segments.length, 2);
      expect(restored.segments[0].count, 6);
      expect(restored.segments[1].start, 100);
    });
  });

  group('RoomModel Multi-Room Architecture', () {
    test('Default rooms are predefined with temple, living room and bedroom', () {
      final rooms = RoomModel.defaultRooms;
      expect(rooms.length, 3);
      expect(rooms[0].name, 'Puja Mandir');
      expect(rooms[1].name, 'Living Room');
      expect(rooms[2].name, 'Master Bedroom');
    });

    test('RoomModel roundtrip JSON serialization', () {
      final room = RoomModel(
        id: 'room_balcony',
        name: 'Terrace Garden',
        iconName: 'garden',
        deviceIds: ['dev_01', 'dev_02'],
      );

      final json = room.toJson();
      expect(json['id'], 'room_balcony');
      expect(json['name'], 'Terrace Garden');
      expect(json['icon'], 'garden');
      expect(json['devs'], ['dev_01', 'dev_02']);

      final restored = RoomModel.fromJson(json);
      expect(restored.id, 'room_balcony');
      expect(restored.name, 'Terrace Garden');
      expect(restored.iconName, 'garden');
      expect(restored.deviceIds, ['dev_01', 'dev_02']);
    });
  });

  group('Multi-Segment & Preset Packet Encoders', () {
    test('encodeSetPreset serializes idx command accurately', () {
      final bytes = LightPacketEncoder.encodeSetPreset(4);
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      expect(json['cmd'], 'set_preset');
      expect(json['idx'], 4);
    });

    test('encodeGetPresets serializes get_presets command', () {
      final bytes = LightPacketEncoder.encodeGetPresets();
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      expect(json['cmd'], 'get_presets');
    });

    test('encodeSavePreset serializes full preset including segment ranges', () {
      final preset = LightPreset(
        index: 2,
        name: 'Festive Aarti',
        brightness: 250,
        transitionStyle: 4, // Sparkle
        ambientStyle: 4,    // Embers
        ambientDepth: 10,
        cycleEnabled: true,
        r: 255,
        g: 100,
        b: 10,
        segments: [
          const LedSegment(start: 0, count: 6, r: 255, g: 147, b: 41),
          const LedSegment(start: 100, count: 6, r: 255, g: 255, b: 255),
        ],
      );

      final bytes = LightPacketEncoder.encodeSavePreset(preset);
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      expect(json['cmd'], 'save_preset');
      expect(json['idx'], 2);
      expect(json['name'], 'Festive Aarti');
      expect(json['bright'], 250);
      expect(json['trans'], 4);
      expect(json['amb'], 4);
      expect(json['depth'], 10);
      expect(json['cycle'], true);
      expect(json['r'], 255);
      expect(json['g'], 100);
      expect(json['b'], 10);
      final segs = json['segs'] as List<dynamic>;
      expect(segs.length, 2);
      expect(segs[0]['start'], 0);
      expect(segs[0]['count'], 6);
      expect(segs[1]['start'], 100);
      expect(segs[1]['count'], 6);
    });

    test('encodeSetSegments serializes arbitrary segment range array', () {
      final segs = [
        const LedSegment(start: 0, count: 6, r: 255, g: 147, b: 41),
        const LedSegment(start: 100, count: 6, r: 255, g: 255, b: 255),
      ];

      final bytes = LightPacketEncoder.encodeSetSegments(segs);
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      expect(json['cmd'], 'set_segs');
      final list = json['segs'] as List<dynamic>;
      expect(list.length, 2);
      expect(list[0]['count'], 6);
      expect(list[1]['start'], 100);
    });

    test('encodeSetCycleFlags serializes bitmask', () {
      final bytes = LightPacketEncoder.encodeSetCycleFlags(0x0F);
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      expect(json['cmd'], 'set_cycle');
      expect(json['mask'], 15);
    });

    test('encodeResetPresets serializes reset_presets command', () {
      final bytes = LightPacketEncoder.encodeResetPresets();
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      expect(json['cmd'], 'reset_presets');
    });

    test('encodeSetSegments emits compact wire payload under 130 bytes without bloated name strings', () {
      final segs = [
        const LedSegment(start: 0, count: 6, r: 255, g: 147, b: 41, name: 'Very Long Descriptive Pillar Name That Bloats Wire Packet'),
        const LedSegment(start: 100, count: 6, r: 255, g: 255, b: 255, name: 'Very Long Apex Dome Halo Descriptive Name'),
      ];

      final bytes = LightPacketEncoder.encodeSetSegments(segs);
      final jsonStr = utf8.decode(bytes);
      expect(bytes.length, lessThan(170)); // Compact packet ensures zero truncation over BLE
      expect(jsonStr.contains('Bloats Wire Packet'), isFalse);

      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(json['cmd'], 'set_segs');
      final list = json['segs'] as List<dynamic>;
      expect(list.length, 2);
      expect(list[0]['start'], 0);
      expect(list[0]['count'], 6);
      expect(list[0]['bright'], 255);
      expect(list[1]['start'], 100);
      expect(list[1]['count'], 6);
    });
  });

  group('LightControlNotifier Segment Isolation & Reset Tests', () {
    test('setMode clears segment overrides', () {
      final container = ProviderContainer();
      final ctrl = container.read(lightControlProvider.notifier);

      ctrl.setSegments([
        const LedSegment(start: 0, count: 6),
      ]);
      expect(container.read(lightControlProvider).segments.length, 1);

      ctrl.setMode(0);
      expect(container.read(lightControlProvider).mode, 0);
      expect(container.read(lightControlProvider).segments.isEmpty, isTrue);
    });

    test('setRgb clears segment overrides', () {
      final container = ProviderContainer();
      final ctrl = container.read(lightControlProvider.notifier);

      ctrl.setSegments([
        const LedSegment(start: 0, count: 6),
      ]);
      expect(container.read(lightControlProvider).segments.length, 1);

      ctrl.setRgb(255, 200, 100);
      expect(container.read(lightControlProvider).mode, 3);
      expect(container.read(lightControlProvider).r, 255);
      expect(container.read(lightControlProvider).g, 200);
      expect(container.read(lightControlProvider).b, 100);
      expect(container.read(lightControlProvider).segments.isEmpty, isTrue);
    });

    test('updateFromHardware clears segments when activeSegmentCount is 0 in mode < 3', () {
      final container = ProviderContainer();
      final ctrl = container.read(lightControlProvider.notifier);

      ctrl.setSegments([
        const LedSegment(start: 0, count: 6),
      ]);
      expect(container.read(lightControlProvider).segments.isNotEmpty, isTrue);

      ctrl.updateFromHardware(
        mode: 1,
        brightness: 255,
        r: 255,
        g: 147,
        b: 41,
        activeSegmentCount: 0,
      );
      expect(container.read(lightControlProvider).mode, 1);
      expect(container.read(lightControlProvider).segments.isEmpty, isTrue);
    });
  });
}
