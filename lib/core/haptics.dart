import 'package:flutter/services.dart';
import 'package:haptic_feedback/haptic_feedback.dart' as hf;
import 'log.dart';

final _log = AppLog.tag('haptics');

class AppHaptics {
  AppHaptics._();
  static Future<bool> _canRich() async {
    try { return await hf.Haptics.canVibrate(); } catch (e) { _log.w('canVibrate failed: $e'); return false; }
  }
  static Future<void> tap() async {
    if (await _canRich()) { hf.Haptics.vibrate(hf.HapticsType.light); } else { HapticFeedback.lightImpact(); }
  }
  static Future<void> toggle([bool? isOn]) async {
    if (await _canRich()) { hf.Haptics.vibrate(hf.HapticsType.medium); } else { HapticFeedback.mediumImpact(); }
  }
  static Future<void> powerUp() async {
    if (await _canRich()) { hf.Haptics.vibrate(hf.HapticsType.heavy); await Future.delayed(const Duration(milliseconds: 70)); hf.Haptics.vibrate(hf.HapticsType.medium); } else { HapticFeedback.heavyImpact(); }
  }
  static Future<void> warn() async {
    for (var i = 0; i < 2; i++) { HapticFeedback.heavyImpact(); await Future.delayed(const Duration(milliseconds: 100)); }
  }
  static Future<void> light() async => tap();
  static Future<void> medium() async => toggle();
  static Future<void> error() async => warn();
  static Future<void> success() async => powerUp();
  static Future<void> impact() async => toggle();
  static Future<void> tick() async => HapticFeedback.selectionClick();
  static Future<void> selection() async => HapticFeedback.selectionClick();
}
