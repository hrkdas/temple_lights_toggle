import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'log.dart';

final _log = AppLog.tag('kv');

class KvStore {
  KvStore._(this._prefs);
  static KvStore? _instance;
  static Future<KvStore> instance() async {
    if (_instance != null) return _instance!;
    final prefs = await SharedPreferences.getInstance();
    _log.i('KvStore ready, keys=${prefs.getKeys().length}');
    return _instance = KvStore._(prefs);
  }
  static KvStore? get current => _instance;
  final SharedPreferences _prefs;

  Future<void> putJson(String key, Object value) async {
    await _prefs.setString(key, jsonEncode(value));
  }
  Map<String, dynamic>? getJsonMap(String key) {
    final s = _prefs.getString(key);
    if (s == null) return null;
    try { return jsonDecode(s) as Map<String, dynamic>; } catch (e) { _log.w('decode map failed for $key: $e'); return null; }
  }
  List<dynamic>? getJsonList(String key) {
    final s = _prefs.getString(key);
    if (s == null) return null;
    try { return jsonDecode(s) as List<dynamic>; } catch (e) { _log.w('decode list failed for $key: $e'); return null; }
  }
  String? getString(String key) => _prefs.getString(key);
  Future<void> putString(String k, String v) => _prefs.setString(k, v);
  bool? getBool(String key) => _prefs.getBool(key);
  Future<void> putBool(String k, bool v) => _prefs.setBool(k, v);
  int? getInt(String key) => _prefs.getInt(key);
  Future<void> putInt(String k, int v) => _prefs.setInt(k, v);
  Future<void> remove(String key) => _prefs.remove(key);
}

class KvKeys {
  KvKeys._();
  static const lastConnectedId = 'last_connected_device_id';
  static const lastConnectedName = 'last_connected_device_name';
  static const savedDevices = 'saved_devices_v1';
  static const savedSchedules = 'saved_schedules_v1';
  static const savedModes = 'saved_default_modes_v1';
}
