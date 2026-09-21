import 'dart:convert';
import 'dart:typed_data';

class LightBleUuids {
  LightBleUuids._();
  static const String defaultService = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890';
  static const String defaultControlChar = 'a1b2c3d4-e5f6-7890-abcd-ef1234567891';
  static const String defaultOtaChar = 'a1b2c3d4-e5f6-7890-abcd-ef1234567892';
  static const List<String> knownServices = [defaultService];
  static const String targetDeviceName = 'Temple Lights';
  static const String bundledFirmwareVersion = '1.2.0';

  static bool isTargetDevice({required String name, List<String>? serviceUuids}) {
    final lowerName = name.trim().toLowerCase();
    if (lowerName == targetDeviceName.toLowerCase() || lowerName.contains('temple')) return true;
    if (serviceUuids != null && serviceUuids.any((u) => u.toLowerCase() == defaultService.toLowerCase())) return true;
    return false;
  }

  static bool isTargetRelayDevice({required String name, List<String>? serviceUuids}) =>
      isTargetDevice(name: name, serviceUuids: serviceUuids);
}

class LightPacketEncoder {
  LightPacketEncoder._();

  static Uint8List encodeSetMode(int mode) =>
      Uint8List.fromList(utf8.encode(jsonEncode({'cmd': 'set_mode', 'mode': mode})));

  static Uint8List encodeNextMode() =>
      Uint8List.fromList(utf8.encode(jsonEncode({'cmd': 'next_mode'})));

  static Uint8List encodeSetBrightness(int val) =>
      Uint8List.fromList(utf8.encode(jsonEncode({'cmd': 'set_bright', 'val': val})));

  static Uint8List encodeFastBrightness(int val) =>
      Uint8List.fromList([0x42, val.clamp(0, 255)]);

  static Uint8List encodeSetRgb(int r, int g, int b) =>
      Uint8List.fromList(utf8.encode(jsonEncode({'cmd': 'set_rgb', 'r': r, 'g': g, 'b': b})));

  static Uint8List encodeOn() =>
      Uint8List.fromList(utf8.encode(jsonEncode({'cmd': 'on'})));

  static Uint8List encodeOff() =>
      Uint8List.fromList(utf8.encode(jsonEncode({'cmd': 'off'})));

  static Uint8List encodeGetState() =>
      Uint8List.fromList(utf8.encode(jsonEncode({'cmd': 'get_state'})));

  static Uint8List encodeTimeSync(DateTime now) =>
      Uint8List.fromList(utf8.encode(jsonEncode({'cmd': 'time', 'y': now.year, 'mon': now.month, 'd': now.day, 'h': now.hour, 'm': now.minute, 's': now.second, 'w': now.weekday, 'epoch': now.millisecondsSinceEpoch ~/ 1000})));

  static Uint8List encodeSaveSchedule({
    required String id,
    required String name,
    required bool isEnabled,
    required bool hasTurnOn,
    required int turnOnHour,
    required int turnOnMinute,
    required bool hasTurnOff,
    required int turnOffHour,
    required int turnOffMinute,
    required List<int> repeatDays,
    int? targetMode,
    int? targetBrightness,
    int? targetR,
    int? targetG,
    int? targetB,
  }) =>
      Uint8List.fromList(utf8.encode(jsonEncode({
        'cmd': 'save_sched',
        'id': id,
        'name': name,
        'en': isEnabled,
        'on_en': hasTurnOn,
        'on_h': turnOnHour,
        'on_m': turnOnMinute,
        'off_en': hasTurnOff,
        'off_h': turnOffHour,
        'off_m': turnOffMinute,
        'days': repeatDays,
        if (targetMode != null) 'tgt_mode': targetMode,
        if (targetBrightness != null) 'tgt_bright': targetBrightness,
        if (targetR != null) 'tgt_r': targetR,
        if (targetG != null) 'tgt_g': targetG,
        if (targetB != null) 'tgt_b': targetB,
      })));

  static Uint8List encodeGetSchedules() =>
      Uint8List.fromList(utf8.encode(jsonEncode({'cmd': 'get_scheds'})));

  static Uint8List encodeToggleSchedule(String id, bool isEnabled) =>
      Uint8List.fromList(utf8.encode(jsonEncode({'cmd': 'toggle_sched', 'id': id, 'en': isEnabled})));

  static Uint8List encodeDeleteSchedule(String id) =>
      Uint8List.fromList(utf8.encode(jsonEncode({'cmd': 'del_sched', 'id': id})));

  static Uint8List encodeStartTimer({required int seconds}) =>
      Uint8List.fromList(utf8.encode(jsonEncode({'cmd': 'timer', 'sec': seconds})));

  static Uint8List encodeCancelTimer() =>
      Uint8List.fromList(utf8.encode(jsonEncode({'cmd': 'timer_cancel'})));

  static Uint8List encodeOtaBegin({required int size, required String md5}) =>
      Uint8List.fromList(utf8.encode(jsonEncode({'cmd': 'ota_begin', 'size': size, 'md5': md5})));

  static Uint8List encodeOtaEnd() =>
      Uint8List.fromList(utf8.encode(jsonEncode({'cmd': 'ota_end'})));

  static Uint8List encodeOtaAbort() =>
      Uint8List.fromList(utf8.encode(jsonEncode({'cmd': 'ota_abort'})));

  static Uint8List encodeGetModes() =>
      Uint8List.fromList(utf8.encode(jsonEncode({'cmd': 'get_modes'})));

  static Uint8List encodeSaveMode({
    required int index,
    required String name,
    required int r,
    required int g,
    required int b,
    required int style,
    required int brightness,
  }) =>
      Uint8List.fromList(utf8.encode(jsonEncode({
        'cmd': 'save_mode',
        'idx': index,
        'name': name,
        'r': r,
        'g': g,
        'b': b,
        'style': style,
        'bright': brightness,
      })));

  static Uint8List encodeResetModes() =>
      Uint8List.fromList(utf8.encode(jsonEncode({'cmd': 'reset_modes'})));
}
