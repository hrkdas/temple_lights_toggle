import 'dart:async';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import '../core/log.dart';

final _log = AppLog.tag('ble.scanner');

/// Discovered BLE peripheral model for the UI and auto-connect engine.
class ScannedDevice {
  ScannedDevice({
    required this.id,
    required this.name,
    required this.rssi,
    required this.serviceUuids,
    required this.firstSeen,
  });

  final String id;
  final String name;
  final int rssi;
  final List<Uuid> serviceUuids;
  final DateTime firstSeen;

  ScannedDevice copyWith({int? rssi, String? name}) => ScannedDevice(
        id: id,
        name: name ?? this.name,
        rssi: rssi ?? this.rssi,
        serviceUuids: serviceUuids,
        firstSeen: firstSeen,
      );
}

/// Continuous BLE Scanner with deduplication, RSSI updates, and sorted stream.
class BleScanner {
  BleScanner({FlutterReactiveBle? ble}) : _ble = ble ?? FlutterReactiveBle();

  final FlutterReactiveBle _ble;
  StreamSubscription<DiscoveredDevice>? _sub;
  final Map<String, ScannedDevice> _devices = {};
  final _controller = StreamController<List<ScannedDevice>>.broadcast();

  Stream<List<ScannedDevice>> get stream => _controller.stream;
  bool get isScanning => _sub != null;

  /// Starts scanning for devices.
  /// If [serviceFilter] is provided, filters hardware advertisements.
  /// Otherwise performs a broad scan.
  Future<void> start({List<String>? serviceFilter}) async {
    if (_sub != null) {
      _log.w('start() called while scanner is already running');
      return;
    }

    _log.i('Starting BLE scan (filter: ${serviceFilter ?? "all"})');
    _devices.clear();
    _controller.add(const []);

    final services = serviceFilter?.map(Uuid.parse).toList() ?? <Uuid>[];

    _sub = _ble
        .scanForDevices(
      withServices: services,
      scanMode: ScanMode.lowLatency,
    )
        .listen(
      (d) => _onDiscovered(d),
      onError: (Object e, StackTrace st) {
        _log.e('Scan error: $e', error: e, stack: st);
      },
    );
  }

  void _onDiscovered(DiscoveredDevice d) {
    final displayName = d.name.trim().isEmpty ? 'BLE Peripheral (${d.id.substring(0, d.id.length > 8 ? 8 : d.id.length)})' : d.name.trim();

    final prev = _devices[d.id];
    final now = ScannedDevice(
      id: d.id,
      name: displayName,
      rssi: d.rssi,
      serviceUuids: d.serviceUuids,
      firstSeen: prev?.firstSeen ?? DateTime.now(),
    );

    _devices[d.id] = now;
    _emit();
  }

  void _emit() {
    final list = _devices.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    _controller.add(list);
  }

  Future<void> stop() async {
    if (_sub == null) return;
    _log.i('Stopping BLE scan (${_devices.length} devices discovered)');
    await _sub?.cancel();
    _sub = null;
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}
