import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import '../contract/light_contract.dart';
import '../core/log.dart';

final _log = AppLog.tag('ble.client');

/// Manages a single active BLE device connection session, service discovery, and characteristic writes.
class BleClient {
  BleClient({FlutterReactiveBle? ble}) : _ble = ble ?? FlutterReactiveBle();

  final FlutterReactiveBle _ble;

  StreamSubscription<ConnectionStateUpdate>? _connSub;
  final _connStateController = StreamController<DeviceConnectionState>.broadcast();

  String? _deviceId;
  String? _deviceName;
  Completer<void>? _writeMutex;
  List<Service> _discoveredServices = [];

  Stream<DeviceConnectionState> get connectionStream => _connStateController.stream;
  FlutterReactiveBle get rawBle => _ble;
  String? get deviceId => _deviceId;
  String? get deviceName => _deviceName;
  List<Service> get discoveredServices => _discoveredServices;
  bool get isConnected => _deviceId != null;

  /// Connect to a device by ID and discover all GATT services.
  Future<void> connect(
    String deviceId, {
    String? name,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (_connSub != null) {
      _log.w('connect() called while already attached to $_deviceId — disconnecting first');
      await disconnect();
    }

    _deviceId = deviceId;
    _deviceName = name;
    _log.i('Connecting to $deviceId (${name ?? "unnamed"})...');

    final readyCompleter = Completer<void>();

    _connSub = _ble
        .connectToDevice(
      id: deviceId,
      connectionTimeout: timeout,
    )
        .listen(
      (update) async {
        _log.i('Device $deviceId state: ${update.connectionState.name}');
        _connStateController.add(update.connectionState);

        if (update.connectionState == DeviceConnectionState.connected) {
          try {
            try {
              final mtu = await _ble.requestMtu(deviceId: deviceId, mtu: 512);
              _log.i('Negotiated ATT MTU size: $mtu bytes for $deviceId');
            } catch (e) {
              _log.w('MTU negotiation skipped or failed: $e');
            }
            await _ble.discoverAllServices(deviceId);
            _discoveredServices = await _ble.getDiscoveredServices(deviceId);
            _log.i('Discovered ${_discoveredServices.length} GATT services on $deviceId');
            if (!readyCompleter.isCompleted) {
              readyCompleter.complete();
            }
          } catch (e) {
            _log.w('Service discovery failed: $e');
            if (!readyCompleter.isCompleted) {
              readyCompleter.complete();
            }
          }
        } else if (update.connectionState == DeviceConnectionState.disconnected) {
          if (!readyCompleter.isCompleted) {
            readyCompleter.completeError(
              StateError('Disconnected before connection established: ${update.failure}'),
            );
          }
        }
      },
      onError: (Object e, StackTrace st) {
        _log.e('Connection stream error: $e', error: e, stack: st);
        if (!readyCompleter.isCompleted) {
          readyCompleter.completeError(e);
        }
      },
    );

    try {
      await readyCompleter.future.timeout(
        timeout + const Duration(seconds: 3),
        onTimeout: () {
          _log.e('Connection timed out after ${timeout.inSeconds}s');
          throw TimeoutException('BLE connection timed out');
        },
      );
    } catch (_) {
      await disconnect();
      rethrow;
    }
  }

  /// Disconnects from the current device.
  Future<void> disconnect() async {
    _log.i('Disconnecting from $_deviceId');
    await _connSub?.cancel();
    _connSub = null;
    _deviceId = null;
    _deviceName = null;
    _discoveredServices = [];
    _connStateController.add(DeviceConnectionState.disconnected);
  }

  /// Resolve a [QualifiedCharacteristic] using target UUIDs or automatic discovery.
  QualifiedCharacteristic resolveCharacteristic({
    String? serviceUuid,
    String? charUuid,
  }) {
    final devId = _deviceId;
    if (devId == null) throw StateError('No BLE device connected');

    // 1. If explicit UUIDs given, use them
    if (serviceUuid != null && charUuid != null) {
      return QualifiedCharacteristic(
        serviceId: Uuid.parse(serviceUuid),
        characteristicId: Uuid.parse(charUuid),
        deviceId: devId,
      );
    }

    // 2. Look for known LOT / Relay characteristic in discovered services
    for (final s in _discoveredServices) {
      final sUuid = s.id.toString().toLowerCase();
      if (sUuid == LightBleUuids.defaultService.toLowerCase()) {
        for (final c in s.characteristics) {
          if (c.id.toString().toLowerCase() == LightBleUuids.defaultControlChar.toLowerCase()) {
            return QualifiedCharacteristic(
              serviceId: s.id,
              characteristicId: c.id,
              deviceId: devId,
            );
          }
        }
      }
    }

    // 3. Fallback: find any writable characteristic among non-standard services
    for (final s in _discoveredServices) {
      final sUuid = s.id.toString().toLowerCase();
      // Skip generic access / generic attribute
      if (sUuid.contains('1800') || sUuid.contains('1801')) continue;
      if (s.characteristics.isNotEmpty) {
        return QualifiedCharacteristic(
          serviceId: s.id,
          characteristicId: s.characteristics.first.id,
          deviceId: devId,
        );
      }
    }

    // 4. Default fallback to standard contract
    return QualifiedCharacteristic(
      serviceId: Uuid.parse(LightBleUuids.defaultService),
      characteristicId: Uuid.parse(LightBleUuids.defaultControlChar),
      deviceId: devId,
    );
  }

  /// Write without response (fastest, ideal for continuous toggle / stream).
  Future<void> writeWithoutResponse(
    Uint8List bytes, {
    String? serviceUuid,
    String? charUuid,
  }) async {
    try {
      final qc = resolveCharacteristic(
        serviceUuid: serviceUuid,
        charUuid: charUuid,
      );
      await _ble.writeCharacteristicWithoutResponse(qc, value: bytes);
      _log.d('writeNoResp ${qc.characteristicId} (${bytes.length}B)');
    } catch (e) {
      _log.w('writeWithoutResponse failed: $e');
      // If writeWithoutResponse is not supported on this characteristic, fallback to write with response
      await writeWithResponse(bytes, serviceUuid: serviceUuid, charUuid: charUuid);
    }
  }

  /// Acknowledged write with mutex, GATT-133 and auth retry.
  Future<void> writeWithResponse(
    Uint8List bytes, {
    String? serviceUuid,
    String? charUuid,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    while (_writeMutex != null) {
      try {
        await _writeMutex!.future.timeout(const Duration(seconds: 3));
      } on TimeoutException {
        _log.w('Write mutex timeout — forcing release');
        _writeMutex = null;
      }
    }

    final mutex = _writeMutex = Completer<void>();
    final qc = resolveCharacteristic(
      serviceUuid: serviceUuid,
      charUuid: charUuid,
    );

    final stopTime = DateTime.now().add(timeout);
    try {
      while (DateTime.now().isBefore(stopTime)) {
        try {
          await _ble.writeCharacteristicWithResponse(qc, value: bytes);
          _log.d('writeAck ${qc.characteristicId} (${bytes.length}B)');
          return;
        } on Exception catch (e) {
          final errorStr = e.toString().toLowerCase();
          final isAuth = errorStr.contains('137') ||
              errorStr.contains('gatt_auth_fail') ||
              errorStr.contains('auth') ||
              errorStr.contains('insufficient');

          if (isAuth) {
            _log.i('Write triggered auth/pairing dialog. Waiting for user PIN in OS prompt...');
            await Future<void>.delayed(const Duration(milliseconds: 1500));
            if (_deviceId == null) break;
            continue;
          }

          if (_isGatt133(e)) {
            _log.w('GATT 133 error — retrying after 600ms');
            await Future<void>.delayed(const Duration(milliseconds: 600));
            if (_deviceId == null) break;
            continue;
          }

          rethrow;
        }
      }
    } finally {
      mutex.complete();
      if (identical(_writeMutex, mutex)) _writeMutex = null;
    }
  }

  /// Reads the current value of the characteristic with pairing/auth retry.
  Future<Uint8List> readCharacteristic({
    String? serviceUuid,
    String? charUuid,
    Duration pairingTimeout = const Duration(seconds: 30),
  }) async {
    final qc = resolveCharacteristic(
      serviceUuid: serviceUuid,
      charUuid: charUuid,
    );

    final stopTime = DateTime.now().add(pairingTimeout);
    Object? lastError;

    while (DateTime.now().isBefore(stopTime)) {
      try {
        final data = await _ble.readCharacteristic(qc);
        _log.i('readCharacteristic ${qc.characteristicId}: ${data.length}B (0x${data.map((b) => b.toRadixString(16).padLeft(2, '0')).join()})');
        return Uint8List.fromList(data);
      } catch (e) {
        lastError = e;
        final errorStr = e.toString().toLowerCase();

        // 137 = GATT_AUTH_FAIL (Android SMP pairing popup in progress)
        // 5 = GATT_INSUFFICIENT_AUTHENTICATION
        // 15 = GATT_INSUFFICIENT_ENCRYPTION
        final isAuthOrPairing = errorStr.contains('137') ||
            errorStr.contains('gatt_auth_fail') ||
            errorStr.contains('auth') ||
            errorStr.contains('insufficient') ||
            errorStr.contains('security');

        if (isAuthOrPairing) {
          _log.i('Hardware pairing / auth required (status 137 / GATT_AUTH_FAIL). Waiting for user PIN input in system prompt...');
          await Future<void>.delayed(const Duration(milliseconds: 1500));
          if (_deviceId == null) break; // Device was disconnected
          continue;
        }

        if (_isGatt133(e)) {
          _log.w('GATT error during read — retrying in 800ms: $e');
          await Future<void>.delayed(const Duration(milliseconds: 800));
          if (_deviceId == null) break;
          continue;
        }

        rethrow;
      }
    }

    throw lastError ?? TimeoutException('Characteristic read/pairing timed out');
  }

  /// Subscribes to live BLE notifications / indications on the characteristic.
  Stream<List<int>> subscribeToCharacteristic({
    String? serviceUuid,
    String? charUuid,
  }) {
    final qc = resolveCharacteristic(
      serviceUuid: serviceUuid,
      charUuid: charUuid,
    );
    _log.i('Subscribing to characteristic notifications on ${qc.characteristicId}');
    return _ble.subscribeToCharacteristic(qc);
  }

  bool _isGatt133(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('133') || s.contains('gatt error');
  }

  /// Reads live connection RSSI (signal strength in dBm) from active BLE peripheral.
  Future<int> readRssi() async {
    final devId = _deviceId;
    if (devId == null) throw StateError('No BLE device connected');
    return _ble.readRssi(devId);
  }

  Future<void> dispose() async {
    await disconnect();
    await _connStateController.close();
  }
}
