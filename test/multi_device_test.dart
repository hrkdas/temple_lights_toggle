import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:temple_lights_toggle/contract/light_contract.dart';
import 'package:temple_lights_toggle/domain/models.dart';

void main() {
  group('Multi-Device BLE Packet Encoders', () {
    test('encodeSetName serializes name payload correctly', () {
      final bytes = LightPacketEncoder.encodeSetName('Puja Room Shrine');
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      expect(json['cmd'], 'set_name');
      expect(json['name'], 'Puja Room Shrine');
    });

    test('encodeResetName serializes reset_name command', () {
      final bytes = LightPacketEncoder.encodeResetName();
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      expect(json['cmd'], 'reset_name');
    });

    test('encodeIdentify serializes identify visual blink command', () {
      final bytes = LightPacketEncoder.encodeIdentify();
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      expect(json['cmd'], 'identify');
    });

    test('encodeSetHwConfig serializes leds and max_ma power budget correctly', () {
      final bytes = LightPacketEncoder.encodeSetHwConfig(leds: 180, maxCurrentMa: 3500);
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      expect(json['cmd'], 'set_hw_config');
      expect(json['leds'], 180);
      expect(json['max_ma'], 3500);
    });

    test('encodeSetAnimConfig serializes transition, ambient aura, and depth', () {
      final bytes = LightPacketEncoder.encodeSetAnimConfig(
        transitionStyle: 1,
        ambientStyle: 2,
        depth: 8,
      );
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      expect(json['cmd'], 'set_anim_config');
      expect(json['trans'], 1);
      expect(json['ambient'], 2);
      expect(json['depth'], 8);
    });

    test('encodeHwTest serializes strip alignment test command', () {
      final bytes = LightPacketEncoder.encodeHwTest();
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      expect(json['cmd'], 'hw_test');
    });
  });

  group('PairedDevice Model Multi-Device Support & Backup Backward Compatibility', () {
    final fixedTime = DateTime(2026, 10, 14, 10, 30);

    test('displayName returns customAlias when present, falls back to hardware name', () {
      final devWithAlias = PairedDevice(
        id: 'AA:BB:CC:DD:EE:01',
        name: 'Temple Lights 4A1F',
        lastSeen: fixedTime,
        customAlias: 'Puja Room Altar',
      );
      expect(devWithAlias.displayName, 'Puja Room Altar');

      final devWithoutAlias = PairedDevice(
        id: 'AA:BB:CC:DD:EE:02',
        name: 'Temple Lights B21C',
        lastSeen: fixedTime,
      );
      expect(devWithoutAlias.displayName, 'Temple Lights B21C');

      final devWithBlankAlias = PairedDevice(
        id: 'AA:BB:CC:DD:EE:03',
        name: 'Temple Lights C33D',
        lastSeen: fixedTime,
        customAlias: '   ',
      );
      expect(devWithBlankAlias.displayName, 'Temple Lights C33D');
    });

    test('JSON serialization & deserialization preserves all multi-device cached state', () {
      final original = PairedDevice(
        id: '11:22:33:44:55:66',
        name: 'Temple Lights 9F20',
        lastSeen: fixedTime,
        customAlias: 'Living Room Mandir',
        firmwareVersion: '1.3.0',
        cachedBrightness: 215,
        cachedMode: 2,
        cachedIsOn: true,
        cachedR: 255,
        cachedG: 180,
        cachedB: 40,
        ledCount: 300,
        maxCurrentMa: 5000,
        transitionStyle: 1,
        ambientStyle: 2,
        ambientDepth: 8,
      );

      final json = original.toJson();
      final restored = PairedDevice.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.customAlias, original.customAlias);
      expect(restored.firmwareVersion, original.firmwareVersion);
      expect(restored.cachedBrightness, original.cachedBrightness);
      expect(restored.cachedMode, original.cachedMode);
      expect(restored.cachedIsOn, original.cachedIsOn);
      expect(restored.cachedR, original.cachedR);
      expect(restored.cachedG, original.cachedG);
      expect(restored.cachedB, original.cachedB);
      expect(restored.ledCount, 300);
      expect(restored.maxCurrentMa, 5000);
      expect(restored.transitionStyle, 1);
      expect(restored.ambientStyle, 2);
      expect(restored.ambientDepth, 8);
      expect(restored.effectiveLedCount, 300);
      expect(restored.effectiveMaxCurrentMa, 5000);
      expect(restored.effectiveTransitionStyle, 1);
      expect(restored.effectiveAmbientStyle, 2);
      expect(restored.effectiveAmbientDepth, 8);
      expect(restored.stripLengthMeters, 5.0);
      expect(restored.formattedLength, '5.0m');
      expect(restored.displayName, 'Living Room Mandir');
    });

    test('Backup Restore Backward Compatibility: parses bare-bones legacy JSON without crashing', () {
      // Simulates an older backup where only basic ID and name were persisted
      final legacyJson = {
        'id': 'AA:BB:CC:DD:EE:FF',
        'name': 'Temple Lights',
        'lastSeen': '2026-09-01T12:00:00.000',
      };

      final restored = PairedDevice.fromJson(legacyJson);
      expect(restored.id, 'AA:BB:CC:DD:EE:FF');
      expect(restored.name, 'Temple Lights');
      expect(restored.customAlias, isNull);
      expect(restored.cachedIsOn, isNull);
      expect(restored.ledCount, isNull);
      expect(restored.maxCurrentMa, isNull);
      expect(restored.transitionStyle, isNull);
      expect(restored.ambientStyle, isNull);

      // Verify safe default fallbacks
      expect(restored.displayName, 'Temple Lights');
      expect(restored.effectiveLedCount, 150);
      expect(restored.effectiveMaxCurrentMa, 3000);
      expect(restored.effectiveTransitionStyle, 0);
      expect(restored.effectiveAmbientStyle, 1);
      expect(restored.effectiveAmbientDepth, 6);
      expect(restored.stripLengthMeters, 2.5);
      expect(restored.formattedLength, '2.5m');

      // Verify re-serializing restored legacy device produces valid JSON
      final reSerialized = restored.toJson();
      expect(reSerialized['id'], 'AA:BB:CC:DD:EE:FF');
      expect(reSerialized['name'], 'Temple Lights');
    });

    test('copyWith updates specified fields while preserving existing state', () {
      final dev = PairedDevice(
        id: 'AA:BB:CC:DD:EE:01',
        name: 'Temple Lights 4A1F',
        lastSeen: fixedTime,
        cachedBrightness: 100,
        cachedMode: 1,
        ledCount: 150,
      );

      final updated = dev.copyWith(
        customAlias: 'Meditation Corner',
        cachedBrightness: 255,
        ledCount: 180,
      );

      expect(updated.id, 'AA:BB:CC:DD:EE:01');
      expect(updated.name, 'Temple Lights 4A1F');
      expect(updated.customAlias, 'Meditation Corner');
      expect(updated.displayName, 'Meditation Corner');
      expect(updated.cachedBrightness, 255);
      expect(updated.cachedMode, 1);
      expect(updated.ledCount, 180);
      expect(updated.effectiveLedCount, 180);
      expect(updated.stripLengthMeters, 3.0);
      expect(updated.lastSeen, fixedTime);
    });
  });

  group('LightState Dynamic Sizing, Animation & Power Math', () {
    test('Calculates dynamic meter length and mode names accurately', () {
      // 150 LEDs (2.5m standard)
      const state150 = LightState(ledCount: 150, mode: 0);
      expect(state150.stripLengthMeters, 2.5);
      expect(state150.formattedLength, '2.5m');
      expect(state150.modeName, 'Warm White (All 2.5m)');

      const state150Center = LightState(ledCount: 150, mode: 1);
      expect(state150Center.modeName, 'Warm White (Center 1.5m)');

      // 300 LEDs (5.0m long strip)
      const state300 = LightState(ledCount: 300, mode: 0);
      expect(state300.stripLengthMeters, 5.0);
      expect(state300.formattedLength, '5.0m');
      expect(state300.modeName, 'Warm White (All 5.0m)');

      const state300Center = LightState(ledCount: 300, mode: 1);
      expect(state300Center.modeName, 'Warm White (Center 3.0m)');

      // 60 LEDs (1.0m compact shrine strip)
      const state60 = LightState(ledCount: 60, mode: 2);
      expect(state60.stripLengthMeters, 1.0);
      expect(state60.formattedLength, '1.0m');
      expect(state60.modeName, 'Pure White (All 1.0m)');
    });

    test('Provides human-readable transition and ambient style labels', () {
      const stateDefault = LightState(transitionStyle: 0, ambientStyle: 1);
      expect(stateDefault.transitionStyleName, 'Center-Out Dawn');
      expect(stateDefault.ambientStyleName, 'Gentle Breathing');

      const stateSweepDiya = LightState(transitionStyle: 1, ambientStyle: 2);
      expect(stateSweepDiya.transitionStyleName, 'Sunrise Flow');
      expect(stateSweepDiya.ambientStyleName, 'Diya Candle Flutter');

      const stateFadeSolid = LightState(transitionStyle: 2, ambientStyle: 0);
      expect(stateFadeSolid.transitionStyleName, 'Uniform Smooth Fade');
      expect(stateFadeSolid.ambientStyleName, 'Pure Solid');
    });
  });

  group('LightBleUuids Target Device Filtering with Dynamic Suffixes', () {
    test('Recognizes unique MAC-suffix hardware names', () {
      expect(LightBleUuids.isTargetDevice(name: 'Temple Lights 4A1F'), isTrue);
      expect(LightBleUuids.isTargetDevice(name: 'Temple Lights [E2:59]'), isTrue);
      expect(LightBleUuids.isTargetDevice(name: 'temple lights puja'), isTrue);
      expect(LightBleUuids.isTargetDevice(name: 'Office Soundbar'), isFalse);
    });

    test('Honors custom user name filter', () {
      expect(
        LightBleUuids.isTargetDevice(name: 'Mandir Altar', nameFilter: 'Mandir'),
        isTrue,
      );
      expect(
        LightBleUuids.isTargetDevice(name: 'Living Room Lights', nameFilter: 'Living'),
        isTrue,
      );
      expect(
        LightBleUuids.isTargetDevice(name: 'Kitchen Strip', nameFilter: 'Mandir'),
        isFalse,
      );
    });
  });
}
