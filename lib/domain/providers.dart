import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../contract/light_contract.dart';
import '../contract/ota_constants.dart';
import '../core/haptics.dart';
import '../core/kv_store.dart';
import '../core/log.dart';
import '../core/permissions.dart';
import '../transport/ble_client.dart';
import '../transport/ota_chunker.dart';
import '../transport/ota_protocol.dart';
import '../transport/scanner.dart';
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

  Future<void> recordDevice({required String id, required String name}) async {
    final now = DateTime.now();
    final existing = state.firstWhere(
      (d) => d.id == id,
      orElse: () => PairedDevice(id: id, name: name, lastSeen: now),
    );
    existing.name = name;
    existing.lastSeen = now;

    state = [
      existing,
      ...state.where((d) => d.id != id),
    ];

    await _kv.putString(KvKeys.lastConnectedId, id);
    await _kv.putString(KvKeys.lastConnectedName, name);
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
              _ref.read(lightControlProvider.notifier).updateFromHardware(
                    mode: m,
                    brightness: b,
                    r: r,
                    g: g,
                    b: bl,
                    firmwareVersion: ver,
                  );
            } else if (type == 'ota_ack') {
              _ref.read(otaProgressProvider.notifier).handleOtaAck(json);
            } else if (type == 'time_synced') {
              _log.i('ESP32 confirmed RTC time sync');
            } else if (type == 'mode_cfg' || type == 'modes_end') {
              _ref.read(defaultModesProvider.notifier).handleIncomingModePacket(json);
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
    unawaited(_ref.read(schedulesProvider.notifier).onDeviceConnected());
    unawaited(_ref.read(defaultModesProvider.notifier).onDeviceConnected());
    _startLiveRssiTracking(deviceId);

    // Initial state query
    try {
      await _client.writeWithoutResponse(
        LightPacketEncoder.encodeGetState(),
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
  LightControlNotifier(this._ref) : super(LightState.idle);

  final Ref _ref;
  BleClient get _client => _ref.read(bleClientProvider);

  DateTime? _lastLocalInteraction;
  Timer? _throttleTimer;
  int? _pendingBrightness;
  bool _sendInFlight = false;

  void startBrightnessDrag() {
    _lastLocalInteraction = DateTime.now();
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
    if (on) {
      // Switching ON: remember last state, advance to next mode and loop among 0, 1, 2
      final nextMode = state.mode >= 2 ? 0 : state.mode + 1;
      const targetBright = 255;
      state = state.copyWith(mode: nextMode, isOn: true, brightness: targetBright, lastToggled: DateTime.now());
      await AppHaptics.powerUp();
      await _dispatchPacket(LightPacketEncoder.encodeOn());
    } else {
      state = state.copyWith(isOn: false, brightness: 0, lastToggled: DateTime.now());
      _ref.read(autoOffTimerProvider.notifier).onLightsSwitchedOff();
      await AppHaptics.toggle(false);
      await _dispatchFast(LightPacketEncoder.encodeFastBrightness(0));
      await _dispatchPacket(LightPacketEncoder.encodeOff());
    }
  }

  /// Switch mode (0=warm all, 1=warm center, 2=white all, 3=custom rgb)
  Future<void> setMode(int mode) async {
    _lastLocalInteraction = DateTime.now();
    final nextBright = state.brightness == 0 ? 255 : state.brightness;
    state = state.copyWith(mode: mode, isOn: true, brightness: nextBright, lastToggled: DateTime.now());
    await AppHaptics.selection();
    await _dispatchPacket(LightPacketEncoder.encodeSetMode(mode));
  }

  /// Cycle to next mode
  Future<void> nextMode() async {
    final nextM = (state.mode + 1) % 4;
    await setMode(nextM);
  }

  /// Set custom RGB color (auto-switches to mode 3)
  Future<void> setRgb(int r, int g, int b) async {
    _lastLocalInteraction = DateTime.now();
    final nextBright = state.brightness == 0 ? 255 : state.brightness;
    state = state.copyWith(
      r: r.clamp(0, 255),
      g: g.clamp(0, 255),
      b: b.clamp(0, 255),
      mode: 3,
      isOn: true,
      brightness: nextBright,
      lastToggled: DateTime.now(),
    );
    await AppHaptics.tap();
    await _dispatchPacket(LightPacketEncoder.encodeSetRgb(r, g, b));
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
  }) {
    // If the user recently changed brightness/mode locally (within last 1500ms),
    // ignore stale incoming hardware echo to prevent slider jitter or jumping
    final isRecentLocal = _lastLocalInteraction != null &&
        DateTime.now().difference(_lastLocalInteraction!).inMilliseconds < 1500;

    final targetBright = isRecentLocal ? state.brightness : brightness;
    final isOn = targetBright > 0;

    state = state.copyWith(
      mode: mode,
      brightness: targetBright,
      r: r,
      g: g,
      b: b,
      isOn: isOn,
      lastToggled: isRecentLocal ? state.lastToggled : DateTime.now(),
      firmwareVersion: firmwareVersion ?? state.firmwareVersion,
    );
    if (!isOn) {
      _ref.read(autoOffTimerProvider.notifier).onLightsSwitchedOff();
    }
    _log.i('Lights state updated from hardware: mode=$mode, bright=$brightness, RGB=($r,$g,$b), ver=${firmwareVersion ?? state.firmwareVersion}');
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

  void _persist() {
    unawaited(_kv.putJson(KvKeys.savedModes, state.map((m) => m.toJson()).toList()));
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

