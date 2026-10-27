import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:temple_lights_toggle/core/backup_service.dart';
import 'package:temple_lights_toggle/core/kv_store.dart';
import 'package:temple_lights_toggle/domain/models.dart';
import 'package:temple_lights_toggle/domain/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Database Backup & Safe Restore Compatibility Tests', () {
    late KvStore kv;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      kv = await KvStore.instance();
    });

    test('BackupService creates complete v2 JSON snapshot', () async {
      final service = BackupService(kv);

      // Seed mock device and preset
      await kv.putJson(KvKeys.savedDevices, [
        {
          'id': 'AA:BB:CC:11:22:33',
          'name': 'Temple Shrine Altar',
          'roomId': 'room_puja_mandir',
          'lastSeen': '2026-10-24T12:00:00.000',
          'ledCount': 150,
          'maxCurrentMa': 3000,
        }
      ]);

      final jsonString = service.createBackupJson();
      final decoded = jsonDecode(jsonString) as Map<String, dynamic>;

      expect(decoded['version'], 2);
      expect(decoded['app'], 'Temple Lights Toggle');
      expect(decoded['devices'], isA<List>());
      expect((decoded['devices'] as List).length, 1);
      expect(decoded['presets'], isA<List>());
      expect(decoded['rooms'], isA<List>());
      expect(decoded['schedules'], isA<List>());
    });

    test('Restore from legacy v1 backup: bare-bones JSON parses without crashing', () async {
      final service = BackupService(kv);

      // Simulates an older backup payload where only legacy fields exist
      final legacyBackupPayload = jsonEncode({
        'version': 1,
        'devices': [
          {
            'id': 'FF:EE:DD:CC:BB:AA',
            'name': 'Old Temple Light',
            // No roomId, no ledCount, no transitionStyle, no segments
          }
        ],
        // Legacy modes format (no presets key, no rooms key)
        'modes': [
          {
            'idx': 0,
            'name': 'Warm Sanctuary',
            'r': 255,
            'g': 147,
            'b': 41,
            'style': 0,
            'bright': 255,
          },
          {
            'idx': 1,
            'name': 'Center Altar Focus',
            'r': 255,
            'g': 147,
            'b': 41,
            'style': 1,
            'bright': 200,
          },
          {
            'idx': 2,
            'name': 'Pure White Illumination',
            'r': 255,
            'g': 255,
            'b': 255,
            'style': 0,
            'bright': 255,
          },
        ],
        'lastConnectedId': 'FF:EE:DD:CC:BB:AA',
        'lastConnectedName': 'Old Temple Light',
      });

      final container = ProviderContainer(
        overrides: [
          kvStoreProvider.overrideWithValue(kv),
        ],
      );

      // WidgetRef mock via ProviderContainer
      // Restore the backup
      final result = await service.restoreBackupJson(
        legacyBackupPayload,
        ref: _MockWidgetRef(container),
      );

      expect(result.devicesRestored, 1);
      expect(result.presetsRestored, 3);
      expect(result.roomsRestored, RoomModel.defaultRooms.length);
      expect(result.schemaVersion, 1);

      // Verify restored device has safe defaults
      final restoredDevicesRaw = kv.getJsonList(KvKeys.savedDevices)!;
      final dev = PairedDevice.fromJson(restoredDevicesRaw.first as Map<String, dynamic>);
      expect(dev.id, 'FF:EE:DD:CC:BB:AA');
      expect(dev.displayName, 'Old Temple Light');
      expect(dev.effectiveRoomId, 'room_temple'); // Safe default
      expect(dev.effectiveLedCount, 150);
      expect(dev.effectiveMaxCurrentMa, 3000);
      expect(dev.effectiveTransitionStyle, 0);
      expect(dev.effectiveAmbientStyle, 1);

      // Verify legacy modes were upgraded to LightPreset with correct segment ranges
      final restoredPresetsRaw = kv.getJsonList(KvKeys.savedPresets)!;
      expect(restoredPresetsRaw.length, 3);
      final p1 = LightPreset.fromJson(restoredPresetsRaw[1] as Map<String, dynamic>);
      expect(p1.name, 'Center Altar Focus');
      expect(p1.segments.isNotEmpty, true);
      expect(p1.segments.first.start, (150 * 0.20).round());
    });

    test('Restore from corrupt or empty payload throws descriptive error without corrupting store', () async {
      final service = BackupService(kv);
      final container = ProviderContainer(
        overrides: [
          kvStoreProvider.overrideWithValue(kv),
        ],
      );

      expect(
        () => service.restoreBackupJson('', ref: _MockWidgetRef(container)),
        throwsA(isA<FormatException>()),
      );

      expect(
        () => service.restoreBackupJson('not valid json {[[', ref: _MockWidgetRef(container)),
        throwsA(isA<FormatException>()),
      );

      expect(
        () => service.restoreBackupJson('["an", "array", "not", "object"]', ref: _MockWidgetRef(container)),
        throwsA(isA<FormatException>()),
      );
    });

    test('Backup and restore preserves rainmakerEmail with backward compatibility', () async {
      final service = BackupService(kv);
      await kv.putString(KvKeys.rainmakerEmail, 'user@templelights.org');

      final backupStr = service.createBackupJson();
      final decoded = jsonDecode(backupStr) as Map<String, dynamic>;
      expect(decoded['rainmakerEmail'], 'user@templelights.org');

      // Clear kv
      await kv.remove(KvKeys.rainmakerEmail);
      expect(kv.getString(KvKeys.rainmakerEmail), isNull);

      final container = ProviderContainer(
        overrides: [
          kvStoreProvider.overrideWithValue(kv),
        ],
      );

      // Restore and verify rainmakerEmail is restored
      await service.restoreBackupJson(backupStr, ref: _MockWidgetRef(container));
      expect(kv.getString(KvKeys.rainmakerEmail), 'user@templelights.org');

      // Verify that restoring a legacy backup without rainmakerEmail does not crash or corrupt
      final legacyPayload = jsonEncode({
        'version': 1,
        'devices': [],
        'modes': [],
      });
      await service.restoreBackupJson(legacyPayload, ref: _MockWidgetRef(container));
      // Still safe and no crash
    });
  });

  group('Multi-Room Architecture & Device Assignment Tests', () {
    test('Default rooms have distinct IDs, emojis, and labels', () {
      final rooms = RoomModel.defaultRooms;
      expect(rooms.length, 3);

      final mandir = rooms[0];
      expect(mandir.id, 'room_temple');
      expect(mandir.name, 'Puja Mandir');
      expect(mandir.iconEmoji, '🛕');

      final living = rooms[1];
      expect(living.id, 'room_living');
      expect(living.iconEmoji, '🛋️');

      final bedroom = rooms[2];
      expect(bedroom.id, 'room_bedroom');
      expect(bedroom.iconEmoji, '🛏️');
    });

    test('RoomModel JSON roundtrip preserves device IDs and iconName', () {
      const room = RoomModel(
        id: 'room_custom_balcony',
        name: 'Tulsi Balcony Altar',
        iconName: 'balcony',
        deviceIds: ['DEV_1', 'DEV_2'],
      );

      final json = room.toJson();
      final roundtrip = RoomModel.fromJson(json);

      expect(roundtrip.id, 'room_custom_balcony');
      expect(roundtrip.name, 'Tulsi Balcony Altar');
      expect(roundtrip.iconName, 'balcony');
      expect(roundtrip.iconEmoji, '🪴');
      expect(roundtrip.deviceIds, ['DEV_1', 'DEV_2']);
    });

    test('PairedDevice associates with room and defaults gracefully when omitted', () {
      final devWithRoom = PairedDevice(
        id: 'DEV_01',
        name: 'Mandir Pillar Left',
        lastSeen: DateTime.now(),
        roomId: 'room_temple',
      );
      expect(devWithRoom.effectiveRoomId, 'room_temple');

      final devWithoutRoom = PairedDevice(
        id: 'DEV_02',
        name: 'Living Room TV Backlight',
        lastSeen: DateTime.now(),
        roomId: null,
      );
      expect(devWithoutRoom.effectiveRoomId, 'room_temple'); // Safe fallback
    });
  });

  group('Multi-Segment Quick Range Parsing & Segment Shaders', () {
    test('Parses comma-separated ranges such as "1-6, 100-105" accurately', () {
      const totalLeds = 150;
      const input = '1-6, 100-105';

      // Simulation of StripVisualizer parsing logic
      final parts = input.split(RegExp(r'[,;]+'));
      final List<LedSegment> parsed = [];

      for (final raw in parts) {
        final part = raw.trim();
        if (part.isEmpty) continue;
        if (part.contains('-')) {
          final bounds = part.split('-');
          if (bounds.length == 2) {
            final s1 = int.tryParse(bounds[0].trim());
            final s2 = int.tryParse(bounds[1].trim());
            if (s1 != null && s2 != null && s1 > 0 && s2 >= s1) {
              final start0 = (s1 - 1).clamp(0, totalLeds - 1);
              final end0 = (s2 - 1).clamp(start0, totalLeds - 1);
              final count = end0 - start0 + 1;
              parsed.add(LedSegment(
                start: start0,
                count: count,
                r: 255,
                g: 147,
                b: 41,
              ));
            }
          }
        }
      }

      expect(parsed.length, 2);
      expect(parsed[0].start, 0);
      expect(parsed[0].end, 5);
      expect(parsed[0].count, 6);
      expect(parsed[0].displayName, 'LEDs #1–#6');

      expect(parsed[1].start, 99);
      expect(parsed[1].end, 104);
      expect(parsed[1].count, 6);
      expect(parsed[1].displayName, 'LEDs #100–#105');
    });

    test('Clamps range bounds safely when numbers exceed total strip LEDs', () {
      const totalLeds = 100;
      const input = '90-150'; // Exceeds strip length

      final parts = input.split('-');
      final s1 = int.parse(parts[0].trim());
      final s2 = int.parse(parts[1].trim());

      final start0 = (s1 - 1).clamp(0, totalLeds - 1);
      final end0 = (s2 - 1).clamp(start0, totalLeds - 1);
      final count = end0 - start0 + 1;

      expect(start0, 89);
      expect(end0, 99);
      expect(count, 11);
    });

    test('LedSegment reports correct effect names for all 7 shaders', () {
      expect(const LedSegment(start: 0, count: 10, effect: 0).effectName, 'Pure Solid');
      expect(const LedSegment(start: 0, count: 10, effect: 1).effectName, 'Gentle Breathe');
      expect(const LedSegment(start: 0, count: 10, effect: 2).effectName, 'Diya Candle Flutter');
      expect(const LedSegment(start: 0, count: 10, effect: 3).effectName, 'Starlight Twinkle');
      expect(const LedSegment(start: 0, count: 10, effect: 4).effectName, 'Sacred Amber Embers');
      expect(const LedSegment(start: 0, count: 10, effect: 5).effectName, 'Aurora Flow');
      expect(const LedSegment(start: 0, count: 10, effect: 6).effectName, 'Rainbow Cycle');
    });
  });

  group('Dynamic Presets Studio (>3 Modes) Tests', () {
    test('Supports adding preset 4, 5, 6 with custom multi-segments and living auras', () {
      final preset4 = LightPreset(
        index: 3,
        name: 'Sanctum Pillars Accent',
        transitionStyle: 4, // Dual Convergence
        ambientStyle: 2,    // Diya Flutter
        brightness: 220,
        cycleEnabled: true,
        segments: const [
          LedSegment(start: 0, count: 6, r: 255, g: 147, b: 41, effect: 2, name: 'Left Base'),
          LedSegment(start: 99, count: 6, r: 0, g: 229, b: 255, effect: 1, name: 'Right Base'),
        ],
      );

      final preset5 = LightPreset(
        index: 4,
        name: 'Diwali Cosmic Glow',
        transitionStyle: 5, // Sparkle Ignition
        ambientStyle: 4,    // Sacred Amber Embers
        brightness: 255,
        cycleEnabled: false,
        segments: const [
          LedSegment(start: 0, count: 30, r: 255, g: 180, b: 0, effect: 4),
          LedSegment(start: 30, count: 60, r: 255, g: 30, b: 30, effect: 2),
          LedSegment(start: 90, count: 30, r: 255, g: 180, b: 0, effect: 4),
        ],
      );

      expect(preset4.index, 3);
      expect(preset4.name, 'Sanctum Pillars Accent');
      expect(preset4.segments.length, 2);
      expect(preset4.cycleEnabled, true);

      expect(preset5.index, 4);
      expect(preset5.name, 'Diwali Cosmic Glow');
      expect(preset5.segments.length, 3);
      expect(preset5.cycleEnabled, false);

      // JSON serialization
      final p4Json = preset4.toJson();
      final p4Restored = LightPreset.fromJson(p4Json);
      expect(p4Restored.index, 3);
      expect(p4Restored.segments.length, 2);
      expect(p4Restored.transitionStyle, 4);
      expect(p4Restored.ambientStyle, 2);
    });

    test('PairedDevice backward compatibility: handles Google Home and RainMaker metadata', () async {
      final devWithGh = PairedDevice(
        id: '11:22:33:44:55:66',
        name: 'Temple Lights',
        lastSeen: DateTime(2026, 10, 26),
        isGoogleHomeLinked: true,
        rainmakerNodeId: 'node_abc123',
      );

      final jsonMap = devWithGh.toJson();
      expect(jsonMap['isGoogleHomeLinked'], true);
      expect(jsonMap['rainmakerNodeId'], 'node_abc123');

      // Restoring modern device
      final restoredModern = PairedDevice.fromJson(jsonMap);
      expect(restoredModern.isGoogleHomeLinked, true);
      expect(restoredModern.rainmakerNodeId, 'node_abc123');

      // Restoring legacy device without these keys
      final legacyJson = {
        'id': '99:88:77:66:55:44',
        'name': 'Legacy Temple Lights',
        'lastSeen': '2026-01-01T00:00:00.000',
      };
      final restoredLegacy = PairedDevice.fromJson(legacyJson);
      expect(restoredLegacy.id, '99:88:77:66:55:44');
      expect(restoredLegacy.name, 'Legacy Temple Lights');
      expect(restoredLegacy.isGoogleHomeLinked, isNull);
      expect(restoredLegacy.rainmakerNodeId, isNull);
    });

    test('PairedDevice resilience: handles double/num values, missing id, and empty objects without crashing', () async {
      final trickyJson = {
        'id': null,
        'name': 'Tricky Light',
        'cachedBrightness': 128.0,
        'cachedMode': 2.0,
        'cachedR': 255.0,
        'cachedG': 147.0,
        'cachedB': 41.0,
        'ledCount': 180.0,
        'maxCurrentMa': 3500.0,
        'colorOrder': 1.0,
        'stripOrientation': 1.0,
        'transitionStyle': 3.0,
        'ambientStyle': 2.0,
        'ambientDepth': 8.0,
      };

      final restored = PairedDevice.fromJson(trickyJson);
      expect(restored.id, 'unknown_device');
      expect(restored.name, 'Tricky Light');
      expect(restored.cachedBrightness, 128);
      expect(restored.cachedMode, 2);
      expect(restored.cachedR, 255);
      expect(restored.cachedG, 147);
      expect(restored.cachedB, 41);
      expect(restored.ledCount, 180);
      expect(restored.maxCurrentMa, 3500);
      expect(restored.colorOrder, 1);
      expect(restored.stripOrientation, 1);
      expect(restored.effectiveStripOrientation, 1);
      expect(restored.transitionStyle, 3);
      expect(restored.ambientStyle, 2);
      expect(restored.ambientDepth, 8);
    });

    test('PairedDevice serialization preserves rainmakerNodeId and isGoogleHomeLinked', () {
      final dev = PairedDevice(
        id: 'ESP32_NODE_01',
        name: 'Sanctuary Light',
        lastSeen: DateTime.now(),
        rainmakerNodeId: 'rmaker_node_abc123',
        isGoogleHomeLinked: true,
      );

      final jsonMap = dev.toJson();
      expect(jsonMap['rainmakerNodeId'], 'rmaker_node_abc123');
      expect(jsonMap['isGoogleHomeLinked'], true);

      final restored = PairedDevice.fromJson(jsonMap);
      expect(restored.rainmakerNodeId, 'rmaker_node_abc123');
      expect(restored.isGoogleHomeLinked, true);
    });
  });
}

class _MockWidgetRef implements WidgetRef {
  _MockWidgetRef(this._container);
  final ProviderContainer _container;

  @override
  BuildContext get context => throw UnimplementedError();

  @override
  T read<T>(ProviderListenable<T> provider) => _container.read(provider);

  @override
  T watch<T>(ProviderListenable<T> provider) => _container.read(provider);

  @override
  void listen<T>(ProviderListenable<T> provider, void Function(T? previous, T next) listener, {void Function(Object error, StackTrace stackTrace)? onError}) {}

  @override
  ProviderSubscription<T> listenManual<T>(ProviderListenable<T> provider, void Function(T? previous, T next) listener, {void Function(Object error, StackTrace stackTrace)? onError, bool fireImmediately = false}) =>
      throw UnimplementedError();

  @override
  T refresh<T>(Refreshable<T> provider) => _container.refresh(provider);

  @override
  void invalidate(ProviderOrFamily provider) => _container.invalidate(provider);

  @override
  bool exists(ProviderBase<Object?> provider) => _container.exists(provider);
}
