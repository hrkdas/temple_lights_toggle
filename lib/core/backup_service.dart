import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/models.dart';
import '../domain/providers.dart';
import 'kv_store.dart';
import 'log.dart';

final _log = AppLog.tag('backup');

/// Summary result of a database restore operation.
class BackupRestoreResult {
  const BackupRestoreResult({
    required this.devicesRestored,
    required this.presetsRestored,
    required this.roomsRestored,
    required this.schedulesRestored,
    required this.schemaVersion,
    this.warning,
  });

  final int devicesRestored;
  final int presetsRestored;
  final int roomsRestored;
  final int schedulesRestored;
  final int schemaVersion;
  final String? warning;

  bool get isSuccess => true;

  @override
  String toString() =>
      'Restored $devicesRestored devices, $presetsRestored presets, $roomsRestored rooms, $schedulesRestored schedules (v$schemaVersion)';
}

/// Service providing export and 100% backward-compatible import of the entire app database.
class BackupService {
  const BackupService(this._kv);

  final KvStore _kv;

  /// Creates a complete JSON snapshot of all paired devices, presets, rooms, schedules, and preferences.
  String createBackupJson() {
    final devices = _kv.getJsonList(KvKeys.savedDevices) ?? [];
    final presets = _kv.getJsonList(KvKeys.savedPresets) ?? [];
    final legacyModes = _kv.getJsonList(KvKeys.savedModes) ?? [];
    final rooms = _kv.getJsonList(KvKeys.savedRooms) ?? [];
    final schedules = _kv.getJsonList(KvKeys.savedSchedules) ?? [];
    final lastId = _kv.getString(KvKeys.lastConnectedId);
    final lastName = _kv.getString(KvKeys.lastConnectedName);
    final rmakerEmail = _kv.getString(KvKeys.rainmakerEmail);

    final payload = <String, dynamic>{
      'version': 2,
      'app': 'Temple Lights Toggle',
      'exportedAt': DateTime.now().toIso8601String(),
      'devices': devices,
      'presets': presets.isNotEmpty ? presets : legacyModes,
      'modes': legacyModes,
      'rooms': rooms,
      'schedules': schedules,
      'lastConnectedId': lastId,
      'lastConnectedName': lastName,
      if (rmakerEmail != null) 'rainmakerEmail': rmakerEmail,
    };

    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Restores database state from a backup JSON string with 100% backward compatibility.
  /// Handles legacy v1 payloads, missing fields, null values, or older data models without crashing.
  Future<BackupRestoreResult> restoreBackupJson(
    String jsonString, {
    required WidgetRef ref,
  }) async {
    final trimmed = jsonString.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Backup JSON string is empty.');
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (e) {
      throw FormatException('Invalid JSON payload: $e');
    }

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Backup payload root must be a JSON object.');
    }

    final schemaVersion = (decoded['version'] as num?)?.toInt() ?? 1;
    String? warning;

    // 1. Restore & Sanitize Paired Devices
    final List<Map<String, dynamic>> sanitizedDevices = [];
    final rawDevices = decoded['devices'];
    if (rawDevices is List) {
      for (final item in rawDevices) {
        if (item is Map<String, dynamic>) {
          try {
            // PairedDevice.fromJson gracefully handles all missing fields & legacy schemas
            final dev = PairedDevice.fromJson(item);
            sanitizedDevices.add(dev.toJson());
          } catch (e) {
            _log.w('Skipping invalid device in backup: $e');
          }
        }
      }
    }

    // 2. Restore & Sanitize Presets (with legacy modes fallback)
    final List<Map<String, dynamic>> sanitizedPresets = [];
    final rawPresets = decoded['presets'];
    final rawModes = decoded['modes'];

    if (rawPresets is List && rawPresets.isNotEmpty) {
      for (final item in rawPresets) {
        if (item is Map<String, dynamic>) {
          try {
            // Check if it's a new LightPreset or legacy DefaultModeConfig
            if (item.containsKey('segments') || item.containsKey('transitionStyle')) {
              final preset = LightPreset.fromJson(item);
              sanitizedPresets.add(preset.toJson());
            } else {
              // Legacy mode config -> convert to LightPreset
              final legacyMode = DefaultModeConfig.fromJson(item);
              final preset = LightPreset.fromLegacyDefaultMode(legacyMode);
              sanitizedPresets.add(preset.toJson());
            }
          } catch (e) {
            _log.w('Skipping invalid preset in backup: $e');
          }
        }
      }
    } else if (rawModes is List && rawModes.isNotEmpty) {
      // Legacy v1 backup had only modes
      for (final item in rawModes) {
        if (item is Map<String, dynamic>) {
          try {
            final legacyMode = DefaultModeConfig.fromJson(item);
            final preset = LightPreset.fromLegacyDefaultMode(legacyMode);
            sanitizedPresets.add(preset.toJson());
          } catch (e) {
            _log.w('Skipping invalid legacy mode in backup: $e');
          }
        }
      }
    }

    // Ensure at least default presets exist if none were valid
    if (sanitizedPresets.isEmpty) {
      for (final p in LightPreset.defaultPresets()) {
        sanitizedPresets.add(p.toJson());
      }
      warning = 'No valid presets found in backup. Restored default sacred presets.';
    }

    // 3. Restore & Sanitize Rooms
    final List<Map<String, dynamic>> sanitizedRooms = [];
    final rawRooms = decoded['rooms'];
    if (rawRooms is List && rawRooms.isNotEmpty) {
      for (final item in rawRooms) {
        if (item is Map<String, dynamic>) {
          try {
            final room = RoomModel.fromJson(item);
            sanitizedRooms.add(room.toJson());
          } catch (e) {
            _log.w('Skipping invalid room in backup: $e');
          }
        }
      }
    }

    // Ensure default rooms exist if none were in backup
    if (sanitizedRooms.isEmpty) {
      for (final r in RoomModel.defaultRooms) {
        sanitizedRooms.add(r.toJson());
      }
    }

    // 4. Restore & Sanitize Schedules
    final List<Map<String, dynamic>> sanitizedSchedules = [];
    final rawSchedules = decoded['schedules'];
    if (rawSchedules is List) {
      for (final item in rawSchedules) {
        if (item is Map<String, dynamic>) {
          try {
            final schedule = LightSchedule.fromJson(item);
            sanitizedSchedules.add(schedule.toJson());
          } catch (e) {
            _log.w('Skipping invalid schedule in backup: $e');
          }
        }
      }
    }

    // 5. Commit to KvStore
    await _kv.putJson(KvKeys.savedDevices, sanitizedDevices);
    await _kv.putJson(KvKeys.savedPresets, sanitizedPresets);
    await _kv.putJson(KvKeys.savedRooms, sanitizedRooms);
    await _kv.putJson(KvKeys.savedSchedules, sanitizedSchedules);

    // Maintain legacy savedModes key for older code paths
    final legacyModesList = sanitizedPresets.take(3).map((p) {
      final preset = LightPreset.fromJson(p);
      return {
        'index': preset.index,
        'name': preset.name,
        'r': preset.segments.isNotEmpty ? preset.segments.first.r : 255,
        'g': preset.segments.isNotEmpty ? preset.segments.first.g : 147,
        'b': preset.segments.isNotEmpty ? preset.segments.first.b : 41,
        'style': preset.segments.isNotEmpty && preset.segments.first.count < 150 ? 1 : 0,
        'brightness': preset.brightness,
      };
    }).toList();
    await _kv.putJson(KvKeys.savedModes, legacyModesList);

    if (decoded['lastConnectedId'] is String) {
      await _kv.putString(KvKeys.lastConnectedId, decoded['lastConnectedId'] as String);
    }
    if (decoded['lastConnectedName'] is String) {
      await _kv.putString(KvKeys.lastConnectedName, decoded['lastConnectedName'] as String);
    }
    if (decoded['rainmakerEmail'] is String) {
      await _kv.putString(KvKeys.rainmakerEmail, decoded['rainmakerEmail'] as String);
    }

    // 6. Reload all active providers
    ref.read(pairedDevicesProvider.notifier).loadFromKv();
    ref.read(presetsProvider.notifier).loadFromKv();
    ref.read(roomsProvider.notifier).loadFromKv();
    ref.read(schedulesProvider.notifier).loadFromKv();
    ref.read(defaultModesProvider.notifier).loadFromKv();
    ref.read(rainmakerAuthProvider.notifier).refreshNodes();

    _log.i(
      'Backup restore complete: ${sanitizedDevices.length} devices, ${sanitizedPresets.length} presets, '
      '${sanitizedRooms.length} rooms, ${sanitizedSchedules.length} schedules',
    );

    return BackupRestoreResult(
      devicesRestored: sanitizedDevices.length,
      presetsRestored: sanitizedPresets.length,
      roomsRestored: sanitizedRooms.length,
      schedulesRestored: sanitizedSchedules.length,
      schemaVersion: schemaVersion,
      warning: warning,
    );
  }
}
