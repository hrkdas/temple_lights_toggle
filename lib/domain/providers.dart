import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../contract/light_contract.dart';
import '../contract/ota_constants.dart';
import '../core/haptics.dart';
import '../core/backup_service.dart';
import '../core/kv_store.dart';
import '../core/log.dart';
import '../core/permissions.dart';
import '../transport/ble_client.dart';
import '../transport/ota_chunker.dart';
import '../transport/ota_protocol.dart';
import '../transport/scanner.dart';
import '../services/rainmaker_cloud_service.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'models.dart';

final _log = AppLog.tag('domain');

// ============================================================================
// Singletons & Core Providers
// ============================================================================

final bleClientProvider = Provider<BleClient>((ref) {
  final client = BleClient();
  ref.onDispose(client.dispose);
  return client;
});

final scannerProvider = Provider<BleScanner>((ref) {
  final scanner = BleScanner();
  ref.onDispose(scanner.dispose);
  return scanner;
});

final kvStoreProvider = Provider<KvStore>((ref) {
  final current = KvStore.current;
  if (current != null) return current;
  throw StateError('kvStoreProvider not initialized before runApp()');
});

final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(ref.watch(kvStoreProvider));
});

// ============================================================================
// Light Settings Provider
// ============================================================================

class SettingsNotifier extends StateNotifier<LightSettings> {
  SettingsNotifier(this._kv) : super(const LightSettings()) {
    _load();
  }

  final KvStore _kv;

  void _load() {
    final raw = _kv.getJsonMap('light_settings_v1');
    if (raw != null) {
      state = LightSettings.fromJson(raw);
      _log.i('Settings loaded: autoConnect=${state.autoConnectEnabled}');
    }
  }

  Future<void> update(LightSettings Function(LightSettings current) updater) async {
    state = updater(state);
    await _kv.putJson('light_settings_v1', state.toJson());
    _log.i('Settings saved');
  }

  Future<void> setAutoConnect(bool enabled) =>
      update((s) => s.copyWith(autoConnectEnabled: enabled));

  Future<void> setCustomUuids({String? serviceUuid, String? charUuid}) =>
      update((s) => s.copyWith(
            customServiceUuid: serviceUuid,
            customCharUuid: charUuid,
            clearServiceUuid: serviceUuid == null,
            clearCharUuid: charUuid == null,
          ));

  Future<void> setNameFilter(String filter) =>
      update((s) => s.copyWith(nameFilter: filter));
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, LightSettings>((ref) {
  return SettingsNotifier(ref.watch(kvStoreProvider));
});

// ============================================================================
// Paired Devices History Provider
// ============================================================================

class PairedDevicesNotifier extends StateNotifier<List<PairedDevice>> {
  PairedDevicesNotifier(this._kv) : super(const []) {
    _load();
  }

  final KvStore _kv;

  void _load() {
    final raw = _kv.getJsonList(KvKeys.savedDevices) ?? const [];
    state = raw.whereType<Map<String, dynamic>>().map(PairedDevice.fromJson).toList();
  }

  Future<void> _persist() => _kv.putJson(
        KvKeys.savedDevices,
        state.map((d) => d.toJson()).toList(),
      );

  Future<void> recordDevice({
    required String id,
    required String name,
    String? customAlias,
    String? firmwareVersion,
  }) async {
    final now = DateTime.now();
    final existing = state.firstWhere(
      (d) => d.id == id,
      orElse: () => PairedDevice(id: id, name: name, lastSeen: now),
    );
    existing.name = name;
    existing.lastSeen = now;
    if (customAlias != null && customAlias.trim().isNotEmpty) {
      existing.customAlias = customAlias.trim();
    }
    if (firmwareVersion != null) {
      existing.firmwareVersion = firmwareVersion;
    }

    state = [
      existing,
      ...state.where((d) => d.id != id),
    ];

    await _kv.putString(KvKeys.lastConnectedId, id);
    await _kv.putString(KvKeys.lastConnectedName, existing.displayName);
    await _persist();
  }

  Future<void> updateCustomAlias(String id, String alias) async {
    final trimmed = alias.trim();
    state = [
      for (final d in state)
        if (d.id == id)
          d.copyWith(customAlias: trimmed.isEmpty ? null : trimmed)
        else
          d,
    ];
    await _persist();
  }

  Future<void> upsertDevice(PairedDevice device) async {
    final idx = state.indexWhere((d) => d.id == device.id);
    if (idx >= 0) {
      state = [
        for (int i = 0; i < state.length; i++)
          if (i == idx) device else state[i],
      ];
    } else {
      state = [device, ...state];
    }
    await _persist();
  }

  Future<void> updateCachedState({
    required String id,
    String? name,
    int? brightness,
    int? mode,
    bool? isOn,
    int? r,
    int? g,
    int? b,
    String? firmwareVersion,
    int? ledCount,
    int? maxCurrentMa,
    int? colorOrder,
    int? transitionStyle,
    int? ambientStyle,
    int? ambientDepth,
    String? rainmakerNodeId,
    bool? isGoogleHomeLinked,
  }) async {
    var matched = false;
    state = [
      for (final d in state)
        if (d.id == id) ...[
          (() {
            matched = true;
            return d.copyWith(
              name: name ?? d.name,
              lastSeen: DateTime.now(),
              firmwareVersion: firmwareVersion ?? d.firmwareVersion,
              cachedBrightness: brightness ?? d.cachedBrightness,
              cachedMode: mode ?? d.cachedMode,
              cachedIsOn: isOn ?? d.cachedIsOn,
              cachedR: r ?? d.cachedR,
              cachedG: g ?? d.cachedG,
              cachedB: b ?? d.cachedB,
              ledCount: ledCount ?? d.ledCount,
              maxCurrentMa: maxCurrentMa ?? d.maxCurrentMa,
              colorOrder: colorOrder ?? d.colorOrder,
              transitionStyle: transitionStyle ?? d.transitionStyle,
              ambientStyle: ambientStyle ?? d.ambientStyle,
              ambientDepth: ambientDepth ?? d.ambientDepth,
              rainmakerNodeId: rainmakerNodeId ?? d.rainmakerNodeId,
              isGoogleHomeLinked: isGoogleHomeLinked ?? d.isGoogleHomeLinked,
            );
          })()
        ] else
          d,
    ];
    if (matched) {
      await _persist();
    }
  }

  void loadFromKv() => _load();

  Future<void> updateDeviceRoom(String id, String roomId) async {
    state = [
      for (final d in state)
        if (d.id == id) d.copyWith(roomId: roomId) else d,
    ];
    await _persist();
  }

  Future<void> remove(String id) async {
    state = state.where((d) => d.id != id).toList();
    final lastId = _kv.getString(KvKeys.lastConnectedId);
    if (lastId == id) {
      await _kv.remove(KvKeys.lastConnectedId);
      await _kv.remove(KvKeys.lastConnectedName);
    }
    await _persist();
  }
}

final pairedDevicesProvider =
    StateNotifierProvider<PairedDevicesNotifier, List<PairedDevice>>((ref) {
  return PairedDevicesNotifier(ref.watch(kvStoreProvider));
});

final activeDeviceProvider = Provider<PairedDevice?>((ref) {
  final session = ref.watch(lightSessionProvider);
  final pairedList = ref.watch(pairedDevicesProvider);
  if (session.deviceId == null) return null;
  return pairedList.where((d) => d.id == session.deviceId).firstOrNull ??
      PairedDevice(
        id: session.deviceId!,
        name: session.deviceName ?? 'Temple Lights',
        lastSeen: DateTime.now(),
      );
});

// ============================================================================
// Resilient Long-Range Connection State Machine
// ============================================================================

class LightSessionNotifier extends StateNotifier<ConnState> {
  LightSessionNotifier(this._ref) : super(ConnState.idle) {
    _initTarget();
    _bindClientConnectionStream();
  }

  final Ref _ref;
  StreamSubscription<DeviceConnectionState>? _connSub;
  StreamSubscription<List<ScannedDevice>>? _scanSub;
  Timer? _liveRssiTimer;
  StreamSubscription<List<int>>? _charNotifySub;
  var _sessionEpoch = 0;
  var _disposed = false;
  Timer? _autoConnectDebounce;
  Timer? _persistentReconnectTimer;
  Timer? _periodicTimeSyncTimer;

  BleClient get _client => _ref.read(bleClientProvider);
  BleScanner get _scanner => _ref.read(scannerProvider);
  KvStore get _kv => _ref.read(kvStoreProvider);

  void _initTarget() {
    final lastId = _kv.getString(KvKeys.lastConnectedId);
    final lastName = _kv.getString(KvKeys.lastConnectedName);
    if (lastId != null) {
      state = ConnState(
        phase: ConnPhase.idle,
        deviceId: lastId,
        deviceName: lastName ?? 'Temple Lights',
        isTargetPaired: true,
      );
    }
  }

  void _bindClientConnectionStream() {
    _connSub = _client.connectionStream.listen((update) {
      _log.i('Connection state stream: ${update.name}');
      switch (update) {
        case DeviceConnectionState.connected:
          if (state.phase != ConnPhase.reconnecting) {
            state = state.copyWith(phase: ConnPhase.connected, clearError: true, reconnectAttempt: 0);
            if (state.deviceId != null) {
              _startLiveRssiTracking(state.deviceId!);
            }
          }
        case DeviceConnectionState.connecting:
          if (state.phase != ConnPhase.reconnecting) {
            state = state.copyWith(phase: ConnPhase.connecting);
          }
        case DeviceConnectionState.disconnected:
          _charNotifySub?.cancel();
          _charNotifySub = null;
          if (state.phase == ConnPhase.connected) {
            final devId = state.deviceId ?? _kv.getString(KvKeys.lastConnectedId);
            final devName = state.deviceName ?? _kv.getString(KvKeys.lastConnectedName);
            _handleUnexpectedDisconnect(devId, devName, _sessionEpoch);
          } else if (state.phase != ConnPhase.reconnecting && state.phase != ConnPhase.idle) {
            state = state.copyWith(phase: ConnPhase.disconnected);
          }
        case DeviceConnectionState.disconnecting:
          break;
      }
    });
  }

  Future<void> startAutoDiscovery() async {
    final granted = await BlePermissions.requestAll();
    if (!granted) {
      state = state.copyWith(
        phase: ConnPhase.failed,
        errorMessage: 'Bluetooth permissions were denied.',
      );
      return;
    }
    await scanAndAutoConnect();
  }

  Future<void> scanAndAutoConnect() async {
    if (state.isConnected || state.isConnecting) return;

    final epoch = ++_sessionEpoch;
    final lastId = _kv.getString(KvKeys.lastConnectedId);
    final lastName = _kv.getString(KvKeys.lastConnectedName);

    state = ConnState(
      phase: ConnPhase.scanning,
      deviceId: lastId,
      deviceName: lastName,
      isTargetPaired: lastId != null,
    );

    _log.i('Starting long-range auto-connect scan session (epoch $epoch, paired: ${lastId != null})');

    await _scanSub?.cancel();
    await _scanner.stop();

    final settings = _ref.read(settingsProvider);

    _scanSub = _scanner.stream.listen((devices) {
      if (devices.isEmpty || state.phase != ConnPhase.scanning || epoch != _sessionEpoch) {
        return;
      }

      if (!settings.autoConnectEnabled) return;

      // 1. Last connected device priority
      if (lastId != null) {
        final lastDevice = devices.where((d) => d.id == lastId).firstOrNull;
        if (lastDevice != null) {
          _log.i('Found last auto-connected device ${lastDevice.name} (${lastDevice.id}) — connecting!');
          state = state.copyWith(rssi: lastDevice.rssi);
          _triggerAutoConnect(lastDevice, epoch);
          return;
        }
      }

      // 2. Previously paired devices priority
      final pairedList = _ref.read(pairedDevicesProvider);
      for (final p in pairedList) {
        final pairedDevice = devices.where((d) => d.id == p.id).firstOrNull;
        if (pairedDevice != null) {
          _log.i('Found paired device ${pairedDevice.name} — connecting!');
          state = state.copyWith(rssi: pairedDevice.rssi);
          _triggerAutoConnect(pairedDevice, epoch);
          return;
        }
      }

      // 3. Target Hardware Priority: Temple Lights
      final targetDevice = devices.where((d) => LightBleUuids.isTargetDevice(
            name: d.name,
            serviceUuids: d.serviceUuids.map((u) => u.toString()).toList(),
          )).firstOrNull;

      if (targetDevice != null) {
        _log.i('Target device "${targetDevice.name}" detected — auto-connecting!');
        state = state.copyWith(rssi: targetDevice.rssi);
        _triggerAutoConnect(targetDevice, epoch);
        return;
      }

      // 4. Custom filter match
      if (settings.nameFilter.isNotEmpty) {
        final matched = devices.where((d) =>
            d.name.toLowerCase().contains(settings.nameFilter.toLowerCase())).firstOrNull;
        if (matched != null) {
          _log.i('Found filtered device ${matched.name} — auto-connecting!');
          state = state.copyWith(rssi: matched.rssi);
          _triggerAutoConnect(matched, epoch);
          return;
        }
      }


    });

    try {
      await _scanner.start();
    } catch (e) {
      _log.e('Scanner failed to start: $e');
      state = ConnState(
        phase: ConnPhase.failed,
        errorMessage: 'BLE scan error: $e',
      );
    }
  }

  void _triggerAutoConnect(ScannedDevice device, int epoch) {
    _autoConnectDebounce?.cancel();
    unawaited(connect(device.id, name: device.name, epoch: epoch, rssi: device.rssi));
  }

  Future<void> switchToDevice(String deviceId, {String? name}) async {
    final pairedList = _ref.read(pairedDevicesProvider);
    final targetDevice = pairedList.where((d) => d.id == deviceId).firstOrNull;
    final resolvedName = name ?? targetDevice?.displayName ?? 'Temple Lights';

    // 1. Immediately hydrate UI from cache so switching feels instant
    if (targetDevice != null) {
      _ref.read(lightControlProvider.notifier).hydrateFromCached(targetDevice);
    }

    // 2. Clear volatile per-device buffers
    _ref.read(schedulesProvider.notifier).clearTransientState();
    _ref.read(defaultModesProvider.notifier).clearTransientState();
    _ref.read(logsProvider.notifier).clearTransientState();

    // 3. Update active device in KV storage
    await _kv.putString(KvKeys.lastConnectedId, deviceId);
    await _kv.putString(KvKeys.lastConnectedName, resolvedName);

    // 4. Connect to target device
    await connect(deviceId, name: resolvedName);
  }

  Future<void> connect(String deviceId, {String? name, int? epoch, int? rssi}) async {
    final currentEpoch = epoch ?? ++_sessionEpoch;
    _autoConnectDebounce?.cancel();
    _persistentReconnectTimer?.cancel();
    await _scanner.stop();

    state = ConnState(
      phase: ConnPhase.connecting,
      deviceId: deviceId,
      deviceName: name ?? state.deviceName ?? 'Temple Lights',
      rssi: rssi ?? state.rssi,
      isTargetPaired: true,
      reconnectAttempt: state.reconnectAttempt,
    );

    try {
      await _client.connect(deviceId, name: name);
      if (currentEpoch != _sessionEpoch || _disposed) {
        await _client.disconnect();
        return;
      }
      await _onConnectedSuccess(deviceId, name, rssi);
    } catch (e, st) {
      if (currentEpoch != _sessionEpoch || _disposed) return;
      _log.e('Connect failed: $e', error: e, stack: st);

      final lastId = _kv.getString(KvKeys.lastConnectedId);
      if (lastId != null && lastId == deviceId) {
        _handleUnexpectedDisconnect(deviceId, name ?? state.deviceName, currentEpoch);
      } else {
        state = ConnState(
          phase: ConnPhase.failed,
          deviceId: deviceId,
          deviceName: name,
          errorMessage: e.toString(),
        );
        await AppHaptics.warn();
      }
    }
  }

  Future<void> _onConnectedSuccess(String deviceId, String? name, int? rssi) async {
    final resolvedName = name ?? _client.deviceName ?? 'Temple Lights';
    final settings = _ref.read(settingsProvider);

    await _ref.read(pairedDevicesProvider.notifier).recordDevice(
          id: deviceId,
          name: resolvedName,
        );

    state = ConnState(
      phase: ConnPhase.connected,
      deviceId: deviceId,
      deviceName: resolvedName,
      rssi: rssi ?? state.rssi ?? -65,
      isTargetPaired: true,
      reconnectAttempt: 0,
    );

    await AppHaptics.powerUp();

    // Subscribe to BLE notifications for live updates
    await _charNotifySub?.cancel();
    _charNotifySub = _client.subscribeToCharacteristic(
      serviceUuid: settings.customServiceUuid,
      charUuid: settings.customCharUuid,
    ).listen(
      (data) async {
        if (data.isEmpty) return;

        // 5-byte binary telemetry: [mode, brightness, R, G, B]
        if (data.length == 5) {
          final m = data[0];
          final b = data[1];
          final r = data[2];
          final g = data[3];
          final bl = data[4];
          _ref.read(lightControlProvider.notifier).updateFromHardware(
                mode: m,
                brightness: b,
                r: r,
                g: g,
                b: bl,
              );
          _ref.read(pairedDevicesProvider.notifier).updateCachedState(
                id: deviceId,
                brightness: b,
                mode: m,
                isOn: b > 0,
                r: r,
                g: g,
                b: bl,
              );
          return;
        }

        // JSON string packets
        try {
          final str = utf8.decode(data);
          _log.d('Incoming BLE notification payload: $str');
          if (str.startsWith('{')) {
            final json = jsonDecode(str) as Map<String, dynamic>;
            final type = json['type'] as String?;

            if (type == 'state') {
              final m = json['mode'] as int? ?? 0;
              final b = json['bright'] as int? ?? 255;
              final r = json['r'] as int? ?? 255;
              final g = json['g'] as int? ?? 147;
              final bl = json['b'] as int? ?? 41;
              final ver = json['ver'] as String?;
              final hwName = json['name'] as String?;
              final leds = (json['leds'] as num?)?.toInt();
              final maxMa = (json['max_ma'] as num?)?.toInt();
              final colorOrd = (json['color_order'] as num?)?.toInt();
              final trans = (json['trans'] as num?)?.toInt();
              final amb = (json['amb'] as num?)?.toInt();
              final depth = (json['depth'] as num?)?.toInt();
              final preset = (json['preset'] as num?)?.toInt();
              final segs = (json['segs'] as num?)?.toInt();
              final rmakerNodeId = json['node_id'] as String?;
              _ref.read(lightControlProvider.notifier).updateFromHardware(
                    mode: m,
                    brightness: b,
                    r: r,
                    g: g,
                    b: bl,
                    firmwareVersion: ver,
                    ledCount: leds,
                    maxCurrentMa: maxMa,
                    colorOrder: colorOrd,
                    transitionStyle: trans,
                    ambientStyle: amb,
                    ambientDepth: depth,
                    activePreset: preset,
                    activeSegmentCount: segs,
                    rainmakerNodeId: rmakerNodeId,
                  );
              _ref.read(pairedDevicesProvider.notifier).updateCachedState(
                    id: deviceId,
                    name: hwName,
                    brightness: b,
                    mode: m,
                    isOn: b > 0,
                    r: r,
                    g: g,
                    b: bl,
                    firmwareVersion: ver,
                    ledCount: leds,
                    maxCurrentMa: maxMa,
                    colorOrder: colorOrd,
                    transitionStyle: trans,
                    ambientStyle: amb,
                    ambientDepth: depth,
                    rainmakerNodeId: rmakerNodeId,
                  );
            } else if (type == 'rmaker_info') {
              final nodeId = json['node_id'] as String?;
              if (nodeId != null && nodeId.isNotEmpty) {
                _ref.read(lightControlProvider.notifier).updateFromHardware(
                      mode: _ref.read(lightControlProvider).mode,
                      brightness: _ref.read(lightControlProvider).brightness,
                      r: _ref.read(lightControlProvider).r,
                      g: _ref.read(lightControlProvider).g,
                      b: _ref.read(lightControlProvider).b,
                      rainmakerNodeId: nodeId,
                    );
                _ref.read(pairedDevicesProvider.notifier).updateCachedState(
                      id: deviceId,
                      rainmakerNodeId: nodeId,
                    );
                // Zero-tap auto-binding if authenticated with Espressif Cloud
                final auth = _ref.read(rainmakerAuthProvider);
                if (auth.isLoggedIn && !auth.nodes.contains(nodeId)) {
                  unawaited(_ref.read(rainmakerAuthProvider.notifier).mapActiveDevice(nodeId: nodeId));
                }
              }
            } else if (type == 'ota_ack') {
              _ref.read(otaProgressProvider.notifier).handleOtaAck(json);
            } else if (type == 'time_synced') {
              _log.i('ESP32 confirmed RTC time sync');
            } else if (type == 'mode_cfg' || type == 'modes_end') {
              _ref.read(defaultModesProvider.notifier).handleIncomingModePacket(json);
            } else if (type == 'preset_item' || type == 'presets_end') {
              _ref.read(presetsProvider.notifier).handleIncomingPresetPacket(json);
            } else if (type == 'sched' || type == 'sched_start' || type == 'sched_end') {
              _ref.read(schedulesProvider.notifier).handleIncomingHydration(json);
            } else if (type == 'log') {
              _ref.read(logsProvider.notifier).handleIncomingLog(json);
            } else if (type == 'logs_start') {
              _ref.read(logsProvider.notifier).handleIncomingLogsStart(json['count'] as int? ?? 0);
            } else if (type == 'logs_end') {
              _ref.read(logsProvider.notifier).handleIncomingLogsEnd();
            } else if (type == 'logs_cleared') {
              _ref.read(logsProvider.notifier).handleIncomingLogsCleared();
            } else if (type == 'timer_sync') {
              final active = json['active'] as bool? ?? false;
              final duration = json['duration'] as int? ?? 0;
              final remaining = json['remaining'] as int? ?? 0;
              _ref.read(autoOffTimerProvider.notifier).onHardwareTimerSync(
                    active: active,
                    durationSec: duration,
                    remainingSec: remaining,
                  );
            } else if (type == 'timer_started') {
              final sec = json['sec'] as int? ?? 0;
              final remaining = json['remaining'] as int? ?? sec;
              _ref.read(autoOffTimerProvider.notifier).onHardwareTimerSync(
                    active: true,
                    durationSec: sec,
                    remainingSec: remaining,
                  );
            } else if (type == 'timer_canceled') {
              _ref.read(autoOffTimerProvider.notifier).cancelTimer(dispatchBle: false);
            } else if (type == 'timer_done') {
              _ref.read(autoOffTimerProvider.notifier).onHardwareTimerDone();
            } else if (type == 'wifi_scan_item') {
              _ref.read(wifiProvider.notifier).handleIncomingScanItem(json);
            } else if (type == 'wifi_scan_done') {
              _ref.read(wifiProvider.notifier).handleIncomingScanDone(json);
            } else if (type == 'wifi_status') {
              _ref.read(wifiProvider.notifier).handleIncomingStatus(json);
            } else if (type == 'ntp_synced') {
              _ref.read(wifiProvider.notifier).handleIncomingNtpSynced(json);
            }
          }
        } catch (e) {
          _log.v('Could not decode notification as JSON: $e');
        }
      },
      onError: (e) {
        _log.w('Notification stream error: $e');
      },
    );

    _startPeriodicTimeSync();
    unawaited(_ref.read(lightControlProvider.notifier).onDeviceConnected());
    unawaited(_ref.read(schedulesProvider.notifier).onDeviceConnected());
    unawaited(_ref.read(defaultModesProvider.notifier).onDeviceConnected());
    unawaited(_ref.read(presetsProvider.notifier).onDeviceConnected());
    unawaited(_ref.read(wifiProvider.notifier).requestStatus());
    _startLiveRssiTracking(deviceId);

    // Initial state query
    try {
      await _client.writeWithoutResponse(
        LightPacketEncoder.encodeGetState(),
        serviceUuid: settings.customServiceUuid,
        charUuid: settings.customCharUuid,
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await _client.writeWithoutResponse(
        LightPacketEncoder.encodeGetRmakerInfo(),
        serviceUuid: settings.customServiceUuid,
        charUuid: settings.customCharUuid,
      );
    } catch (_) {}
  }

  Future<void> _handleUnexpectedDisconnect(String? deviceId, String? deviceName, int epoch) async {
    _periodicTimeSyncTimer?.cancel();
    _periodicTimeSyncTimer = null;
    _liveRssiTimer?.cancel();
    _liveRssiTimer = null;
    if (deviceId == null) {
      state = const ConnState(phase: ConnPhase.disconnected);
      return;
    }

    _charNotifySub?.cancel();
    _charNotifySub = null;
    _persistentReconnectTimer?.cancel();
    var attempts = state.reconnectAttempt;

    state = ConnState(
      phase: ConnPhase.reconnecting,
      deviceId: deviceId,
      deviceName: deviceName ?? 'Temple Lights',
      isTargetPaired: true,
      reconnectAttempt: attempts,
      errorMessage: 'Out of range. Auto-reconnecting...',
    );

    await AppHaptics.warn();
    await _client.disconnect();

    _runPersistentReconnectCycle(deviceId, deviceName, epoch);
  }

  void _runPersistentReconnectCycle(String deviceId, String? deviceName, int epoch) async {
    if (_disposed || _sessionEpoch != epoch) return;

    final attempts = state.reconnectAttempt + 1;
    state = state.copyWith(
      phase: ConnPhase.reconnecting,
      reconnectAttempt: attempts,
      errorMessage: 'Searching for lights (Attempt $attempts)...',
    );

    _log.i('Long-range reconnect cycle attempt $attempts for $deviceId');

    try {
      await _client.connect(deviceId, name: deviceName, timeout: const Duration(seconds: 4));
      if (_disposed || _sessionEpoch != epoch) {
        await _client.disconnect();
        return;
      }
      await _onConnectedSuccess(deviceId, deviceName, state.rssi);
      _log.i('Reconnected to lights $deviceId after $attempts attempts!');
      return;
    } catch (e) {
      _log.v('Reconnect attempt $attempts failed: $e');
      await _client.disconnect();
    }

    if (_disposed || _sessionEpoch != epoch) return;

    final delayMs = attempts < 5 ? 1200 : 2500;
    _persistentReconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      _runPersistentReconnectCycle(deviceId, deviceName, epoch);
    });
  }

  Future<void> forgetDevice() async {
    final devId = state.deviceId;
    if (devId != null) {
      await _ref.read(pairedDevicesProvider.notifier).remove(devId);
    }
    await disconnect();
    state = const ConnState(phase: ConnPhase.idle);
  }

  Future<void> disconnect() async {
    _sessionEpoch++;
    _autoConnectDebounce?.cancel();
    _persistentReconnectTimer?.cancel();
    _periodicTimeSyncTimer?.cancel();
    _periodicTimeSyncTimer = null;
    _charNotifySub?.cancel();
    _charNotifySub = null;
    _liveRssiTimer?.cancel();
    _liveRssiTimer = null;
    await _scanner.stop();
    await _client.disconnect();

    final lastId = _kv.getString(KvKeys.lastConnectedId);
    final lastName = _kv.getString(KvKeys.lastConnectedName);

    state = ConnState(
      phase: ConnPhase.disconnected,
      deviceId: lastId,
      deviceName: lastName,
      isTargetPaired: lastId != null,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _sessionEpoch++;
    _autoConnectDebounce?.cancel();
    _persistentReconnectTimer?.cancel();
    _periodicTimeSyncTimer?.cancel();
    _periodicTimeSyncTimer = null;
    _connSub?.cancel();
    _scanSub?.cancel();
    _liveRssiTimer?.cancel();
    _charNotifySub?.cancel();
    super.dispose();
  }

  void _startPeriodicTimeSync() {
    _periodicTimeSyncTimer?.cancel();
    _periodicTimeSyncTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      if (state.isConnected && !_disposed) {
        _log.d('Running periodic background time sync with ESP32');
        unawaited(_ref.read(schedulesProvider.notifier).syncTimeWithDevice());
      }
    });
  }

  void _startLiveRssiTracking(String deviceId) {
    _liveRssiTimer?.cancel();
    unawaited(_scanner.stop());
    _pollLiveRssi(deviceId);
    _liveRssiTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _pollLiveRssi(deviceId);
    });
  }

  Future<void> _pollLiveRssi(String deviceId) async {
    if (!state.isConnected || _disposed || !_client.isConnected) return;
    try {
      final currentRssi = await _client.readRssi();
      if (state.isConnected && !_disposed && currentRssi != state.rssi) {
        state = state.copyWith(rssi: currentRssi);
      }
    } catch (_) {}
  }
}

final lightSessionProvider =
    StateNotifierProvider<LightSessionNotifier, ConnState>((ref) {
  return LightSessionNotifier(ref);
});

// Alias for compatibility
final relaySessionProvider = lightSessionProvider;
final motorSessionProvider = lightSessionProvider;

// ============================================================================
// Light Control Provider (Mode, Brightness, RGB, Power)
// ============================================================================

class LightControlNotifier extends StateNotifier<LightState> {
  LightControlNotifier(this._ref) : super(LightState.idle) {
    _initFromCached();
  }

  final Ref _ref;
  BleClient get _client => _ref.read(bleClientProvider);

  DateTime? _lastLocalInteraction;
  Timer? _throttleTimer;
  int? _pendingBrightness;
  bool _sendInFlight = false;
  bool? _pendingPowerCommand;

  ({int r, int g, int b})? _pendingRgb;
  Timer? _rgbThrottleTimer;
  bool _rgbSendInFlight = false;

  void _initFromCached() {
    try {
      final kv = _ref.read(kvStoreProvider);
      final pairedList = _ref.read(pairedDevicesProvider);
      final lastId = kv.getString(KvKeys.lastConnectedId);
      final active = pairedList.where((d) => d.id == lastId).firstOrNull ?? pairedList.firstOrNull;
      if (active != null) {
        hydrateFromCached(active);
      }
    } catch (_) {
      // In isolated unit tests where kvStoreProvider is not overridden
    }
  }

  void _updateCachedDeviceState({
    bool? isOn,
    int? brightness,
    int? mode,
    int? r,
    int? g,
    int? b,
  }) {
    try {
      String? targetId = _ref.read(bleClientProvider).deviceId;
      if (targetId == null) {
        try {
          targetId = _ref.read(lightSessionProvider).deviceId;
        } catch (_) {}
      }
      if (targetId == null) {
        try {
          targetId = _ref.read(pairedDevicesProvider).firstOrNull?.id;
        } catch (_) {}
      }
      if (targetId != null) {
        unawaited(_ref.read(pairedDevicesProvider.notifier).updateCachedState(
              id: targetId,
              isOn: isOn,
              brightness: brightness,
              mode: mode,
              r: r,
              g: g,
              b: b,
            ));
      }
    } catch (_) {}
  }

  Future<void> onDeviceConnected() async {
    if (_pendingPowerCommand != null) {
      final on = _pendingPowerCommand!;
      _pendingPowerCommand = null;
      _lastLocalInteraction = DateTime.now();
      _log.i('Dispatched queued power command ($on) after BLE link established');
      await setPower(on);
    }
  }

  void startBrightnessDrag() {
    _lastLocalInteraction = DateTime.now();
  }

  void startRgbDrag() {
    _lastLocalInteraction = DateTime.now();
  }

  /// High-rate live color / warmth slider handler:
  /// Updates local state instantly at full screen refresh rate with zero latency.
  /// Throttles BLE radio packets to ~24ms intervals using the fast 4-byte binary packet [0x43, R, G, B].
  void setLiveRgb(int r, int g, int b) {
    final cr = r.clamp(0, 255);
    final cg = g.clamp(0, 255);
    final cb = b.clamp(0, 255);
    _lastLocalInteraction = DateTime.now();
    final nextBright = state.brightness == 0 ? 255 : state.brightness;

    // 1. Update UI state immediately (instant tactile response)
    state = state.copyWith(
      r: cr,
      g: cg,
      b: cb,
      mode: 3,
      segments: const [],
      isOn: true,
      brightness: nextBright,
      lastToggled: _lastLocalInteraction,
    );

    // 2. Queue and throttle BLE transmission
    _pendingRgb = (r: cr, g: cg, b: cb);
    _scheduleFastRgbSend();
  }

  void _scheduleFastRgbSend() {
    if (_rgbThrottleTimer != null && _rgbThrottleTimer!.isActive) return;
    if (_rgbSendInFlight) return;

    final targetVal = _pendingRgb;
    if (targetVal == null) return;
    _pendingRgb = null;
    _rgbSendInFlight = true;

    _dispatchFast(LightPacketEncoder.encodeFastRgb(targetVal.r, targetVal.g, targetVal.b)).whenComplete(() {
      _rgbSendInFlight = false;
      if (_pendingRgb != null) {
        _rgbThrottleTimer = Timer(const Duration(milliseconds: 24), () {
          _scheduleFastRgbSend();
        });
      }
    });

    _rgbThrottleTimer = Timer(const Duration(milliseconds: 24), () {
      if (_pendingRgb != null) {
        _scheduleFastRgbSend();
      }
    });
  }

  /// High-rate live slider handler:
  /// Updates local state instantly at full screen refresh rate with zero latency.
  /// Throttles BLE radio packets to ~25ms intervals using the fast 2-byte binary packet.
  void setLiveBrightness(int val) {
    final b = val.clamp(0, 255);
    _lastLocalInteraction = DateTime.now();

    // 1. Update UI state immediately (instant tactile response)
    state = state.copyWith(
      brightness: b,
      isOn: b > 0,
      lastToggled: _lastLocalInteraction,
    );
    if (b == 0) {
      _ref.read(autoOffTimerProvider.notifier).onLightsSwitchedOff();
    }

    // 2. Queue and throttle BLE transmission
    _pendingBrightness = b;
    _scheduleFastBrightnessSend();
  }

  void _scheduleFastBrightnessSend() {
    if (_throttleTimer != null && _throttleTimer!.isActive) return;
    if (_sendInFlight) return;

    final targetVal = _pendingBrightness;
    if (targetVal == null) return;
    _pendingBrightness = null;
    _sendInFlight = true;

    // Send fast 2-byte binary packet immediately
    _dispatchFast(LightPacketEncoder.encodeFastBrightness(targetVal)).whenComplete(() {
      _sendInFlight = false;
      if (_pendingBrightness != null) {
        _throttleTimer = Timer(const Duration(milliseconds: 24), () {
          _scheduleFastBrightnessSend();
        });
      }
    });

    // Enforce 24ms throttle window
    _throttleTimer = Timer(const Duration(milliseconds: 24), () {
      if (_pendingBrightness != null) {
        _scheduleFastBrightnessSend();
      }
    });
  }

  /// Called when user finishes dragging or taps a preset pill
  Future<void> commitBrightness(int val) async {
    final b = val.clamp(0, 255);
    _pendingBrightness = null;
    _throttleTimer?.cancel();
    _lastLocalInteraction = DateTime.now();

    state = state.copyWith(
      brightness: b,
      isOn: b > 0,
      lastToggled: _lastLocalInteraction,
    );
    if (b == 0) {
      _ref.read(autoOffTimerProvider.notifier).onLightsSwitchedOff();
    }

    await _dispatchFast(LightPacketEncoder.encodeFastBrightness(b));
    // Also dispatch JSON as standard fallback
    await _dispatchPacket(LightPacketEncoder.encodeSetBrightness(b));
    _updateCachedDeviceState(isOn: b > 0, brightness: b);
  }

  /// Backward-compatible alias
  Future<void> setBrightness(int val) => commitBrightness(val);

  /// Toggle power between ON (last brightness) and OFF (brightness 0)
  Future<void> togglePower() async {
    final willTurnOn = state.isOff;
    await setPower(willTurnOn);
  }

  Future<void> setPower(bool on) async {
    _lastLocalInteraction = DateTime.now();
    final client = _ref.read(bleClientProvider);

    if (on) {
      // Switching ON: remember last state, advance to next mode and loop among 0, 1, 2
      final nextMode = state.mode >= 2 ? 0 : state.mode + 1;
      const targetBright = 255;
      state = state.copyWith(mode: nextMode, isOn: true, brightness: targetBright, lastToggled: DateTime.now());
      await AppHaptics.powerUp();
      if (client.isConnected) {
        _pendingPowerCommand = null;
        await _dispatchPacket(LightPacketEncoder.encodeOn());
      } else {
        _pendingPowerCommand = true;
      }
    } else {
      state = state.copyWith(isOn: false, brightness: 0, lastToggled: DateTime.now());
      _ref.read(autoOffTimerProvider.notifier).onLightsSwitchedOff();
      await AppHaptics.toggle(false);
      if (client.isConnected) {
        _pendingPowerCommand = null;
        await _dispatchFast(LightPacketEncoder.encodeFastBrightness(0));
        await _dispatchPacket(LightPacketEncoder.encodeOff());
      } else {
        _pendingPowerCommand = false;
      }
    }

    _updateCachedDeviceState(isOn: on, brightness: on ? 255 : 0);
  }

  /// Switch mode (0=warm all, 1=warm center, 2=white all, 3=custom rgb)
  Future<void> setMode(int mode) async {
    _lastLocalInteraction = DateTime.now();
    final nextBright = state.brightness == 0 ? 255 : state.brightness;
    state = state.copyWith(
      mode: mode,
      segments: const [],
      isOn: true,
      brightness: nextBright,
      lastToggled: DateTime.now(),
    );
    await AppHaptics.selection();
    await _dispatchPacket(LightPacketEncoder.encodeSetMode(mode));
    _updateCachedDeviceState(isOn: true, mode: mode);
  }

  /// Activate modern dynamic preset (with segments & animations)
  Future<void> setPreset(int index) async {
    _lastLocalInteraction = DateTime.now();
    final nextBright = state.brightness == 0 ? 255 : state.brightness;
    state = state.copyWith(
      activePreset: index,
      mode: index < 3 ? index : 3,
      isOn: true,
      brightness: nextBright,
      lastToggled: DateTime.now(),
    );
    await AppHaptics.selection();
    await _dispatchPacket(LightPacketEncoder.encodeSetPreset(index));
  }

  /// Live set arbitrary LED segments on the strip
  Future<void> setSegments(List<LedSegment> segments) async {
    _lastLocalInteraction = DateTime.now();
    final nextBright = state.brightness == 0 ? 255 : state.brightness;
    state = state.copyWith(
      segments: segments,
      mode: 3,
      isOn: true,
      brightness: nextBright,
      lastToggled: DateTime.now(),
    );
    await AppHaptics.selection();
    await _dispatchPacket(LightPacketEncoder.encodeSetSegments(segments));
  }

  /// Configure wall-switch cycle bitmask
  Future<void> setCycleFlags(int bitmask) async {
    state = state.copyWith(cycleFlags: bitmask);
    await _dispatchPacket(LightPacketEncoder.encodeSetCycleFlags(bitmask));
  }

  /// Cycle to next mode
  Future<void> nextMode() async {
    final nextM = (state.mode + 1) % 4;
    await setMode(nextM);
  }

  /// Set custom RGB color (auto-switches to mode 3)
  Future<void> setRgb(int r, int g, int b) async {
    _lastLocalInteraction = DateTime.now();
    _pendingRgb = null;
    _rgbThrottleTimer?.cancel();
    final cr = r.clamp(0, 255);
    final cg = g.clamp(0, 255);
    final cb = b.clamp(0, 255);
    final nextBright = state.brightness == 0 ? 255 : state.brightness;
    state = state.copyWith(
      r: cr,
      g: cg,
      b: cb,
      mode: 3,
      segments: const [],
      isOn: true,
      brightness: nextBright,
      lastToggled: DateTime.now(),
    );
    await AppHaptics.tap();
    await _dispatchFast(LightPacketEncoder.encodeFastRgb(cr, cg, cb));
    await _dispatchPacket(LightPacketEncoder.encodeSetRgb(cr, cg, cb));
  }

  Future<void> setCustomRgb(int r, int g, int b) => setRgb(r, g, b);

  /// Emergency cutoff -> Force OFF
  Future<void> emergencyStop() async {
    _lastLocalInteraction = DateTime.now();
    state = state.copyWith(isOn: false, brightness: 0, lastToggled: DateTime.now());
    _ref.read(autoOffTimerProvider.notifier).onLightsSwitchedOff();
    await AppHaptics.warn();
    if (_client.isConnected) {
      await _dispatchPacket(LightPacketEncoder.encodeOff());
    }
  }

  void updateFromHardware({
    required int mode,
    required int brightness,
    required int r,
    required int g,
    required int b,
    String? firmwareVersion,
    int? ledCount,
    int? maxCurrentMa,
    int? transitionStyle,
    int? ambientStyle,
    int? ambientDepth,
    int? colorOrder,
    int? activePreset,
    int? activeSegmentCount,
    String? rainmakerNodeId,
  }) {
    // If the user recently changed brightness locally (within last 1500ms) or has a pending power command,
    // ignore stale incoming hardware echo to prevent slider jitter or jumping
    final isRecentLocal = _lastLocalInteraction != null &&
        DateTime.now().difference(_lastLocalInteraction!).inMilliseconds < 1500;
    final hasPendingPower = _pendingPowerCommand != null;

    final targetBright = (hasPendingPower || isRecentLocal) ? state.brightness : brightness;
    final isOn = hasPendingPower ? state.isOn : (isRecentLocal ? state.isOn : (targetBright > 0));

    state = state.copyWith(
      mode: mode,
      brightness: targetBright,
      r: r,
      g: g,
      b: b,
      isOn: isOn,
      activePreset: activePreset ?? state.activePreset,
      segments: (activeSegmentCount == 0 && mode < 3) ? const [] : state.segments,
      lastToggled: isRecentLocal ? state.lastToggled : DateTime.now(),
      firmwareVersion: firmwareVersion ?? state.firmwareVersion,
      ledCount: ledCount ?? state.ledCount,
      maxCurrentMa: maxCurrentMa ?? state.maxCurrentMa,
      colorOrder: colorOrder ?? state.colorOrder,
      transitionStyle: transitionStyle ?? state.transitionStyle,
      ambientStyle: ambientStyle ?? state.ambientStyle,
      ambientDepth: ambientDepth ?? state.ambientDepth,
      rainmakerNodeId: rainmakerNodeId ?? state.rainmakerNodeId,
    );
    if (!isOn) {
      _ref.read(autoOffTimerProvider.notifier).onLightsSwitchedOff();
    }
    _log.i('Lights state updated from hardware: mode=$mode, bright=$brightness, leds=${ledCount ?? state.ledCount}, colorOrder=${colorOrder ?? state.colorOrder}, trans=${transitionStyle ?? state.transitionStyle}, amb=${ambientStyle ?? state.ambientStyle}');
  }

  void hydrateFromCached(PairedDevice dev) {
    state = LightState(
      isOn: dev.cachedIsOn ?? (dev.cachedBrightness != null ? dev.cachedBrightness! > 0 : true),
      brightness: dev.cachedBrightness ?? 255,
      mode: dev.cachedMode ?? 0,
      r: dev.cachedR ?? 255,
      g: dev.cachedG ?? 147,
      b: dev.cachedB ?? 41,
      firmwareVersion: dev.firmwareVersion,
      ledCount: dev.effectiveLedCount,
      maxCurrentMa: dev.effectiveMaxCurrentMa,
      colorOrder: dev.effectiveColorOrder,
      transitionStyle: dev.effectiveTransitionStyle,
      ambientStyle: dev.effectiveAmbientStyle,
      ambientDepth: dev.effectiveAmbientDepth,
      rainmakerNodeId: dev.rainmakerNodeId,
    );
  }

  Future<void> setHardwareConfig({required int leds, required int maxCurrentMa, int? colorOrder}) async {
    final client = _ref.read(bleClientProvider);
    final order = colorOrder ?? state.colorOrder;
    state = state.copyWith(ledCount: leds, maxCurrentMa: maxCurrentMa, colorOrder: order);
    if (client.deviceId != null) {
      await _ref.read(pairedDevicesProvider.notifier).updateCachedState(
            id: client.deviceId!,
            ledCount: leds,
            maxCurrentMa: maxCurrentMa,
            colorOrder: order,
          );
    }
    if (!client.isConnected) return;
    final pkt = LightPacketEncoder.encodeSetHwConfig(leds: leds, maxCurrentMa: maxCurrentMa, colorOrder: order);
    try {
      await _dispatchPacket(pkt);
      _log.i('Dispatched set_hw_config leds=$leds max_ma=$maxCurrentMa color_order=$order to ESP32');
    } catch (e) {
      _log.w('Failed to dispatch set_hw_config: $e');
    }
  }

  Future<void> setColorOrder(int order) async {
    final client = _ref.read(bleClientProvider);
    state = state.copyWith(colorOrder: order);
    if (client.deviceId != null) {
      await _ref.read(pairedDevicesProvider.notifier).updateCachedState(
            id: client.deviceId!,
            colorOrder: order,
          );
    }
    if (!client.isConnected) return;
    final pkt = LightPacketEncoder.encodeSetColorOrder(order);
    try {
      await _dispatchPacket(pkt);
      _log.i('Dispatched set_color_order order=$order to ESP32');
    } catch (e) {
      _log.w('Failed to dispatch set_color_order: $e');
    }
  }

  Future<void> setAnimationConfig({
    required int transitionStyle,
    required int ambientStyle,
    int depth = 6,
  }) async {
    final client = _ref.read(bleClientProvider);
    state = state.copyWith(
      transitionStyle: transitionStyle,
      ambientStyle: ambientStyle,
      ambientDepth: depth,
    );
    if (client.deviceId != null) {
      await _ref.read(pairedDevicesProvider.notifier).updateCachedState(
            id: client.deviceId!,
            transitionStyle: transitionStyle,
            ambientStyle: ambientStyle,
            ambientDepth: depth,
          );
    }
    if (!client.isConnected) return;
    final pkt = LightPacketEncoder.encodeSetAnimConfig(
      transitionStyle: transitionStyle,
      ambientStyle: ambientStyle,
      depth: depth,
    );
    try {
      await _dispatchPacket(pkt);
      _log.i('Dispatched set_anim_config trans=$transitionStyle amb=$ambientStyle depth=$depth% to ESP32');
    } catch (e) {
      _log.w('Failed to dispatch set_anim_config: $e');
    }
  }

  Future<void> setAnimConfig({
    int? transitionStyle,
    int? ambientStyle,
    int? ambientDepth,
  }) =>
      setAnimationConfig(
        transitionStyle: transitionStyle ?? state.transitionStyle,
        ambientStyle: ambientStyle ?? state.ambientStyle,
        depth: ambientDepth ?? state.ambientDepth,
      );

  Future<void> triggerHwTest() async {
    final client = _ref.read(bleClientProvider);
    if (!client.isConnected) return;
    final pkt = LightPacketEncoder.encodeHwTest();
    try {
      await _dispatchPacket(pkt);
      _log.i('Dispatched hw_test to ESP32');
    } catch (e) {
      _log.w('Failed to dispatch hw_test: $e');
    }
  }

  Future<void> setDeviceName(String name) async {
    final client = _ref.read(bleClientProvider);
    if (!client.isConnected) return;
    final pkt = LightPacketEncoder.encodeSetName(name);
    try {
      await _dispatchPacket(pkt);
      if (client.deviceId != null) {
        await _ref.read(pairedDevicesProvider.notifier).recordDevice(
              id: client.deviceId!,
              name: name,
              customAlias: name,
            );
      }
      _log.i('Dispatched set_name "$name" to ESP32');
    } catch (e) {
      _log.w('Failed to dispatch set_name: $e');
    }
  }

  Future<void> resetDeviceName() async {
    final client = _ref.read(bleClientProvider);
    if (!client.isConnected) return;
    final pkt = LightPacketEncoder.encodeResetName();
    try {
      await _dispatchPacket(pkt);
      if (client.deviceId != null) {
        await _ref.read(pairedDevicesProvider.notifier).updateCustomAlias(client.deviceId!, '');
      }
      _log.i('Dispatched reset_name to ESP32');
    } catch (e) {
      _log.w('Failed to dispatch reset_name: $e');
    }
  }

  Future<void> identifyDevice() async {
    final client = _ref.read(bleClientProvider);
    if (!client.isConnected) return;
    final pkt = LightPacketEncoder.encodeIdentify();
    try {
      await _dispatchPacket(pkt);
      _log.i('Dispatched identify / blink command to ESP32');
    } catch (e) {
      _log.w('Failed to dispatch identify: $e');
    }
  }

  Future<void> previewAnimation({
    required int transitionStyle,
    required int ambientStyle,
    int depth = 6,
  }) async {
    state = state.copyWith(
      transitionStyle: transitionStyle,
      ambientStyle: ambientStyle,
      ambientDepth: depth,
    );
    if (!_client.isConnected) return;
    final pkt = LightPacketEncoder.encodeAnimPreview(
      transitionStyle: transitionStyle,
      ambientStyle: ambientStyle,
      depth: depth,
    );
    try {
      await _dispatchPacket(pkt);
      _log.i('Dispatched anim_preview trans=$transitionStyle amb=$ambientStyle depth=$depth to ESP32');
    } catch (e) {
      _log.w('Failed to dispatch anim_preview: $e');
    }
  }

  Future<void> _dispatchFast(Uint8List packet) async {
    if (!_client.isConnected) return;
    final settings = _ref.read(settingsProvider);
    try {
      await _client.writeWithoutResponse(
        packet,
        serviceUuid: settings.customServiceUuid,
        charUuid: settings.customCharUuid,
      );
    } catch (e) {
      _log.v('Fast packet dispatch error: $e');
    }
  }

  Future<void> _dispatchPacket(Uint8List packet) async {
    if (!_client.isConnected) {
      _log.d('Cannot send command — BLE not connected');
      return;
    }
    final settings = _ref.read(settingsProvider);
    try {
      await _client.writeWithoutResponse(
        packet,
        serviceUuid: settings.customServiceUuid,
        charUuid: settings.customCharUuid,
      );
    } catch (e) {
      _log.e('Failed to send BLE packet: $e');
    }
  }

  @override
  void dispose() {
    _throttleTimer?.cancel();
    _rgbThrottleTimer?.cancel();
    super.dispose();
  }
}

final lightControlProvider =
    StateNotifierProvider<LightControlNotifier, LightState>((ref) {
  return LightControlNotifier(ref);
});

// Aliases for compatibility
final relayControlProvider = lightControlProvider;
final motorControlProvider = lightControlProvider;

// ============================================================================
// Routine Schedule Provider & Background Engine
// ============================================================================

class ScheduleNotifier extends StateNotifier<List<LightSchedule>> {
  ScheduleNotifier(this._ref) : super(const []) {
    _load();
    _startTimer();
  }

  final Ref _ref;
  Timer? _timer;
  final List<LightSchedule> _incomingSchedulesBuffer = [];
  KvStore get _kv => _ref.read(kvStoreProvider);

  void _load() {
    final raw = _kv.getJsonList(KvKeys.savedSchedules);
    if (raw != null) {
      state = raw
          .whereType<Map<String, dynamic>>()
          .map(LightSchedule.fromJson)
          .toList();
      _log.i('Loaded ${state.length} schedules from local cache');
    } else {
      state = const [];
    }
  }

  void loadFromKv() => _load();

  void clearTransientState() {
    _incomingSchedulesBuffer.clear();
    state = const [];
  }

  Future<void> onDeviceConnected() async {
    await syncTimeWithDevice();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await requestHydrationFromDevice();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await _ref.read(logsProvider.notifier).requestLogsFromDevice();
  }

  Future<void> syncTimeWithDevice() async {
    final client = _ref.read(bleClientProvider);
    if (!client.isConnected) return;
    final settings = _ref.read(settingsProvider);
    final pkt = LightPacketEncoder.encodeTimeSync(DateTime.now());
    try {
      await client.writeWithoutResponse(
        pkt,
        serviceUuid: settings.customServiceUuid,
        charUuid: settings.customCharUuid,
      );
      _log.i('Synced phone local time to ESP32 clock');
    } catch (e) {
      _log.w('Failed to sync time to ESP32: $e');
    }
  }

  Future<void> requestHydrationFromDevice() async {
    final client = _ref.read(bleClientProvider);
    if (!client.isConnected) return;
    _incomingSchedulesBuffer.clear();
    final settings = _ref.read(settingsProvider);
    final pkt = LightPacketEncoder.encodeGetSchedules();
    try {
      await client.writeWithoutResponse(
        pkt,
        serviceUuid: settings.customServiceUuid,
        charUuid: settings.customCharUuid,
      );
      _log.i('Requested schedule hydration from ESP32');
    } catch (e) {
      _log.w('Failed to request hydration from ESP32: $e');
    }
  }

  void handleIncomingHydration(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    if (type == 'sched_start') {
      _incomingSchedulesBuffer.clear();
      _log.d('Starting schedule hydration from ESP32 memory (Count: ${json["count"]})');
    } else if (type == 'sched') {
      final schedule = LightSchedule(
        id: json['id'] as String? ?? 'sched_${DateTime.now().millisecondsSinceEpoch}',
        name: json['name'] as String? ?? 'Temple Schedule',
        isEnabled: json['en'] as bool? ?? true,
        hasTurnOn: json['on_en'] as bool? ?? true,
        turnOnHour: json['on_h'] as int? ?? 18,
        turnOnMinute: json['on_m'] as int? ?? 0,
        hasTurnOff: json['off_en'] as bool? ?? true,
        turnOffHour: json['off_h'] as int? ?? 6,
        turnOffMinute: json['off_m'] as int? ?? 0,
        repeatDays: (json['days'] as List<dynamic>?)?.map((e) => e as int).toList() ?? const [1, 2, 3, 4, 5, 6, 7],
        targetMode: json['tgt_mode'] as int? ?? 0,
        targetBrightness: json['tgt_bright'] as int? ?? 255,
        targetR: json['tgt_r'] as int? ?? 255,
        targetG: json['tgt_g'] as int? ?? 147,
        targetB: json['tgt_b'] as int? ?? 41,
      );

      _incomingSchedulesBuffer.removeWhere((s) => s.id == schedule.id);
      _incomingSchedulesBuffer.add(schedule);
    } else if (type == 'sched_end') {
      state = List<LightSchedule>.from(_incomingSchedulesBuffer);
      _persist();
      _log.i('App hydrated with ${state.length} schedules from ESP32 memory');
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _evaluateSchedules());
  }

  void _evaluateSchedules() {
    final now = DateTime.now();
    var hasUpdates = false;
    final updatedList = <LightSchedule>[];

    for (final schedule in state) {
      final action = schedule.evaluateTrigger(now);
      if (action != null) {
        final key = '${action == ScheduleTriggerAction.turnOn ? "ON" : "OFF"}_${now.year}_${now.month}_${now.day}_${now.hour}_${now.minute}';
        final updatedSchedule = schedule.copyWith(lastTriggeredKey: key);
        updatedList.add(updatedSchedule);
        hasUpdates = true;

        final light = _ref.read(lightControlProvider);
        if (action == ScheduleTriggerAction.turnOn && light.isOff) {
          _log.i('⏰ Schedule "${schedule.name}" triggered: TURNING ON LIGHTS (Mode ${schedule.targetMode})');
          if (schedule.targetMode == 3) {
            _ref.read(lightControlProvider.notifier).setCustomRgb(
                  schedule.targetR,
                  schedule.targetG,
                  schedule.targetB,
                );
          } else {
            _ref.read(lightControlProvider.notifier).setMode(schedule.targetMode);
          }
          _ref.read(lightControlProvider.notifier).setBrightness(schedule.targetBrightness);
        } else if (action == ScheduleTriggerAction.turnOff && !light.isOff) {
          _log.i('⏰ Schedule "${schedule.name}" triggered: TURNING OFF LIGHTS');
          _ref.read(lightControlProvider.notifier).setPower(false);
        }
      } else {
        updatedList.add(schedule);
      }
    }

    if (hasUpdates) {
      state = updatedList;
      _persist();
    }
  }

  Future<void> _persist() async {
    await _kv.putJson(
      KvKeys.savedSchedules,
      state.map((s) => s.toJson()).toList(),
    );
  }

  Future<void> addSchedule(LightSchedule schedule) async {
    state = [...state.where((s) => s.id != schedule.id), schedule];
    await _persist();
    _log.i('Added schedule "${schedule.name}"');
    await _sendScheduleToDevice(schedule);
  }

  Future<void> updateSchedule(LightSchedule schedule) async {
    state = [
      for (final s in state)
        if (s.id == schedule.id) schedule else s,
    ];
    await _persist();
    _log.i('Updated schedule "${schedule.name}"');
    await _sendScheduleToDevice(schedule);
  }

  Future<void> toggleSchedule(String id, bool isEnabled) async {
    state = [
      for (final s in state)
        if (s.id == id) s.copyWith(isEnabled: isEnabled) else s,
    ];
    await _persist();

    final client = _ref.read(bleClientProvider);
    if (client.isConnected) {
      final settings = _ref.read(settingsProvider);
      final pkt = LightPacketEncoder.encodeToggleSchedule(id, isEnabled);
      try {
        await client.writeWithoutResponse(
          pkt,
          serviceUuid: settings.customServiceUuid,
          charUuid: settings.customCharUuid,
        );
      } catch (e) {
        _log.w('Failed to toggle schedule on device: $e');
      }
    }
  }

  Future<void> deleteSchedule(String id) async {
    state = state.where((s) => s.id != id).toList();
    await _persist();
    _log.i('Deleted schedule $id');

    final client = _ref.read(bleClientProvider);
    if (client.isConnected) {
      final settings = _ref.read(settingsProvider);
      final pkt = LightPacketEncoder.encodeDeleteSchedule(id);
      try {
        await client.writeWithoutResponse(
          pkt,
          serviceUuid: settings.customServiceUuid,
          charUuid: settings.customCharUuid,
        );
      } catch (e) {
        _log.w('Failed to delete schedule on device: $e');
      }
    }
  }

  Future<void> _sendScheduleToDevice(LightSchedule schedule) async {
    final client = _ref.read(bleClientProvider);
    if (!client.isConnected) return;
    final settings = _ref.read(settingsProvider);
    final pkt = LightPacketEncoder.encodeSaveSchedule(
      id: schedule.id,
      name: schedule.name,
      isEnabled: schedule.isEnabled,
      hasTurnOn: schedule.hasTurnOn,
      turnOnHour: schedule.turnOnHour,
      turnOnMinute: schedule.turnOnMinute,
      hasTurnOff: schedule.hasTurnOff,
      turnOffHour: schedule.turnOffHour,
      turnOffMinute: schedule.turnOffMinute,
      repeatDays: schedule.repeatDays,
      targetMode: schedule.targetMode,
      targetBrightness: schedule.targetBrightness,
      targetR: schedule.targetR,
      targetG: schedule.targetG,
      targetB: schedule.targetB,
    );
    try {
      await client.writeWithoutResponse(
        pkt,
        serviceUuid: settings.customServiceUuid,
        charUuid: settings.customCharUuid,
      );
      _log.i('Saved schedule "${schedule.name}" to ESP32');
    } catch (err) {
      _log.e('Failed to send schedule to ESP32: $err');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final schedulesProvider =
    StateNotifierProvider<ScheduleNotifier, List<LightSchedule>>((ref) {
  return ScheduleNotifier(ref);
});

// ============================================================================
// Quick Auto Turn-Off Countdown Timer Provider
// ============================================================================

class AutoOffTimerNotifier extends StateNotifier<AutoOffTimerState> {
  AutoOffTimerNotifier(this._ref) : super(AutoOffTimerState.idle) {
    _load();
  }

  final Ref _ref;
  Timer? _ticker;
  KvStore get _kv => _ref.read(kvStoreProvider);

  void _load() {
    final raw = _kv.getJsonMap('auto_off_timer_v1');
    if (raw != null) {
      final savedMinutes = (raw['selectedMinutes'] as int?)?.clamp(1, 720) ?? 15;
      state = AutoOffTimerState(
        selectedMinutes: savedMinutes,
        totalSeconds: savedMinutes * 60,
      );
    }
  }

  Future<void> _persist() async {
    await _kv.putJson('auto_off_timer_v1', state.toJson());
  }

  Future<void> setSelectedMinutes(int minutes) async {
    if (minutes <= 0) return;
    state = state.copyWith(
      selectedMinutes: minutes,
      totalSeconds: state.isRunning ? state.totalSeconds : minutes * 60,
    );
    await _persist();
  }

  Future<void> startQuickTimer() => startTimer(state.selectedMinutes);

  Future<void> startTimer(int minutes) async {
    if (minutes <= 0) return;
    final totalSec = minutes * 60;
    final now = DateTime.now();

    _ticker?.cancel();
    state = state.copyWith(
      isRunning: true,
      selectedMinutes: minutes,
      totalSeconds: totalSec,
      remainingSeconds: totalSec,
      startedAt: now,
      endsAt: now.add(Duration(minutes: minutes)),
    );
    await _persist();

    await AppHaptics.powerUp();

    final light = _ref.read(lightControlProvider);
    if (light.isOff) {
      await _ref.read(lightControlProvider.notifier).setPower(true);
    }

    final client = _ref.read(bleClientProvider);
    if (client.isConnected) {
      final settings = _ref.read(settingsProvider);
      final pkt = LightPacketEncoder.encodeStartTimer(seconds: totalSec);
      try {
        await client.writeWithoutResponse(
          pkt,
          serviceUuid: settings.customServiceUuid,
          charUuid: settings.customCharUuid,
        );
        _log.i('Dispatched auto-off timer ($minutes min / $totalSec s) to ESP32');
      } catch (e) {
        _log.w('Failed to send timer packet to ESP32: $e');
      }
    }

    _startTicker();
  }

  Future<void> cancelTimer({bool dispatchBle = true}) async {
    if (!state.isRunning && state.remainingSeconds == 0) return;

    _ticker?.cancel();
    state = state.copyWith(
      isRunning: false,
      remainingSeconds: 0,
      clearDates: true,
    );

    await AppHaptics.impact();

    if (dispatchBle) {
      final client = _ref.read(bleClientProvider);
      if (client.isConnected) {
        final settings = _ref.read(settingsProvider);
        final pkt = LightPacketEncoder.encodeCancelTimer();
        try {
          await client.writeWithoutResponse(
            pkt,
            serviceUuid: settings.customServiceUuid,
            charUuid: settings.customCharUuid,
          );
          _log.i('Dispatched timer cancel to ESP32');
        } catch (e) {
          _log.w('Failed to send timer cancel to ESP32: $e');
        }
      }
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!state.isRunning) {
        timer.cancel();
        return;
      }

      if (state.remainingSeconds <= 1) {
        timer.cancel();
        _onTimerFinished();
      } else {
        state = state.copyWith(remainingSeconds: state.remainingSeconds - 1);
      }
    });
  }

  Future<void> _onTimerFinished() async {
    state = state.copyWith(
      isRunning: false,
      remainingSeconds: 0,
      clearDates: true,
    );
    _log.i('⏰ Auto turn-off timer reached 0: Turning OFF lights');
    await AppHaptics.warn();

    final light = _ref.read(lightControlProvider);
    if (!light.isOff) {
      await _ref.read(lightControlProvider.notifier).setPower(false);
    }
  }

  void onHardwareTimerDone() {
    _ticker?.cancel();
    state = state.copyWith(
      isRunning: false,
      remainingSeconds: 0,
      clearDates: true,
    );
    _log.i('Received timer_done from hardware');
  }

  void onHardwareTimerSync({
    required bool active,
    required int durationSec,
    required int remainingSec,
  }) {
    if (!active || remainingSec <= 0) {
      if (state.isRunning) {
        _ticker?.cancel();
        state = state.copyWith(isRunning: false, remainingSeconds: 0, clearDates: true);
      }
      return;
    }

    final now = DateTime.now();
    state = state.copyWith(
      isRunning: true,
      totalSeconds: durationSec > 0 ? durationSec : remainingSec,
      remainingSeconds: remainingSec,
      selectedMinutes: durationSec > 0 ? (durationSec ~/ 60) : state.selectedMinutes,
      startedAt: now.subtract(Duration(seconds: durationSec - remainingSec)),
      endsAt: now.add(Duration(seconds: remainingSec)),
    );
    _startTicker();
    _log.i('Synced running timer from ESP32: remaining=$remainingSec s');
  }

  void onLightsSwitchedOff() {
    if (state.isRunning) {
      _ticker?.cancel();
      state = state.copyWith(
        isRunning: false,
        remainingSeconds: 0,
        clearDates: true,
      );
      _log.i('Lights turned off -> Auto-off timer cancelled');
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

final autoOffTimerProvider =
    StateNotifierProvider<AutoOffTimerNotifier, AutoOffTimerState>((ref) {
  return AutoOffTimerNotifier(ref);
});

// ============================================================================
// Activity Logs Provider (ESP32 Persistent Sync)
// ============================================================================

class LogsNotifier extends StateNotifier<List<LightLogEntry>> {
  LogsNotifier(this._ref) : super(const []) {
    _load();
  }

  final Ref _ref;
  final List<LightLogEntry> _incomingLogsBuffer = [];
  KvStore get _kv => _ref.read(kvStoreProvider);

  void _load() {
    final raw = _kv.getJsonList('saved_logs_v1');
    if (raw != null) {
      state = raw
          .whereType<Map<String, dynamic>>()
          .map(LightLogEntry.fromJson)
          .toList();
      _log.i('Loaded ${state.length} activity logs from local storage');
    }
  }

  void clearTransientState() {
    _incomingLogsBuffer.clear();
    state = const [];
  }

  Future<void> _persist() async {
    await _kv.putJson(
      'saved_logs_v1',
      state.map((l) => l.toJson()).toList(),
    );
  }

  Future<void> onDeviceConnected() async {
    await requestLogsFromDevice();
  }

  Future<void> requestLogsFromDevice() async {
    final client = _ref.read(bleClientProvider);
    if (!client.isConnected) return;
    _incomingLogsBuffer.clear();
    final settings = _ref.read(settingsProvider);
    final pkt = Uint8List.fromList(utf8.encode(jsonEncode({'cmd': 'get_logs'})));
    try {
      await client.writeWithoutResponse(
        pkt,
        serviceUuid: settings.customServiceUuid,
        charUuid: settings.customCharUuid,
      );
      _log.i('Requested logs hydration from ESP32');
    } catch (e) {
      _log.w('Failed to request logs from ESP32: $e');
    }
  }

  void handleIncomingLog(Map<String, dynamic> json) {
    final entry = LightLogEntry.fromJson(json);
    _incomingLogsBuffer.removeWhere((l) => l.id == entry.id);
    _incomingLogsBuffer.add(entry);

    final existingIdx = state.indexWhere((l) => l.id == entry.id);
    if (existingIdx != -1) {
      state = [
        for (int i = 0; i < state.length; i++)
          if (i == existingIdx) entry else state[i]
      ];
    } else {
      final updated = [entry, ...state];
      state = updated.take(20).toList();
      _persist();
    }
    _log.i('Live log received: ID=${entry.id}, ON=${entry.isOn}, mode=${entry.mode}');
  }

  void handleIncomingLogsStart(int count) {
    _incomingLogsBuffer.clear();
    _log.d('Starting logs hydration from ESP32 (Count: $count)');
  }

  void handleIncomingLogsEnd() {
    final sorted = List<LightLogEntry>.from(_incomingLogsBuffer)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    state = sorted.take(20).toList();
    _persist();
    _log.i('App hydrated with ${state.length} logs from ESP32 memory');
  }

  void handleIncomingLogsCleared() {
    state = const [];
    _incomingLogsBuffer.clear();
    _persist();
    _log.i('Logs cleared on ESP32 & synced to app');
  }

  Future<void> clearLogs() async {
    state = const [];
    _incomingLogsBuffer.clear();
    await _persist();

    final client = _ref.read(bleClientProvider);
    if (client.isConnected) {
      final settings = _ref.read(settingsProvider);
      final pkt = Uint8List.fromList(utf8.encode(jsonEncode({'cmd': 'clear_logs'})));
      try {
        await client.writeWithoutResponse(
          pkt,
          serviceUuid: settings.customServiceUuid,
          charUuid: settings.customCharUuid,
        );
        _log.i('Sent clear_logs command to ESP32');
      } catch (e) {
        _log.w('Failed to dispatch clear_logs to ESP32: $e');
      }
    }
  }

  Future<void> addLog(LightLogEntry entry) async {
    final updated = [entry, ...state.where((l) => l.id != entry.id)];
    state = updated.take(20).toList();
    await _persist();
  }
}

final logsProvider = StateNotifierProvider<LogsNotifier, List<LightLogEntry>>((ref) {
  return LogsNotifier(ref);
});

// Alias for compatibility
final relayLogsProvider = logsProvider;

// ============================================================================
// Over-The-Air (OTA) Firmware Update Notifier & Provider
// ============================================================================

class OtaNotifier extends StateNotifier<OtaProgressState> {
  OtaNotifier(this._ref) : super(const OtaProgressState());

  final Ref _ref;
  OtaProtocol? _protocol;
  bool _canceled = false;

  void handleOtaAck(Map<String, dynamic> json) {
    // Backwards-compatible stub
  }

  void reset() {
    _canceled = false;
    final currentDevVer = _ref.read(lightControlProvider).firmwareVersion;
    state = OtaProgressState(deviceFirmwareVersion: currentDevVer);
  }

  Future<void> cancelUpdate() async {
    _canceled = true;
    try {
      await _protocol?.sendEnd();
    } catch (_) {}
    await _protocol?.dispose();
    _protocol = null;
    state = state.copyWith(
      phase: OtaPhase.canceled,
      statusMessage: 'Update canceled by user',
    );
    await AppHaptics.light();
  }

  Future<void> startUpdate() async {
    if (state.isInProgress) return;
    _canceled = false;

    final client = _ref.read(bleClientProvider);
    final devVer = _ref.read(lightControlProvider).firmwareVersion;
    final devId = client.deviceId;

    if (!client.isConnected || devId == null) {
      state = state.copyWith(
        phase: OtaPhase.failed,
        errorMessage: 'Temple Lights is not connected. Please connect before updating.',
        statusMessage: 'Connection required',
      );
      await AppHaptics.error();
      return;
    }

    try {
      // 1. Loading asset
      state = state.copyWith(
        phase: OtaPhase.loadingAsset,
        statusMessage: 'Loading bundled firmware...',
        deviceFirmwareVersion: devVer,
        clearError: true,
      );

      final ByteData assetData = await rootBundle.load('assets/firmware/firmware.bin');
      final Uint8List firmwareBytes = assetData.buffer.asUint8List();
      final totalSize = firmwareBytes.length;

      _log.i('Loaded firmware.bin: $totalSize bytes');

      if (_canceled) return;

      // 2. High-speed link configuration & handshake
      state = state.copyWith(
        phase: OtaPhase.preparing,
        totalBytes: totalSize,
        bytesWritten: 0,
        statusMessage: 'Preparing high-speed OTA link...',
      );

      int negotiatedMtu = OtaConstants.fallbackMtu;
      try {
        negotiatedMtu = await client.rawBle.requestMtu(
          deviceId: devId,
          mtu: OtaConstants.targetMtu,
        ).timeout(const Duration(seconds: 4));
        _log.i('OTA negotiated MTU: $negotiatedMtu');
      } catch (e) {
        _log.w('MTU request error: $e');
      }

      try {
        await client.rawBle.requestConnectionPriority(
          deviceId: devId,
          priority: ConnectionPriority.highPerformance,
        );
      } catch (_) {}

      try {
        await client.rawBle.clearGattCache(devId);
        _log.i('GATT cache cleared for $devId');
      } catch (e) {
        _log.w('clearGattCache warning: $e');
      }

      await client.rawBle.discoverAllServices(devId).timeout(OtaConstants.serviceDiscoveryTimeout);
      final discoveredServices = await client.rawBle.getDiscoveredServices(devId);
      final settings = _ref.read(settingsProvider);

      _log.i('Discovered ${discoveredServices.length} GATT services on $devId:');
      for (final s in discoveredServices) {
        final cList = s.characteristics.map((c) => c.id.toString()).join(', ');
        _log.i('  Service ${s.id}: [$cList]');
      }

      final resolved = OtaConstants.resolveOtaUuids(
        discoveredServices: discoveredServices,
        preferredServiceUuid: settings.customServiceUuid ?? LightBleUuids.defaultOtaService,
      );

      if (resolved == null) {
        final serviceSummary = discoveredServices.map((s) {
          final chars = s.characteristics.map((c) => c.id.toString()).join(', ');
          return '${s.id} (chars: [$chars])';
        }).join('; ');

        throw StateError(
          'OTA service IDs could not be matched on connected device ($devId). Available services: [$serviceSummary]',
        );
      }

      _log.i('Matched OTA: ${resolved.sourceDescription}');
      _log.i('  Service: ${resolved.serviceUuid} | Control: ${resolved.controlUuid} | Data: ${resolved.dataUuid} | Status: ${resolved.statusUuid}');

      final int effectiveMtu = negotiatedMtu > 0 ? negotiatedMtu : OtaConstants.fallbackMtu;
      final int attPayload = effectiveMtu - 3;
      final int protocolPayload = attPayload - OtaConstants.chunkHeaderBytes;
      final int chunkPayloadBytes = protocolPayload.clamp(
        OtaConstants.minChunkPayloadBytes,
        OtaConstants.safeMaxChunkPayloadBytes,
      );

      final protocol = OtaProtocol(
        ble: client.rawBle,
        deviceId: devId,
        serviceUuid: resolved.serviceUuid,
        controlUuid: resolved.controlUuid,
        dataUuid: resolved.dataUuid,
        statusUuid: resolved.statusUuid,
        log: (msg) => _log.d(msg),
      );
      _protocol = protocol;

      await protocol.initialize();
      // Settle CCCD descriptor write on ESP32 (matching Boturo Go architecture)
      await Future<void>.delayed(const Duration(milliseconds: 600));

      if (_canceled) return;

      state = state.copyWith(
        statusMessage: 'Initiating ESP32 flash partition...',
      );

      await protocol.sendStart(firmwareSizeBytes: totalSize);
      await Future<void>.delayed(OtaConstants.postStartSettleDelay);

      if (_canceled) return;

      // 3. Streaming chunks with windowed ACK and burst pacing
      state = state.copyWith(
        phase: OtaPhase.transferring,
        statusMessage: 'Transmitting firmware chunks...',
      );

      final startTime = DateTime.now();
      final chunker = OtaChunker(chunkPayloadBytes: chunkPayloadBytes);

      await chunker.transfer(
        firmware: firmwareBytes,
        sendChunk: (chunk) => protocol.sendChunk(
          chunkIndex: chunk.chunkIndex,
          payload: chunk.payload,
        ),
        waitForAck: (chunkIndex) => protocol.waitForAck(chunkIndex: chunkIndex),
        onProgress: (sentBytes, total) {
          final elapsedSec = DateTime.now().difference(startTime).inMilliseconds / 1000.0;
          final speed = elapsedSec > 0 ? (sentBytes / elapsedSec) : 0.0;
          final remainingBytes = total - sentBytes;
          final eta = speed > 0 ? (remainingBytes / speed).ceil() : 0;

          state = state.copyWith(
            bytesWritten: sentBytes,
            speedBytesPerSec: speed,
            etaSeconds: eta,
            statusMessage: 'Transmitting: ${(sentBytes * 100 / total).toStringAsFixed(0)}%',
          );
        },
        onRetry: (chunkIndex, attempt, error) {
          _log.w('OTA retry: chunk $chunkIndex, attempt $attempt ($error)');
        },
      );

      if (_canceled) return;

      // 4. Verifying
      state = state.copyWith(
        phase: OtaPhase.verifying,
        bytesWritten: totalSize,
        statusMessage: 'Verifying firmware partition...',
      );

      await protocol.sendEnd();
      await protocol.waitForDone();

      // 5. Rebooting
      state = state.copyWith(
        phase: OtaPhase.rebooting,
        statusMessage: 'Device is rebooting with new firmware...',
      );

      await AppHaptics.powerUp();
      await Future<void>.delayed(const Duration(seconds: 4));

      // 6. Completed
      state = state.copyWith(
        phase: OtaPhase.completed,
        isCompleted: true,
        statusMessage: 'Update installed successfully!',
      );

      await AppHaptics.success();
    } catch (e) {
      _log.e('OTA process exception: $e');
      final errStr = e.toString();
      String userMessage = 'Update failed: $e';
      if (errStr.contains('Characteristic not found') ||
          errStr.contains('discovered') ||
          errStr.contains('NoSuchElementException')) {
        userMessage =
            'Bluetooth service table on your phone is out-of-sync for $devId. '
            'Please turn Bluetooth OFF in phone settings, wait 3 seconds, turn it back ON, '
            'reconnect and tap Retry.';
      }
      state = state.copyWith(
        phase: OtaPhase.failed,
        errorMessage: userMessage,
        statusMessage: 'Update interrupted',
      );
      await AppHaptics.error();
    } finally {
      await _protocol?.dispose();
      _protocol = null;
    }
  }
}

final otaProgressProvider = StateNotifierProvider<OtaNotifier, OtaProgressState>((ref) {
  return OtaNotifier(ref);
});

// ============================================================================
// Default Boot Modes Provider (Editable 3 Default Modes)
// ============================================================================

class DefaultModesNotifier extends StateNotifier<List<DefaultModeConfig>> {
  DefaultModesNotifier(this._ref) : super(DefaultModeConfig.factoryDefaults) {
    _loadFromCache();
  }

  final Ref _ref;
  final List<DefaultModeConfig> _incomingBuffer = [];
  KvStore get _kv => _ref.read(kvStoreProvider);

  void _loadFromCache() {
    final raw = _kv.getJsonList(KvKeys.savedModes);
    if (raw != null) {
      final list = raw
          .whereType<Map<String, dynamic>>()
          .map(DefaultModeConfig.fromJson)
          .toList();
      if (list.length == 3) {
        state = list;
        _log.i('Loaded 3 default modes from local cache');
        return;
      }
    }
    state = DefaultModeConfig.factoryDefaults;
  }

  void loadFromKv() => _loadFromCache();

  void _persist() {
    unawaited(_kv.putJson(KvKeys.savedModes, state.map((m) => m.toJson()).toList()));
  }

  void clearTransientState() {
    _incomingBuffer.clear();
    state = DefaultModeConfig.factoryDefaults;
  }

  Future<void> onDeviceConnected() async {
    await requestModesFromDevice();
  }

  Future<void> requestModesFromDevice() async {
    final client = _ref.read(bleClientProvider);
    if (!client.isConnected) return;
    final settings = _ref.read(settingsProvider);
    try {
      await client.writeWithoutResponse(
        LightPacketEncoder.encodeGetModes(),
        serviceUuid: settings.customServiceUuid,
        charUuid: settings.customCharUuid,
      );
      _log.i('Requested default modes from ESP32');
    } catch (e) {
      _log.w('Failed to request modes from ESP32: $e');
    }
  }

  void handleIncomingModePacket(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    if (type == 'mode_cfg') {
      final mode = DefaultModeConfig.fromJson(json);
      _incomingBuffer.removeWhere((m) => m.index == mode.index);
      _incomingBuffer.add(mode);
      _incomingBuffer.sort((a, b) => a.index.compareTo(b.index));
    } else if (type == 'modes_end') {
      if (_incomingBuffer.length == 3) {
        state = List<DefaultModeConfig>.from(_incomingBuffer);
        _persist();
        _log.i('Hydrated 3 default modes from ESP32');
      }
      _incomingBuffer.clear();
    }
  }

  Future<void> saveMode(DefaultModeConfig config) async {
    state = [
      for (final m in state)
        if (m.index == config.index) config else m,
    ];
    _persist();

    final client = _ref.read(bleClientProvider);
    if (!client.isConnected) return;
    final settings = _ref.read(settingsProvider);
    try {
      await client.writeWithoutResponse(
        LightPacketEncoder.encodeSaveMode(
          index: config.index,
          name: config.name,
          r: config.r,
          g: config.g,
          b: config.b,
          style: config.style,
          brightness: config.brightness,
        ),
        serviceUuid: settings.customServiceUuid,
        charUuid: settings.customCharUuid,
      );
      _log.i('Saved mode ${config.index} ("${config.name}") to ESP32');
    } catch (e) {
      _log.e('Failed to save mode ${config.index} to ESP32: $e');
    }
  }

  Future<void> resetToDefaults() async {
    state = DefaultModeConfig.factoryDefaults;
    _persist();

    final client = _ref.read(bleClientProvider);
    if (!client.isConnected) return;
    final settings = _ref.read(settingsProvider);
    try {
      await client.writeWithoutResponse(
        LightPacketEncoder.encodeResetModes(),
        serviceUuid: settings.customServiceUuid,
        charUuid: settings.customCharUuid,
      );
      _log.i('Reset default modes on ESP32 to factory defaults');
    } catch (e) {
      _log.e('Failed to reset modes on ESP32: $e');
    }
  }

  Future<void> activateMode(int index) async {
    await _ref.read(lightControlProvider.notifier).setMode(index);
    if (index < state.length) {
      await _ref.read(lightControlProvider.notifier).setBrightness(state[index].brightness);
    }
  }

  Future<void> cycleNextMode() async {
    await _ref.read(lightControlProvider.notifier).nextMode();
  }
}

final defaultModesProvider = StateNotifierProvider<DefaultModesNotifier, List<DefaultModeConfig>>((ref) {
  return DefaultModesNotifier(ref);
});

// ============================================================================
// Presets & Multi-Segment Ranges Provider (>3 Modes)
// ============================================================================

class PresetsNotifier extends StateNotifier<List<LightPreset>> {
  PresetsNotifier(this._ref) : super(LightPreset.defaultPresets()) {
    _load();
  }

  final Ref _ref;
  KvStore get _kv => _ref.read(kvStoreProvider);

  void _load() {
    final raw = _kv.getJsonList(KvKeys.savedPresets);
    if (raw != null && raw.isNotEmpty) {
      final list = raw.whereType<Map<String, dynamic>>().map(LightPreset.fromJson).toList();
      if (list.isNotEmpty) {
        state = list;
        return;
      }
    }

    // Transparent migration from savedModes if available
    final legacyModes = _kv.getJsonList(KvKeys.savedModes);
    if (legacyModes != null && legacyModes.isNotEmpty) {
      final modes = legacyModes.whereType<Map<String, dynamic>>().map(DefaultModeConfig.fromJson).toList();
      if (modes.isNotEmpty) {
        state = modes.map((m) => LightPreset.fromLegacyDefaultMode(m)).toList();
        _save();
        return;
      }
    }

    state = LightPreset.defaultPresets();
  }

  void loadFromKv() => _load();

  Future<void> _save() async {
    await _kv.putJson(KvKeys.savedPresets, state.map((p) => p.toJson()).toList());
  }

  void clearTransientState() {
    _incomingBuffer.clear();
  }

  Future<void> onDeviceConnected() async {
    final client = _ref.read(bleClientProvider);
    if (!client.isConnected) return;
    final settings = _ref.read(settingsProvider);
    try {
      await client.writeWithoutResponse(
        LightPacketEncoder.encodeGetPresets(),
        serviceUuid: settings.customServiceUuid,
        charUuid: settings.customCharUuid,
      );
    } catch (_) {}
  }

  final List<LightPreset> _incomingBuffer = [];

  void handleIncomingPresetPacket(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    if (type == 'preset_item') {
      final p = LightPreset.fromJson(json);
      _incomingBuffer.removeWhere((item) => item.index == p.index);
      _incomingBuffer.add(p);
    } else if (type == 'presets_end') {
      if (_incomingBuffer.isNotEmpty) {
        _incomingBuffer.sort((a, b) => a.index.compareTo(b.index));
        state = List<LightPreset>.from(_incomingBuffer);
        _incomingBuffer.clear();
        _save();
      }
    }
  }

  Future<void> savePreset(LightPreset preset) async {
    final existing = List<LightPreset>.from(state);
    final idx = existing.indexWhere((p) => p.index == preset.index);
    if (idx >= 0) {
      existing[idx] = preset;
    } else {
      existing.add(preset);
    }
    existing.sort((a, b) => a.index.compareTo(b.index));
    state = existing;
    await _save();

    final client = _ref.read(bleClientProvider);
    if (!client.isConnected) return;
    final settings = _ref.read(settingsProvider);
    try {
      await client.writeWithoutResponse(
        LightPacketEncoder.encodeSavePreset(preset),
        serviceUuid: settings.customServiceUuid,
        charUuid: settings.customCharUuid,
      );
      _log.i('Saved preset ${preset.index} ("${preset.name}") to ESP32');
    } catch (e) {
      _log.e('Failed to send save_preset to ESP32: $e');
    }
  }

  Future<void> addPreset(LightPreset preset) async {
    final nextIdx = state.isEmpty ? 0 : (state.map((p) => p.index).reduce((a, b) => a > b ? a : b) + 1);
    final p = preset.copyWith(index: nextIdx);
    await savePreset(p);
  }

  Future<void> deletePreset(int index) async {
    if (state.length <= 1) return;
    final existing = List<LightPreset>.from(state)..removeWhere((p) => p.index == index);
    state = existing;
    await _save();
  }

  Future<void> resetToDefaults() async {
    state = LightPreset.defaultPresets();
    await _save();

    final client = _ref.read(bleClientProvider);
    if (!client.isConnected) return;
    final settings = _ref.read(settingsProvider);
    try {
      await client.writeWithoutResponse(
        LightPacketEncoder.encodeResetPresets(),
        serviceUuid: settings.customServiceUuid,
        charUuid: settings.customCharUuid,
      );
      _log.i('Reset presets on ESP32 to factory defaults');
    } catch (e) {
      _log.e('Failed to reset presets on ESP32: $e');
    }
  }

  Future<void> activatePreset(int index) async {
    await _ref.read(lightControlProvider.notifier).setPreset(index);
    final p = state.where((item) => item.index == index).firstOrNull;
    if (p != null) {
      await _ref.read(lightControlProvider.notifier).setBrightness(p.brightness);
    }
  }
}

final presetsProvider = StateNotifierProvider<PresetsNotifier, List<LightPreset>>((ref) {
  return PresetsNotifier(ref);
});

// ============================================================================
// Multi-Room Management Provider
// ============================================================================

class RoomsNotifier extends StateNotifier<List<RoomModel>> {
  RoomsNotifier(this._ref) : super(RoomModel.defaultRooms) {
    _load();
  }

  final Ref _ref;
  KvStore get _kv => _ref.read(kvStoreProvider);

  void _load() {
    final raw = _kv.getJsonList(KvKeys.savedRooms);
    if (raw != null && raw.isNotEmpty) {
      final list = raw.whereType<Map<String, dynamic>>().map(RoomModel.fromJson).toList();
      if (list.isNotEmpty) {
        state = list;
        return;
      }
    }
    state = RoomModel.defaultRooms;
  }

  void loadFromKv() => _load();

  Future<void> _save() async {
    await _kv.putJson(KvKeys.savedRooms, state.map((r) => r.toJson()).toList());
  }

  Future<void> addRoom(String name, {String icon = 'temple'}) async {
    final id = 'room_${DateTime.now().millisecondsSinceEpoch}';
    final room = RoomModel(id: id, name: name.trim(), iconName: icon);
    state = [...state, room];
    await _save();
  }

  Future<void> renameRoom(String roomId, String newName) async {
    state = state.map((r) => r.id == roomId ? r.copyWith(name: newName.trim()) : r).toList();
    await _save();
  }

  Future<void> deleteRoom(String roomId) async {
    if (state.length <= 1) return;
    state = state.where((r) => r.id != roomId).toList();
    await _save();
  }

  Future<void> assignDeviceToRoom(String deviceId, String roomId) async {
    state = state.map((r) {
      final devs = List<String>.from(r.deviceIds)..remove(deviceId);
      if (r.id == roomId) {
        devs.add(deviceId);
      }
      return r.copyWith(deviceIds: devs);
    }).toList();
    await _save();

    final pairedList = _ref.read(pairedDevicesProvider);
    final dev = pairedList.where((d) => d.id == deviceId).firstOrNull;
    if (dev != null) {
      await _ref.read(pairedDevicesProvider.notifier).updateDeviceRoom(deviceId, roomId);
    }
  }

  Future<void> toggleRoomPower(String roomId, bool on) => syncRoomPower(roomId, on);

  Future<void> syncRoomPower(String roomId, bool on) async {
    final pairedNotifier = _ref.read(pairedDevicesProvider.notifier);
    final pairedList = _ref.read(pairedDevicesProvider);
    final currentDevice = _ref.read(activeDeviceProvider);

    for (final dev in pairedList) {
      if (roomId == 'all' || dev.effectiveRoomId == roomId) {
        await pairedNotifier.updateCachedState(
          id: dev.id,
          isOn: on,
          brightness: on ? (dev.cachedBrightness ?? 255) : 0,
        );
      }
    }

    if (currentDevice != null && (roomId == 'all' || currentDevice.effectiveRoomId == roomId)) {
      await _ref.read(lightControlProvider.notifier).setPower(on);
    }
  }

  Future<void> syncRoomBrightness(String roomId, int brightness) async {
    final pairedNotifier = _ref.read(pairedDevicesProvider.notifier);
    final pairedList = _ref.read(pairedDevicesProvider);
    final currentDevice = _ref.read(activeDeviceProvider);
    final b = brightness.clamp(0, 255);

    for (final dev in pairedList) {
      if (roomId == 'all' || dev.effectiveRoomId == roomId) {
        await pairedNotifier.updateCachedState(
          id: dev.id,
          brightness: b,
          isOn: b > 0,
        );
      }
    }

    if (currentDevice != null && (roomId == 'all' || currentDevice.effectiveRoomId == roomId)) {
      await _ref.read(lightControlProvider.notifier).commitBrightness(b);
    }
  }

  Future<void> syncRoomScene(String roomId, SacredScene scene) async {
    final pairedNotifier = _ref.read(pairedDevicesProvider.notifier);
    final pairedList = _ref.read(pairedDevicesProvider);
    final currentDevice = _ref.read(activeDeviceProvider);

    for (final dev in pairedList) {
      if (roomId == 'all' || dev.effectiveRoomId == roomId) {
        await pairedNotifier.updateCachedState(
          id: dev.id,
          brightness: scene.brightness,
          isOn: scene.brightness > 0,
          r: scene.r,
          g: scene.g,
          b: scene.b,
          transitionStyle: scene.transitionStyle,
          ambientStyle: scene.ambientStyle,
          ambientDepth: scene.ambientDepth,
        );
      }
    }

    if (currentDevice != null && (roomId == 'all' || currentDevice.effectiveRoomId == roomId)) {
      final ctrl = _ref.read(lightControlProvider.notifier);
      await ctrl.setAnimConfig(
        transitionStyle: scene.transitionStyle,
        ambientStyle: scene.ambientStyle,
        ambientDepth: scene.ambientDepth,
      );
      await ctrl.setRgb(scene.r, scene.g, scene.b);
      await ctrl.commitBrightness(scene.brightness);
    }
  }
}

final sacredScenesProvider = Provider<List<SacredScene>>((ref) {
  return SacredScene.defaultScenes;
});

final roomsProvider = StateNotifierProvider<RoomsNotifier, List<RoomModel>>((ref) {
  return RoomsNotifier(ref);
});

final activeRoomIdProvider = StateProvider<String?>((ref) {
  return null;
});

// ============================================================================
// WiFi Provisioning & Autonomous Network Clock Provider
// ============================================================================

class WifiNotifier extends StateNotifier<WifiConnectionState> {
  WifiNotifier(this._ref) : super(WifiConnectionState.idle);

  final Ref _ref;

  void handleIncomingScanItem(Map<String, dynamic> json) {
    try {
      final item = WifiNetworkItem.fromJson(json);
      if (item.ssid.isEmpty) return;

      final existing = List<WifiNetworkItem>.from(state.scannedNetworks);
      final idx = existing.indexWhere((n) => n.ssid == item.ssid);
      if (idx >= 0) {
        if (item.rssi > existing[idx].rssi) {
          existing[idx] = item;
        }
      } else {
        existing.add(item);
      }
      existing.sort((a, b) => b.rssi.compareTo(a.rssi));
      state = state.copyWith(scannedNetworks: existing);
    } catch (e) {
      _log.w('Failed to parse wifi_scan_item: $e');
    }
  }

  void handleIncomingScanDone(Map<String, dynamic> json) {
    _log.i('WiFi scan complete. Total networks found: ${state.scannedNetworks.length}');
    state = state.copyWith(isScanning: false);
  }

  void handleIncomingStatus(Map<String, dynamic> json) {
    final stateStr = json['state'] as String? ?? 'idle';
    final reasonStr = json['reason'] as String? ?? 'none';
    final ssid = json['ssid'] as String? ?? state.currentSsid;
    final ip = json['ip'] as String? ?? '';
    final rssi = (json['rssi'] as num?)?.toInt() ?? 0;

    WifiPhase phase = WifiPhase.idle;
    switch (stateStr) {
      case 'scanning':
        phase = WifiPhase.scanning;
        break;
      case 'connecting':
        phase = WifiPhase.connecting;
        break;
      case 'got_ip':
        phase = WifiPhase.gotIp;
        break;
      case 'internet_ok':
        phase = WifiPhase.internetOk;
        break;
      case 'saved':
        phase = WifiPhase.saved;
        break;
      case 'connected':
        phase = WifiPhase.connected;
        break;
      case 'failed':
        phase = WifiPhase.failed;
        break;
      case 'disconnected':
        phase = WifiPhase.disconnected;
        break;
      default:
        phase = WifiPhase.idle;
    }

    state = state.copyWith(
      phase: phase,
      currentSsid: ssid,
      ipAddress: ip,
      rssi: rssi,
      failureReason: reasonStr,
      isScanning: phase == WifiPhase.scanning,
    );
    _log.i('WiFi Status updated: $stateStr (reason=$reasonStr, ip=$ip, rssi=$rssi)');
  }

  void handleIncomingNtpSynced(Map<String, dynamic> json) {
    final epoch = (json['epoch'] as num?)?.toInt();
    final tzMin = (json['tz_min'] as num?)?.toInt();
    _log.i('Firmware confirmed NTP sync: epoch=$epoch, tz=$tzMin min');
    state = state.copyWith(
      phase: WifiPhase.connected,
      lastNtpSyncEpoch: epoch,
    );
  }

  Future<void> scanNetworks() async {
    final client = _ref.read(bleClientProvider);
    if (!client.isConnected) return;
    state = state.copyWith(isScanning: true, scannedNetworks: []);
    final settings = _ref.read(settingsProvider);
    final pkt = LightPacketEncoder.encodeWifiScan();
    try {
      await client.writeWithoutResponse(
        pkt,
        serviceUuid: settings.customServiceUuid,
        charUuid: settings.customCharUuid,
      );
      _log.i('Sent wifi_scan command');
    } catch (e) {
      _log.w('Failed to send wifi_scan: $e');
      state = state.copyWith(isScanning: false);
    }
  }

  Future<void> connect({
    required String ssid,
    required String psk,
    bool save = true,
  }) async {
    final client = _ref.read(bleClientProvider);
    if (!client.isConnected) return;
    state = state.copyWith(
      phase: WifiPhase.connecting,
      currentSsid: ssid,
      failureReason: 'none',
    );
    final settings = _ref.read(settingsProvider);
    final pkt = LightPacketEncoder.encodeWifiConnect(
      ssid: ssid,
      psk: psk,
      save: save,
    );
    try {
      await client.writeWithoutResponse(
        pkt,
        serviceUuid: settings.customServiceUuid,
        charUuid: settings.customCharUuid,
      );
      _log.i('Sent wifi_connect command for $ssid');
    } catch (e) {
      _log.w('Failed to send wifi_connect: $e');
      state = state.copyWith(phase: WifiPhase.failed, failureReason: e.toString());
    }
  }

  Future<void> forget() async {
    final client = _ref.read(bleClientProvider);
    if (!client.isConnected) return;
    final settings = _ref.read(settingsProvider);
    final pkt = LightPacketEncoder.encodeWifiForget();
    try {
      await client.writeWithoutResponse(
        pkt,
        serviceUuid: settings.customServiceUuid,
        charUuid: settings.customCharUuid,
      );
      state = WifiConnectionState.idle;
      _log.i('Sent wifi_forget command');
    } catch (e) {
      _log.w('Failed to send wifi_forget: $e');
    }
  }

  Future<void> requestStatus() async {
    final client = _ref.read(bleClientProvider);
    if (!client.isConnected) return;
    final settings = _ref.read(settingsProvider);
    final pkt = LightPacketEncoder.encodeWifiStatus();
    try {
      await client.writeWithoutResponse(
        pkt,
        serviceUuid: settings.customServiceUuid,
        charUuid: settings.customCharUuid,
      );
      _log.i('Sent wifi_status query');
    } catch (e) {
      _log.w('Failed to send wifi_status: $e');
    }
  }

  Future<void> triggerNtpSync() async {
    final client = _ref.read(bleClientProvider);
    if (!client.isConnected) return;
    final settings = _ref.read(settingsProvider);
    final pkt = LightPacketEncoder.encodeTriggerNtp();
    try {
      await client.writeWithoutResponse(
        pkt,
        serviceUuid: settings.customServiceUuid,
        charUuid: settings.customCharUuid,
      );
      _log.i('Sent ntp_sync trigger command');
    } catch (e) {
      _log.w('Failed to send ntp_sync: $e');
    }
  }
}

final wifiProvider = StateNotifierProvider<WifiNotifier, WifiConnectionState>((ref) {
  return WifiNotifier(ref);
});

// ============================================================================
// ESP RainMaker Cloud Authentication & Node Association
// ============================================================================

final rainmakerCloudServiceProvider = Provider<RainmakerCloudService>((ref) {
  return const RainmakerCloudService();
});

class RainmakerAuthState {
  const RainmakerAuthState({
    this.isLoggedIn = false,
    this.email,
    this.userId,
    this.accessToken,
    this.refreshToken,
    this.nodes = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  final bool isLoggedIn;
  final String? email;
  final String? userId;
  final String? accessToken;
  final String? refreshToken;
  final List<String> nodes;
  final bool isLoading;
  final String? errorMessage;

  RainmakerAuthState copyWith({
    bool? isLoggedIn,
    String? email,
    String? userId,
    String? accessToken,
    String? refreshToken,
    List<String>? nodes,
    bool? isLoading,
    String? errorMessage,
  }) =>
      RainmakerAuthState(
        isLoggedIn: isLoggedIn ?? this.isLoggedIn,
        email: email ?? this.email,
        userId: userId ?? this.userId,
        accessToken: accessToken ?? this.accessToken,
        refreshToken: refreshToken ?? this.refreshToken,
        nodes: nodes ?? this.nodes,
        isLoading: isLoading ?? this.isLoading,
        errorMessage: errorMessage,
      );
}

class RainmakerAuthNotifier extends StateNotifier<RainmakerAuthState> {
  RainmakerAuthNotifier(this._ref) : super(const RainmakerAuthState()) {
    _loadFromKv();
  }

  final Ref _ref;

  void _loadFromKv() {
    final kv = _ref.read(kvStoreProvider);
    final email = kv.getString(KvKeys.rainmakerEmail);
    final token = kv.getString(KvKeys.rainmakerAccessToken);
    final refresh = kv.getString(KvKeys.rainmakerRefreshToken);
    final uid = kv.getString(KvKeys.rainmakerUserId);

    if (token != null && token.isNotEmpty) {
      state = RainmakerAuthState(
        isLoggedIn: true,
        email: email ?? 'Google User',
        accessToken: token,
        refreshToken: refresh,
        userId: uid,
      );
      refreshNodes();
    }
  }

  /// Initiates Google Sign-In with Espressif RainMaker using secure ASWebAuthenticationSession / CustomTabs.
  Future<bool> loginWithGoogle() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final authUrl = RainmakerCloudService.getGoogleOAuthUrl().toString();
      final result = await FlutterWebAuth2.authenticate(
        url: authUrl,
        callbackUrlScheme: 'rainmaker',
      );

      final uri = Uri.parse(result);
      final code = uri.queryParameters['code'];
      if (code == null || code.isEmpty) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'No authorization code returned from Google login.',
        );
        return false;
      }

      return await _completeOAuthCodeExchange(code);
    } catch (e) {
      _log.w('Google OAuth sign-in error or cancelled: $e');
      final errStr = e.toString().toLowerCase();
      final isCanceled = errStr.contains('cancel') || errStr.contains('user_canceled');
      state = state.copyWith(
        isLoading: false,
        errorMessage: isCanceled
            ? 'Sign-in canceled or closed in browser.'
            : 'Google sign-in failed: $e',
      );
      return false;
    }
  }

  /// Fallback: Exchanges an OAuth code directly, whether entered as raw code or full callback URL.
  Future<bool> loginWithOAuthCode(String codeOrUrl) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    final code = RainmakerCloudService.extractOAuthCode(codeOrUrl);
    if (code.isEmpty) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Invalid or empty code / redirect URL.',
      );
      return false;
    }
    return await _completeOAuthCodeExchange(code);
  }

  Future<bool> _completeOAuthCodeExchange(String code) async {
    final service = _ref.read(rainmakerCloudServiceProvider);
    final res = await service.exchangeOAuthCode(code);

    if (res.isSuccess && res.accessToken != null) {
      final kv = _ref.read(kvStoreProvider);
      if (res.email != null) {
        await kv.putString(KvKeys.rainmakerEmail, res.email!);
      }
      await kv.putString(KvKeys.rainmakerAccessToken, res.accessToken!);
      if (res.refreshToken != null) {
        await kv.putString(KvKeys.rainmakerRefreshToken, res.refreshToken!);
      }
      if (res.userId != null) {
        await kv.putString(KvKeys.rainmakerUserId, res.userId!);
      }

      state = RainmakerAuthState(
        isLoggedIn: true,
        email: res.email ?? 'Google User',
        accessToken: res.accessToken,
        refreshToken: res.refreshToken,
        userId: res.userId,
        isLoading: false,
      );

      await refreshNodes();

      // Zero-tap Auto-Binding: If an active light is connected with a known nodeId, bind it automatically!
      final activeDev = _ref.read(activeDeviceProvider);
      final light = _ref.read(lightControlProvider);
      final targetNodeId = light.rainmakerNodeId ?? activeDev?.rainmakerNodeId;
      if (targetNodeId != null && targetNodeId.isNotEmpty) {
        await mapActiveDevice(nodeId: targetNodeId);
      }

      return true;
    } else {
      state = state.copyWith(
        isLoading: false,
        errorMessage: res.errorMessage ?? 'Failed to complete Google authentication.',
      );
      return false;
    }
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    final service = _ref.read(rainmakerCloudServiceProvider);
    final res = await service.login(email: email, password: password);

    if (res.isSuccess && res.accessToken != null) {
      final kv = _ref.read(kvStoreProvider);
      await kv.putString(KvKeys.rainmakerEmail, res.email ?? email);
      await kv.putString(KvKeys.rainmakerAccessToken, res.accessToken!);
      if (res.refreshToken != null) {
        await kv.putString(KvKeys.rainmakerRefreshToken, res.refreshToken!);
      }
      if (res.userId != null) {
        await kv.putString(KvKeys.rainmakerUserId, res.userId!);
      }

      state = RainmakerAuthState(
        isLoggedIn: true,
        email: res.email ?? email,
        accessToken: res.accessToken,
        refreshToken: res.refreshToken,
        userId: res.userId,
        isLoading: false,
      );
      await refreshNodes();

      // Zero-tap Auto-Binding: Bind active device if known
      final activeDev = _ref.read(activeDeviceProvider);
      final light = _ref.read(lightControlProvider);
      final targetNodeId = light.rainmakerNodeId ?? activeDev?.rainmakerNodeId;
      if (targetNodeId != null && targetNodeId.isNotEmpty) {
        await mapActiveDevice(nodeId: targetNodeId);
      }

      return true;
    } else {
      state = state.copyWith(
        isLoading: false,
        errorMessage: res.errorMessage ?? 'Failed to authenticate with ESP RainMaker.',
      );
      return false;
    }
  }

  Future<void> logout() async {
    final kv = _ref.read(kvStoreProvider);
    await kv.remove(KvKeys.rainmakerEmail);
    await kv.remove(KvKeys.rainmakerAccessToken);
    await kv.remove(KvKeys.rainmakerRefreshToken);
    await kv.remove(KvKeys.rainmakerUserId);
    state = const RainmakerAuthState();
  }

  Future<void> refreshNodes() async {
    final token = state.accessToken;
    if (token == null || token.isEmpty) return;
    final service = _ref.read(rainmakerCloudServiceProvider);
    var nodes = await service.getUserNodes(accessToken: token);

    // If fetch failed or returned empty and we have a refreshToken, try silent refresh once
    if (nodes.isEmpty && state.refreshToken != null && state.refreshToken!.isNotEmpty) {
      final refreshed = await service.refreshAccessToken(state.refreshToken!);
      if (refreshed.isSuccess && refreshed.accessToken != null) {
        final kv = _ref.read(kvStoreProvider);
        await kv.putString(KvKeys.rainmakerAccessToken, refreshed.accessToken!);
        state = state.copyWith(accessToken: refreshed.accessToken);
        nodes = await service.getUserNodes(accessToken: refreshed.accessToken!);
      }
    }
    state = state.copyWith(nodes: nodes);
  }

  Future<bool> mapActiveDevice({required String nodeId, String? secretKey}) async {
    var token = state.accessToken;
    if (token == null || token.isEmpty) {
      state = state.copyWith(errorMessage: 'Please log in to your Espressif account first.');
      return false;
    }
    final uid = state.userId;
    if (uid == null || uid.isEmpty) {
      state = state.copyWith(errorMessage: 'User ID is missing. Please sign in again.');
      return false;
    }

    state = state.copyWith(isLoading: true, errorMessage: null);
    final service = _ref.read(rainmakerCloudServiceProvider);
    final actualSecretKey = (secretKey != null && secretKey.trim().isNotEmpty)
        ? secretKey.trim()
        : RainmakerCloudService.generateSecretKey();

    // 1. Send rmaker_map_user over BLE to ESP32 node if connected
    final bleClient = _ref.read(bleClientProvider);
    if (bleClient.isConnected) {
      final settings = _ref.read(settingsProvider);
      final pkt = LightPacketEncoder.encodeRmakerMapUser(
        userId: uid,
        secretKey: actualSecretKey,
      );
      try {
        await bleClient.writeWithoutResponse(
          pkt,
          serviceUuid: settings.customServiceUuid,
          charUuid: settings.customCharUuid,
        );
        _log.i('Dispatched rmaker_map_user BLE packet to node (uid: $uid)');
        // Give ESP32 a brief window to push MQTT user mapping packet to AWS IoT
        await Future<void>.delayed(const Duration(milliseconds: 600));
      } catch (e) {
        _log.w('Failed to write rmaker_map_user over BLE: $e');
      }
    }

    // 2. Call RainMaker Cloud PUT /v1/user/nodes/mapping with matching secret key
    var success = await service.mapNodeToUser(
      accessToken: token,
      nodeId: nodeId,
      secretKey: actualSecretKey,
    );

    // If failed and refreshToken exists, try refreshing token once and retrying
    if (!success && state.refreshToken != null && state.refreshToken!.isNotEmpty) {
      final refreshed = await service.refreshAccessToken(state.refreshToken!);
      if (refreshed.isSuccess && refreshed.accessToken != null) {
        token = refreshed.accessToken!;
        final kv = _ref.read(kvStoreProvider);
        await kv.putString(KvKeys.rainmakerAccessToken, token);
        state = state.copyWith(accessToken: token);
        success = await service.mapNodeToUser(
          accessToken: token,
          nodeId: nodeId,
          secretKey: actualSecretKey,
        );
      }
    }

    state = state.copyWith(isLoading: false);
    if (success) {
      await refreshNodes();
      final activeDev = _ref.read(activeDeviceProvider);
      if (activeDev != null) {
        final updated = activeDev.copyWith(
          isGoogleHomeLinked: true,
          rainmakerNodeId: nodeId,
        );
        _ref.read(pairedDevicesProvider.notifier).upsertDevice(updated);
      }
      return true;
    } else {
      state = state.copyWith(errorMessage: 'Failed to link node $nodeId to your account.');
      return false;
    }
  }
}

final rainmakerAuthProvider = StateNotifierProvider<RainmakerAuthNotifier, RainmakerAuthState>((ref) {
  return RainmakerAuthNotifier(ref);
});

