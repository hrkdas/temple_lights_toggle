import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'log.dart';

final _log = AppLog.tag('permissions');

class BlePermissions {
  BlePermissions._();
  static Future<bool> requestAll() async {
    if (Platform.isIOS) {
      final st = await Permission.bluetooth.request();
      _log.i('iOS bluetooth permission: ${st.name}');
      return st.isGranted || st.isLimited;
    }
    if (Platform.isAndroid) {
      final results = await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.locationWhenInUse].request();
      results.forEach((p, st) => _log.i('Android $p = ${st.name}'));
      return (results[Permission.bluetoothScan]?.isGranted ?? false) && (results[Permission.bluetoothConnect]?.isGranted ?? false);
    }
    return true;
  }
}
