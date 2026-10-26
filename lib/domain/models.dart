import 'package:flutter/material.dart';

enum ConnPhase {
  idle,
  scanning,
  connecting,
  connected,
  reconnecting,
  disconnected,
  failed,
}

class ConnState {
  const ConnState({
    required this.phase,
    this.deviceId,
    this.deviceName,
    this.rssi,
    this.errorMessage,
    this.reconnectAttempt = 0,
    this.isTargetPaired = false,
  });

  final ConnPhase phase;
  final String? deviceId;
  final String? deviceName;
  final int? rssi;
  final String? errorMessage;
  final int reconnectAttempt;
  final bool isTargetPaired;

  bool get isConnected => phase == ConnPhase.connected;
  bool get isConnecting => phase == ConnPhase.connecting;
  bool get isReconnecting => phase == ConnPhase.reconnecting;
  bool get isScanning => phase == ConnPhase.scanning;

  int get signalStrengthPercent {
    if (rssi == null) return isConnected ? 70 : 0;
    return ((rssi! + 100) * 2).clamp(0, 100);
  }

  String get signalQualityLabel {
    if (!isConnected) {
      if (isReconnecting) return 'Out of Range';
      if (isScanning) return 'Searching...';
      return 'Disconnected';
    }
    final r = rssi ?? -70;
    if (r >= -60) return 'Excellent (Close)';
    if (r >= -72) return 'Good (Moderate)';
    if (r >= -84) return 'Fair (Distant)';
    return 'Weak (Far Range)';
  }

  ConnState copyWith({
    ConnPhase? phase,
    String? deviceId,
    String? deviceName,
    int? rssi,
    String? errorMessage,
    int? reconnectAttempt,
    bool? isTargetPaired,
    bool clearError = false,
    bool clearDevice = false,
  }) =>
      ConnState(
        phase: phase ?? this.phase,
        deviceId: clearDevice ? null : (deviceId ?? this.deviceId),
        deviceName: clearDevice ? null : (deviceName ?? this.deviceName),
        rssi: rssi ?? this.rssi,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        reconnectAttempt: reconnectAttempt ?? this.reconnectAttempt,
        isTargetPaired: isTargetPaired ?? this.isTargetPaired,
      );

  static const idle = ConnState(phase: ConnPhase.idle);
}

class LedSegment {
  const LedSegment({
    required this.start,
    required this.count,
    this.r = 255,
    this.g = 147,
    this.b = 41,
    this.brightness = 255,
    this.effect = 0, // 0=Solid, 1=Breathe, 2=Diya, 3=Twinkle, 4=Ember, 5=Aurora, 6=Rainbow
    this.speed = 5,
    this.name,
  });

  final int start;
  final int count;
  final int r;
  final int g;
  final int b;
  final int brightness;
  final int effect;
  final int speed;
  final String? name;

  int get end => (start + count - 1).clamp(start, 65535);

  Color get color => Color.fromARGB(255, r, g, b);

  String get displayName => (name != null && name!.trim().isNotEmpty)
      ? name!.trim()
      : 'LEDs #${start + 1}–#${end + 1}';

  String get effectName {
    switch (effect) {
      case 0:
        return 'Pure Solid';
      case 1:
        return 'Gentle Breathe';
      case 2:
        return 'Diya Candle Flutter';
      case 3:
        return 'Starlight Twinkle';
      case 4:
        return 'Sacred Amber Embers';
      case 5:
        return 'Aurora Flow';
      case 6:
        return 'Rainbow Cycle';
      default:
        return 'Pure Solid';
    }
  }

  LedSegment copyWith({
    int? start,
    int? count,
    int? r,
    int? g,
    int? b,
    int? brightness,
    int? effect,
    int? speed,
    String? name,
  }) =>
      LedSegment(
        start: start ?? this.start,
        count: count ?? this.count,
        r: r ?? this.r,
        g: g ?? this.g,
        b: b ?? this.b,
        brightness: brightness ?? this.brightness,
        effect: effect ?? this.effect,
        speed: speed ?? this.speed,
        name: name ?? this.name,
      );

  Map<String, dynamic> toJson() => {
        'start': start,
        'count': count,
        'r': r,
        'g': g,
        'b': b,
        'bright': brightness,
        'fx': effect,
        'spd': speed,
        if (name != null && name!.isNotEmpty) 'name': name,
      };

  factory LedSegment.fromJson(Map<String, dynamic> json) => LedSegment(
        start: (json['start'] as num?)?.toInt() ?? 0,
        count: (json['count'] as num?)?.toInt() ?? 1,
        r: (json['r'] as num?)?.toInt() ?? 255,
        g: (json['g'] as num?)?.toInt() ?? 147,
        b: (json['b'] as num?)?.toInt() ?? 41,
        brightness: (json['bright'] as num?)?.toInt() ?? 255,
        effect: (json['fx'] as num?)?.toInt() ?? 0,
        speed: (json['spd'] as num?)?.toInt() ?? 5,
        name: json['name'] as String?,
      );
}

class LightState {
  const LightState({
    this.isOn = true,
    this.mode = 0,
    this.brightness = 255,
    this.r = 255,
    this.g = 147,
    this.b = 41,
    this.isSending = false,
    this.lastToggled,
    this.firmwareVersion,
    this.ledCount = 150,
    this.maxCurrentMa = 3000,
    this.colorOrder = 0,
    this.transitionStyle = 0,
    this.ambientStyle = 1,
    this.ambientDepth = 6,
    this.activePreset = 0,
    this.cycleFlags = 0x07,
    this.segments = const [],
    this.rainmakerNodeId,
  });

  final bool isOn;
  final int mode;
  final int brightness;
  final int r, g, b;
  final bool isSending;
  final DateTime? lastToggled;
  final String? firmwareVersion;
  final int ledCount;
  final int maxCurrentMa;
  final int colorOrder;      // 0=RGB (Hardware Default: Direct Red-Green-Blue), 1=GRB (WS2812B), 2=BRG, 3=BGR
  final int transitionStyle; // 0=Center-Out, 1=Sunrise, 2=Sunset, 3=Convergence, 4=Sparkle, 5=Domino, 6=Fade
  final int ambientStyle;    // 0=Solid, 1=Breathe, 2=Diya, 3=Twinkle, 4=Embers, 5=Aurora, 6=Rainbow
  final int ambientDepth;
  final int activePreset;
  final int cycleFlags;
  final List<LedSegment> segments;
  final String? rainmakerNodeId;

  static const List<String> colorOrderNames = [
    'RGB (Standard / Default)',
    'GRB (WS2812B)',
    'BRG',
    'BGR',
  ];

  String get colorOrderName =>
      (colorOrder >= 0 && colorOrder < colorOrderNames.length)
          ? colorOrderNames[colorOrder]
          : colorOrderNames[0];

  bool get isOff => !isOn || brightness == 0;

  double get stripLengthMeters => ledCount / 60.0;
  String get formattedLength => '${stripLengthMeters.toStringAsFixed(1)}m';

  String get modeName {
    final len = formattedLength;
    final centerLen = (stripLengthMeters * 0.6).toStringAsFixed(1);
    switch (mode) {
      case 0:
        return 'Warm White (All $len)';
      case 1:
        return 'Warm White (Center ${centerLen}m)';
      case 2:
        return 'Pure White (All $len)';
      case 3:
        return 'Custom RGB';
      default:
        return 'Mode $mode';
    }
  }

  static const List<String> transitionStyleNames = [
    'Center-Out Dawn',
    'Sunrise Flow',
    'Uniform Smooth Fade',
    'Sunset Cascade',
    'Dual Convergence',
    'Sparkle Ignition',
    'Segment Domino',
  ];

  static const List<String> ambientStyleNames = [
    'Pure Solid',
    'Gentle Breathing',
    'Diya Candle Flutter',
    'Starlight Twinkle',
    'Sacred Amber Embers',
    'Aurora Flow',
    'Rainbow Cycle',
  ];

  String get transitionStyleName {
    if (transitionStyle >= 0 && transitionStyle < transitionStyleNames.length) {
      return transitionStyleNames[transitionStyle];
    }
    return transitionStyleNames[0];
  }

  String get ambientStyleName {
    if (ambientStyle >= 0 && ambientStyle < ambientStyleNames.length) {
      return ambientStyleNames[ambientStyle];
    }
    return ambientStyleNames[1];
  }

  LightState copyWith({
    bool? isOn,
    int? mode,
    int? brightness,
    int? r,
    int? g,
    int? b,
    bool? isSending,
    DateTime? lastToggled,
    String? firmwareVersion,
    int? ledCount,
    int? maxCurrentMa,
    int? colorOrder,
    int? transitionStyle,
    int? ambientStyle,
    int? ambientDepth,
    int? activePreset,
    int? cycleFlags,
    List<LedSegment>? segments,
    String? rainmakerNodeId,
  }) =>
      LightState(
        isOn: isOn ?? this.isOn,
        mode: mode ?? this.mode,
        brightness: brightness ?? this.brightness,
        r: r ?? this.r,
        g: g ?? this.g,
        b: b ?? this.b,
        isSending: isSending ?? this.isSending,
        lastToggled: lastToggled ?? this.lastToggled,
        firmwareVersion: firmwareVersion ?? this.firmwareVersion,
        ledCount: ledCount ?? this.ledCount,
        maxCurrentMa: maxCurrentMa ?? this.maxCurrentMa,
        colorOrder: colorOrder ?? this.colorOrder,
        transitionStyle: transitionStyle ?? this.transitionStyle,
        ambientStyle: ambientStyle ?? this.ambientStyle,
        ambientDepth: ambientDepth ?? this.ambientDepth,
        activePreset: activePreset ?? this.activePreset,
        cycleFlags: cycleFlags ?? this.cycleFlags,
        segments: segments ?? this.segments,
        rainmakerNodeId: rainmakerNodeId ?? this.rainmakerNodeId,
      );

  static const idle = LightState();
}

enum OtaPhase {
  idle,
  loadingAsset,
  connecting,
  preparing,
  transferring,
  verifying,
  rebooting,
  completed,
  failed,
  canceled,
}

class OtaProgressState {
  const OtaProgressState({
    this.phase = OtaPhase.idle,
    this.bytesWritten = 0,
    this.totalBytes = 0,
    this.speedBytesPerSec = 0,
    this.etaSeconds = 0,
    this.statusMessage = 'Ready',
    this.errorMessage,
    this.deviceFirmwareVersion,
    this.bundledFirmwareVersion = '1.2.0',
    this.isCompleted = false,
  });

  final OtaPhase phase;
  final int bytesWritten;
  final int totalBytes;
  final double speedBytesPerSec;
  final int etaSeconds;
  final String statusMessage;
  final String? errorMessage;
  final String? deviceFirmwareVersion;
  final String bundledFirmwareVersion;
  final bool isCompleted;

  double get progress {
    if (totalBytes <= 0) return 0.0;
    return (bytesWritten / totalBytes).clamp(0.0, 1.0);
  }

  int get percentage => (progress * 100).toInt();

  bool get isInProgress =>
      phase == OtaPhase.loadingAsset ||
      phase == OtaPhase.connecting ||
      phase == OtaPhase.preparing ||
      phase == OtaPhase.transferring ||
      phase == OtaPhase.verifying ||
      phase == OtaPhase.rebooting;

  String get formattedBytes {
    if (totalBytes <= 0) return '0 KB';
    final currentKb = (bytesWritten / 1024).toStringAsFixed(1);
    final totalKb = (totalBytes / 1024).toStringAsFixed(1);
    return '$currentKb / $totalKb KB';
  }

  String get formattedSpeed {
    if (speedBytesPerSec <= 0) return '-- KB/s';
    final kbPerSec = (speedBytesPerSec / 1024).toStringAsFixed(1);
    return '$kbPerSec KB/s';
  }

  String get formattedEta {
    if (etaSeconds <= 0) return '--';
    if (etaSeconds < 60) return '${etaSeconds}s';
    final m = etaSeconds ~/ 60;
    final s = etaSeconds % 60;
    return '${m}m ${s}s';
  }

  OtaProgressState copyWith({
    OtaPhase? phase,
    int? bytesWritten,
    int? totalBytes,
    double? speedBytesPerSec,
    int? etaSeconds,
    String? statusMessage,
    String? errorMessage,
    String? deviceFirmwareVersion,
    String? bundledFirmwareVersion,
    bool? isCompleted,
    bool clearError = false,
  }) =>
      OtaProgressState(
        phase: phase ?? this.phase,
        bytesWritten: bytesWritten ?? this.bytesWritten,
        totalBytes: totalBytes ?? this.totalBytes,
        speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
        etaSeconds: etaSeconds ?? this.etaSeconds,
        statusMessage: statusMessage ?? this.statusMessage,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        deviceFirmwareVersion: deviceFirmwareVersion ?? this.deviceFirmwareVersion,
        bundledFirmwareVersion: bundledFirmwareVersion ?? this.bundledFirmwareVersion,
        isCompleted: isCompleted ?? this.isCompleted,
      );

  static const idle = OtaProgressState();
}

class LightSettings {
  const LightSettings({
    this.customServiceUuid,
    this.customCharUuid,
    this.autoConnectEnabled = true,
    this.nameFilter = '',
    this.aggressiveLongRangeReconnect = true,
  });

  final String? customServiceUuid;
  final String? customCharUuid;
  final bool autoConnectEnabled;
  final String nameFilter;
  final bool aggressiveLongRangeReconnect;

  LightSettings copyWith({
    String? customServiceUuid,
    String? customCharUuid,
    bool? autoConnectEnabled,
    String? nameFilter,
    bool? aggressiveLongRangeReconnect,
    bool clearServiceUuid = false,
    bool clearCharUuid = false,
  }) =>
      LightSettings(
        customServiceUuid: clearServiceUuid ? null : (customServiceUuid ?? this.customServiceUuid),
        customCharUuid: clearCharUuid ? null : (customCharUuid ?? this.customCharUuid),
        autoConnectEnabled: autoConnectEnabled ?? this.autoConnectEnabled,
        nameFilter: nameFilter ?? this.nameFilter,
        aggressiveLongRangeReconnect: aggressiveLongRangeReconnect ?? this.aggressiveLongRangeReconnect,
      );

  Map<String, dynamic> toJson() => {
        'customServiceUuid': customServiceUuid,
        'customCharUuid': customCharUuid,
        'autoConnectEnabled': autoConnectEnabled,
        'nameFilter': nameFilter,
        'aggressiveLongRangeReconnect': aggressiveLongRangeReconnect,
      };

  factory LightSettings.fromJson(Map<String, dynamic> json) => LightSettings(
        customServiceUuid: json['customServiceUuid'] as String?,
        customCharUuid: json['customCharUuid'] as String?,
        autoConnectEnabled: json['autoConnectEnabled'] as bool? ?? true,
        nameFilter: json['nameFilter'] as String? ?? '',
        aggressiveLongRangeReconnect: json['aggressiveLongRangeReconnect'] as bool? ?? true,
      );
}

class PairedDevice {
  PairedDevice({
    required this.id,
    required this.name,
    required this.lastSeen,
    this.customAlias,
    this.firmwareVersion,
    this.cachedBrightness,
    this.cachedMode,
    this.cachedIsOn,
    this.cachedR,
    this.cachedG,
    this.cachedB,
    this.ledCount,
    this.maxCurrentMa,
    this.colorOrder,
    this.transitionStyle,
    this.ambientStyle,
    this.ambientDepth,
    this.roomId,
    this.activePresetIndex,
    this.segments,
    this.isGoogleHomeLinked,
    this.rainmakerNodeId,
  });

  final String id;
  String name;
  DateTime lastSeen;
  String? customAlias;
  String? firmwareVersion;
  int? cachedBrightness;
  int? cachedMode;
  bool? cachedIsOn;
  int? cachedR;
  int? cachedG;
  int? cachedB;
  int? ledCount;
  int? maxCurrentMa;
  int? colorOrder;
  int? transitionStyle;
  int? ambientStyle;
  int? ambientDepth;
  String? roomId;
  int? activePresetIndex;
  List<LedSegment>? segments;
  bool? isGoogleHomeLinked;
  String? rainmakerNodeId;

  String get displayName =>
      (customAlias != null && customAlias!.trim().isNotEmpty)
          ? customAlias!.trim()
          : name;

  bool get isOff => cachedIsOn == false || (cachedBrightness != null && cachedBrightness == 0);

  int get effectiveLedCount => ledCount ?? 150;
  int get effectiveMaxCurrentMa => maxCurrentMa ?? 3000;
  int get effectiveColorOrder => colorOrder ?? 0;
  int get effectiveTransitionStyle => transitionStyle ?? 0;
  int get effectiveAmbientStyle => ambientStyle ?? 1;
  int get effectiveAmbientDepth => ambientDepth ?? 6;
  String get effectiveRoomId => roomId ?? 'room_temple';

  double get stripLengthMeters => effectiveLedCount / 60.0;
  String get formattedLength => '${stripLengthMeters.toStringAsFixed(1)}m';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lastSeen': lastSeen.toIso8601String(),
        'customAlias': customAlias,
        'firmwareVersion': firmwareVersion,
        'cachedBrightness': cachedBrightness,
        'cachedMode': cachedMode,
        'cachedIsOn': cachedIsOn,
        'cachedR': cachedR,
        'cachedG': cachedG,
        'cachedB': cachedB,
        'ledCount': ledCount,
        'maxCurrentMa': maxCurrentMa,
        'colorOrder': colorOrder,
        'transitionStyle': transitionStyle,
        'ambientStyle': ambientStyle,
        'ambientDepth': ambientDepth,
        'roomId': roomId,
        'activePresetIndex': activePresetIndex,
        if (segments != null) 'segments': segments!.map((s) => s.toJson()).toList(),
        if (isGoogleHomeLinked != null) 'isGoogleHomeLinked': isGoogleHomeLinked,
        if (rainmakerNodeId != null) 'rainmakerNodeId': rainmakerNodeId,
      };

  factory PairedDevice.fromJson(Map<String, dynamic> json) => PairedDevice(
        id: json['id'] as String? ?? 'unknown_device',
        name: json['name'] as String? ?? 'Temple Lights',
        lastSeen: DateTime.tryParse(json['lastSeen'] as String? ?? '') ?? DateTime.now(),
        customAlias: json['customAlias'] as String?,
        firmwareVersion: json['firmwareVersion'] as String?,
        cachedBrightness: (json['cachedBrightness'] as num?)?.toInt(),
        cachedMode: (json['cachedMode'] as num?)?.toInt(),
        cachedIsOn: json['cachedIsOn'] as bool?,
        cachedR: (json['cachedR'] as num?)?.toInt(),
        cachedG: (json['cachedG'] as num?)?.toInt(),
        cachedB: (json['cachedB'] as num?)?.toInt(),
        ledCount: (json['ledCount'] as num?)?.toInt(),
        maxCurrentMa: (json['maxCurrentMa'] as num?)?.toInt(),
        colorOrder: (json['colorOrder'] as num?)?.toInt(),
        transitionStyle: (json['transitionStyle'] as num?)?.toInt(),
        ambientStyle: (json['ambientStyle'] as num?)?.toInt(),
        ambientDepth: (json['ambientDepth'] as num?)?.toInt(),
        roomId: json['roomId'] as String?,
        activePresetIndex: (json['activePresetIndex'] as num?)?.toInt(),
        segments: (json['segments'] as List<dynamic>?)
            ?.map((e) => LedSegment.fromJson(e as Map<String, dynamic>))
            .toList(),
        isGoogleHomeLinked: json['isGoogleHomeLinked'] as bool?,
        rainmakerNodeId: json['rainmakerNodeId'] as String?,
      );

  PairedDevice copyWith({
    String? id,
    String? name,
    DateTime? lastSeen,
    String? customAlias,
    String? firmwareVersion,
    int? cachedBrightness,
    int? cachedMode,
    bool? cachedIsOn,
    int? cachedR,
    int? cachedG,
    int? cachedB,
    int? ledCount,
    int? maxCurrentMa,
    int? colorOrder,
    int? transitionStyle,
    int? ambientStyle,
    int? ambientDepth,
    String? roomId,
    int? activePresetIndex,
    List<LedSegment>? segments,
    bool? isGoogleHomeLinked,
    String? rainmakerNodeId,
  }) =>
      PairedDevice(
        id: id ?? this.id,
        name: name ?? this.name,
        lastSeen: lastSeen ?? this.lastSeen,
        customAlias: customAlias ?? this.customAlias,
        firmwareVersion: firmwareVersion ?? this.firmwareVersion,
        cachedBrightness: cachedBrightness ?? this.cachedBrightness,
        cachedMode: cachedMode ?? this.cachedMode,
        cachedIsOn: cachedIsOn ?? this.cachedIsOn,
        cachedR: cachedR ?? this.cachedR,
        cachedG: cachedG ?? this.cachedG,
        cachedB: cachedB ?? this.cachedB,
        ledCount: ledCount ?? this.ledCount,
        maxCurrentMa: maxCurrentMa ?? this.maxCurrentMa,
        colorOrder: colorOrder ?? this.colorOrder,
        transitionStyle: transitionStyle ?? this.transitionStyle,
        ambientStyle: ambientStyle ?? this.ambientStyle,
        ambientDepth: ambientDepth ?? this.ambientDepth,
        roomId: roomId ?? this.roomId,
        activePresetIndex: activePresetIndex ?? this.activePresetIndex,
        segments: segments ?? this.segments,
        isGoogleHomeLinked: isGoogleHomeLinked ?? this.isGoogleHomeLinked,
        rainmakerNodeId: rainmakerNodeId ?? this.rainmakerNodeId,
      );
}

enum ScheduleTriggerAction { turnOn, turnOff }

class LightSchedule {
  const LightSchedule({
    required this.id,
    required this.name,
    this.isEnabled = true,
    this.hasTurnOn = true,
    this.turnOnHour = 18,
    this.turnOnMinute = 0,
    this.hasTurnOff = true,
    this.turnOffHour = 6,
    this.turnOffMinute = 0,
    this.repeatDays = const [1, 2, 3, 4, 5, 6, 7],
    this.lastTriggeredKey,
    this.targetMode = 0,
    this.targetBrightness = 255,
    this.targetR = 255,
    this.targetG = 147,
    this.targetB = 41,
  });

  final String id;
  final String name;
  final bool isEnabled;
  final bool hasTurnOn;
  final int turnOnHour;
  final int turnOnMinute;
  final bool hasTurnOff;
  final int turnOffHour;
  final int turnOffMinute;
  final List<int> repeatDays;
  final String? lastTriggeredKey;
  final int targetMode;
  final int targetBrightness;
  final int targetR;
  final int targetG;
  final int targetB;

  int get targetBrightnessPercent => ((targetBrightness / 255.0) * 100).round().clamp(0, 100);

  String get targetModeName {
    switch (targetMode) {
      case 0:
        return 'Warm White (All)';
      case 1:
        return 'Center Warm (1.5m)';
      case 2:
        return 'Pure White (All)';
      case 3:
        return 'Custom Color';
      default:
        return 'Mode $targetMode';
    }
  }

  static String formatTime12h(int hour, int minute) {
    final period = hour >= 12 ? 'PM' : 'AM';
    final h = hour % 12 == 0 ? 12 : hour % 12;
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m $period';
  }

  String get formattedTurnOnTime => formatTime12h(turnOnHour, turnOnMinute);
  String get formattedTurnOffTime => formatTime12h(turnOffHour, turnOffMinute);

  String get repeatDaysSummary {
    if (repeatDays.isEmpty) return 'Never';
    if (repeatDays.length == 7) return 'Everyday';
    final sorted = List<int>.from(repeatDays)..sort();
    if (sorted.length == 5 &&
        sorted[0] == 1 &&
        sorted[1] == 2 &&
        sorted[2] == 3 &&
        sorted[3] == 4 &&
        sorted[4] == 5) {
      return 'Weekdays';
    }
    if (sorted.length == 2 && sorted[0] == 6 && sorted[1] == 7) {
      return 'Weekends';
    }
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return sorted.map((d) => dayNames[d - 1]).join(', ');
  }

  ScheduleTriggerAction? evaluateTrigger(DateTime now) {
    if (!isEnabled) return null;
    if (!repeatDays.contains(now.weekday)) return null;

    final nowHour = now.hour;
    final nowMinute = now.minute;

    if (hasTurnOn && nowHour == turnOnHour && nowMinute == turnOnMinute) {
      final key = 'ON_${now.year}_${now.month}_${now.day}_${nowHour}_$nowMinute';
      if (lastTriggeredKey != key) {
        return ScheduleTriggerAction.turnOn;
      }
    }

    if (hasTurnOff && nowHour == turnOffHour && nowMinute == turnOffMinute) {
      final key = 'OFF_${now.year}_${now.month}_${now.day}_${nowHour}_$nowMinute';
      if (lastTriggeredKey != key) {
        return ScheduleTriggerAction.turnOff;
      }
    }

    return null;
  }

  LightSchedule copyWith({
    String? id,
    String? name,
    bool? isEnabled,
    bool? hasTurnOn,
    int? turnOnHour,
    int? turnOnMinute,
    bool? hasTurnOff,
    int? turnOffHour,
    int? turnOffMinute,
    List<int>? repeatDays,
    String? lastTriggeredKey,
    int? targetMode,
    int? targetBrightness,
    int? targetR,
    int? targetG,
    int? targetB,
  }) =>
      LightSchedule(
        id: id ?? this.id,
        name: name ?? this.name,
        isEnabled: isEnabled ?? this.isEnabled,
        hasTurnOn: hasTurnOn ?? this.hasTurnOn,
        turnOnHour: turnOnHour ?? this.turnOnHour,
        turnOnMinute: turnOnMinute ?? this.turnOnMinute,
        hasTurnOff: hasTurnOff ?? this.hasTurnOff,
        turnOffHour: turnOffHour ?? this.turnOffHour,
        turnOffMinute: turnOffMinute ?? this.turnOffMinute,
        repeatDays: repeatDays ?? this.repeatDays,
        lastTriggeredKey: lastTriggeredKey ?? this.lastTriggeredKey,
        targetMode: targetMode ?? this.targetMode,
        targetBrightness: targetBrightness ?? this.targetBrightness,
        targetR: targetR ?? this.targetR,
        targetG: targetG ?? this.targetG,
        targetB: targetB ?? this.targetB,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isEnabled': isEnabled,
        'hasTurnOn': hasTurnOn,
        'turnOnHour': turnOnHour,
        'turnOnMinute': turnOnMinute,
        'hasTurnOff': hasTurnOff,
        'turnOffHour': turnOffHour,
        'turnOffMinute': turnOffMinute,
        'repeatDays': repeatDays,
        'lastTriggeredKey': lastTriggeredKey,
        'targetMode': targetMode,
        'targetBrightness': targetBrightness,
        'targetR': targetR,
        'targetG': targetG,
        'targetB': targetB,
      };

  factory LightSchedule.fromJson(Map<String, dynamic> json) => LightSchedule(
        id: json['id'] as String? ?? 'sched_${DateTime.now().millisecondsSinceEpoch}',
        name: json['name'] as String? ?? 'Temple Schedule',
        isEnabled: json['isEnabled'] as bool? ?? true,
        hasTurnOn: json['hasTurnOn'] as bool? ?? true,
        turnOnHour: (json['turnOnHour'] as num?)?.toInt() ?? 18,
        turnOnMinute: (json['turnOnMinute'] as num?)?.toInt() ?? 0,
        hasTurnOff: json['hasTurnOff'] as bool? ?? true,
        turnOffHour: (json['turnOffHour'] as num?)?.toInt() ?? 6,
        turnOffMinute: (json['turnOffMinute'] as num?)?.toInt() ?? 0,
        repeatDays: (json['repeatDays'] as List<dynamic>?)
                ?.map((e) => (e as num).toInt())
                .toList() ??
            const [1, 2, 3, 4, 5, 6, 7],
        lastTriggeredKey: json['lastTriggeredKey'] as String?,
        targetMode: (json['targetMode'] as num?)?.toInt() ?? 0,
        targetBrightness: (json['targetBrightness'] as num?)?.toInt() ?? 255,
        targetR: (json['targetR'] as num?)?.toInt() ?? 255,
        targetG: (json['targetG'] as num?)?.toInt() ?? 147,
        targetB: (json['targetB'] as num?)?.toInt() ?? 41,
      );
}

class AutoOffTimerState {
  const AutoOffTimerState({
    this.isRunning = false,
    this.totalSeconds = 15 * 60,
    this.remainingSeconds = 0,
    this.selectedMinutes = 15,
    this.startedAt,
    this.endsAt,
  });

  final bool isRunning;
  final int totalSeconds;
  final int remainingSeconds;
  final int selectedMinutes;
  final DateTime? startedAt;
  final DateTime? endsAt;

  double get progress {
    if (!isRunning || totalSeconds <= 0) return 0.0;
    return (1.0 - (remainingSeconds / totalSeconds)).clamp(0.0, 1.0);
  }

  String get formattedRemaining {
    if (!isRunning || remainingSeconds <= 0) return '00:00';
    final hours = remainingSeconds ~/ 3600;
    final mins = (remainingSeconds % 3600) ~/ 60;
    final secs = remainingSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  static String formatMinutes(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (m == 0) return '$h hr';
    return '${h}h ${m}m';
  }

  String get formattedSelectedDuration => formatMinutes(selectedMinutes);

  AutoOffTimerState copyWith({
    bool? isRunning,
    int? totalSeconds,
    int? remainingSeconds,
    int? selectedMinutes,
    DateTime? startedAt,
    DateTime? endsAt,
    bool clearDates = false,
  }) =>
      AutoOffTimerState(
        isRunning: isRunning ?? this.isRunning,
        totalSeconds: totalSeconds ?? this.totalSeconds,
        remainingSeconds: remainingSeconds ?? this.remainingSeconds,
        selectedMinutes: selectedMinutes ?? this.selectedMinutes,
        startedAt: clearDates ? null : (startedAt ?? this.startedAt),
        endsAt: clearDates ? null : (endsAt ?? this.endsAt),
      );

  Map<String, dynamic> toJson() => {
        'selectedMinutes': selectedMinutes,
      };

  factory AutoOffTimerState.fromJson(Map<String, dynamic> json) =>
      AutoOffTimerState(
        selectedMinutes: json['selectedMinutes'] as int? ?? 15,
        totalSeconds: (json['selectedMinutes'] as int? ?? 15) * 60,
      );

  static const idle = AutoOffTimerState();
}

class LightLogEntry {
  const LightLogEntry({
    required this.id,
    required this.isOn,
    required this.timestamp,
    this.durationSeconds = 0,
    this.source = 'BLE App',
    this.mode = 0,
    this.brightness = 255,
  });

  final String id;
  final bool isOn;
  final DateTime timestamp;
  final int durationSeconds;
  final String source;
  final int mode;
  final int brightness;

  String get formattedTime {
    final hour = timestamp.hour;
    final minute = timestamp.minute;
    final sec = timestamp.second;
    final period = hour >= 12 ? 'PM' : 'AM';
    final h = hour % 12 == 0 ? 12 : hour % 12;
    final m = minute.toString().padLeft(2, '0');
    final s = sec.toString().padLeft(2, '0');
    return '$h:$m:$s $period';
  }

  String get formattedDate {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final now = DateTime.now();
    if (timestamp.year == now.year && timestamp.month == now.month && timestamp.day == now.day) {
      return 'Today';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (timestamp.year == yesterday.year && timestamp.month == yesterday.month && timestamp.day == yesterday.day) {
      return 'Yesterday';
    }
    return '${months[timestamp.month - 1]} ${timestamp.day}, ${timestamp.year}';
  }

  String get formattedDateTime => '$formattedDate • $formattedTime';

  String get formattedDuration {
    if (durationSeconds <= 0) return '0s';
    final h = durationSeconds ~/ 3600;
    final m = (durationSeconds % 3600) ~/ 60;
    final s = durationSeconds % 60;
    if (h > 0) {
      return m > 0 ? '${h}h ${m}m ${s}s' : '${h}h ${s}s';
    }
    if (m > 0) {
      return '${m}m ${s}s';
    }
    return '${s}s';
  }

  String get relativeTime {
    final diff = DateTime.now().difference(timestamp);
    if (diff.isNegative || diff.inSeconds < 10) return 'Just now';
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return formattedDate;
  }

  LightLogEntry copyWith({
    String? id,
    bool? isOn,
    DateTime? timestamp,
    int? durationSeconds,
    String? source,
    int? mode,
    int? brightness,
  }) =>
      LightLogEntry(
        id: id ?? this.id,
        isOn: isOn ?? this.isOn,
        timestamp: timestamp ?? this.timestamp,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        source: source ?? this.source,
        mode: mode ?? this.mode,
        brightness: brightness ?? this.brightness,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'isOn': isOn,
        'timestamp': timestamp.toIso8601String(),
        'durationSeconds': durationSeconds,
        'source': source,
        'mode': mode,
        'brightness': brightness,
      };

  factory LightLogEntry.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? 'log_${DateTime.now().millisecondsSinceEpoch}').toString();
    final isOn = json['on'] as bool? ?? (json['isOn'] as bool? ?? false);

    DateTime ts;
    if (json['y'] != null && json['mon'] != null && json['d'] != null) {
      ts = DateTime(
        json['y'] as int? ?? 2026,
        json['mon'] as int? ?? 1,
        json['d'] as int? ?? 1,
        json['h'] as int? ?? 0,
        json['m'] as int? ?? 0,
        json['s'] as int? ?? 0,
      );
    } else if (json['epoch'] != null && (json['epoch'] as num) > 0) {
      ts = DateTime.fromMillisecondsSinceEpoch((json['epoch'] as num).toInt() * 1000);
    } else if (json['timestamp'] != null) {
      ts = DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now();
    } else {
      ts = DateTime.now();
    }

    final dur = (json['dur'] as num?)?.toInt() ?? (json['durationSeconds'] as num?)?.toInt() ?? 0;
    final src = json['src'] as String? ?? json['source'] as String? ?? (isOn ? 'Lights ON' : 'Lights OFF');
    final m = (json['mode'] as num?)?.toInt() ?? 0;
    final b = (json['bright'] as num?)?.toInt() ?? (json['brightness'] as num?)?.toInt() ?? 255;

    return LightLogEntry(
      id: id,
      isOn: isOn,
      timestamp: ts,
      durationSeconds: dur,
      source: src,
      mode: m,
      brightness: b,
    );
  }
}

class DefaultModeConfig {
  const DefaultModeConfig({
    required this.index,
    required this.name,
    required this.r,
    required this.g,
    required this.b,
    this.style = 0, // 0 = Full Strip, 1 = Center 1.5m
    this.brightness = 255,
  });

  final int index;
  final String name;
  final int r;
  final int g;
  final int b;
  final int style; // 0 = Full Strip, 1 = Center Focus (1.5m)
  final int brightness;

  bool get isFullStrip => style == 0;
  bool get isCenterFocus => style == 1;

  int get brightnessPercent => ((brightness / 255.0) * 100).round().clamp(1, 100);

  String get styleLabel => isCenterFocus ? 'Center Focus (1.5m)' : 'Full Strip (2.5m)';

  DefaultModeConfig copyWith({
    int? index,
    String? name,
    int? r,
    int? g,
    int? b,
    int? style,
    int? brightness,
  }) =>
      DefaultModeConfig(
        index: index ?? this.index,
        name: name ?? this.name,
        r: r ?? this.r,
        g: g ?? this.g,
        b: b ?? this.b,
        style: style ?? this.style,
        brightness: brightness ?? this.brightness,
      );

  Map<String, dynamic> toJson() => {
        'idx': index,
        'name': name,
        'r': r,
        'g': g,
        'b': b,
        'style': style,
        'bright': brightness,
      };

  factory DefaultModeConfig.fromJson(Map<String, dynamic> json) => DefaultModeConfig(
        index: (json['idx'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? 'Mode',
        r: (json['r'] as num?)?.toInt() ?? 255,
        g: (json['g'] as num?)?.toInt() ?? 147,
        b: (json['b'] as num?)?.toInt() ?? 41,
        style: (json['style'] as num?)?.toInt() ?? 0,
        brightness: (json['bright'] as num?)?.toInt() ?? 255,
      );

  static const List<DefaultModeConfig> factoryDefaults = [
    DefaultModeConfig(
      index: 0,
      name: 'Warm White',
      r: 255,
      g: 147,
      b: 41,
      style: 0, // Full strip
      brightness: 255,
    ),
    DefaultModeConfig(
      index: 1,
      name: 'Center Warm',
      r: 255,
      g: 147,
      b: 41,
      style: 1, // Center 1.5m
      brightness: 255,
    ),
    DefaultModeConfig(
      index: 2,
      name: 'Pure White',
      r: 255,
      g: 255,
      b: 255,
      style: 0, // Full strip
      brightness: 255,
    ),
  ];
}

class LightPreset {
  const LightPreset({
    required this.index,
    required this.name,
    this.brightness = 255,
    this.transitionStyle = 0,
    this.ambientStyle = 1,
    this.ambientDepth = 6,
    this.cycleEnabled = true,
    this.segments = const [],
    this.r = 255,
    this.g = 147,
    this.b = 41,
  });

  final int index;
  final String name;
  final int brightness;
  final int transitionStyle;
  final int ambientStyle;
  final int ambientDepth;
  final bool cycleEnabled;
  final List<LedSegment> segments;
  final int r, g, b;

  int get brightnessPercent => ((brightness / 255.0) * 100).round().clamp(1, 100);

  Color get color => Color.fromARGB(255, r, g, b);

  String get ambientStyleName {
    if (ambientStyle >= 0 && ambientStyle < LightState.ambientStyleNames.length) {
      return LightState.ambientStyleNames[ambientStyle];
    }
    return LightState.ambientStyleNames[1];
  }

  String get transitionStyleName {
    if (transitionStyle >= 0 && transitionStyle < LightState.transitionStyleNames.length) {
      return LightState.transitionStyleNames[transitionStyle];
    }
    return LightState.transitionStyleNames[0];
  }

  LightPreset copyWith({
    int? index,
    String? name,
    int? brightness,
    int? transitionStyle,
    int? ambientStyle,
    int? ambientDepth,
    bool? cycleEnabled,
    List<LedSegment>? segments,
    int? r,
    int? g,
    int? b,
  }) =>
      LightPreset(
        index: index ?? this.index,
        name: name ?? this.name,
        brightness: brightness ?? this.brightness,
        transitionStyle: transitionStyle ?? this.transitionStyle,
        ambientStyle: ambientStyle ?? this.ambientStyle,
        ambientDepth: ambientDepth ?? this.ambientDepth,
        cycleEnabled: cycleEnabled ?? this.cycleEnabled,
        segments: segments ?? this.segments,
        r: r ?? this.r,
        g: g ?? this.g,
        b: b ?? this.b,
      );

  Map<String, dynamic> toJson() => {
        'idx': index,
        'name': name,
        'bright': brightness,
        'trans': transitionStyle,
        'amb': ambientStyle,
        'depth': ambientDepth,
        'cycle': cycleEnabled,
        'r': r,
        'g': g,
        'b': b,
        'segs': segments.map((s) => s.toJson()).toList(),
      };

  factory LightPreset.fromJson(Map<String, dynamic> json) => LightPreset(
        index: (json['idx'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? 'Preset',
        brightness: (json['bright'] as num?)?.toInt() ?? 255,
        transitionStyle: (json['trans'] as num?)?.toInt() ?? 0,
        ambientStyle: (json['amb'] as num?)?.toInt() ?? 1,
        ambientDepth: (json['depth'] as num?)?.toInt() ?? 6,
        cycleEnabled: json['cycle'] as bool? ?? true,
        r: (json['r'] as num?)?.toInt() ?? 255,
        g: (json['g'] as num?)?.toInt() ?? 147,
        b: (json['b'] as num?)?.toInt() ?? 41,
        segments: (json['segs'] as List<dynamic>?)
                ?.map((e) => LedSegment.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  /// Converts legacy DefaultModeConfig to modern LightPreset
  factory LightPreset.fromLegacyDefaultMode(DefaultModeConfig mode, {int totalLeds = 150}) {
    List<LedSegment> segs;
    if (mode.style == 1) {
      final midStart = (totalLeds * 0.20).round();
      final midCount = totalLeds - (midStart * 2);
      segs = [
        LedSegment(
          start: midStart,
          count: midCount,
          r: mode.r,
          g: mode.g,
          b: mode.b,
          brightness: mode.brightness,
          name: 'Center Focus (1.5m)',
        ),
      ];
    } else {
      segs = [
        LedSegment(
          start: 0,
          count: totalLeds,
          r: mode.r,
          g: mode.g,
          b: mode.b,
          brightness: mode.brightness,
          name: 'Full Strip',
        ),
      ];
    }
    return LightPreset(
      index: mode.index,
      name: mode.name,
      brightness: mode.brightness,
      transitionStyle: 0,
      ambientStyle: 1,
      ambientDepth: 6,
      cycleEnabled: true,
      segments: segs,
      r: mode.r,
      g: mode.g,
      b: mode.b,
    );
  }

  static List<LightPreset> defaultPresets({int totalLeds = 150}) => [
        LightPreset(
          index: 0,
          name: 'Warm White Full',
          brightness: 255,
          transitionStyle: 0,
          ambientStyle: 1,
          cycleEnabled: true,
          r: 255,
          g: 147,
          b: 41,
          segments: [
            LedSegment(start: 0, count: totalLeds, r: 255, g: 147, b: 41, name: 'Full Warm'),
          ],
        ),
        LightPreset(
          index: 1,
          name: 'Center Warm Focus',
          brightness: 255,
          transitionStyle: 0,
          ambientStyle: 1,
          cycleEnabled: true,
          r: 255,
          g: 147,
          b: 41,
          segments: [
            LedSegment(
              start: (totalLeds * 0.20).round(),
              count: (totalLeds * 0.60).round(),
              r: 255,
              g: 147,
              b: 41,
              name: 'Center 1.5m',
            ),
          ],
        ),
        LightPreset(
          index: 2,
          name: 'Pure White Full',
          brightness: 255,
          transitionStyle: 0,
          ambientStyle: 1,
          cycleEnabled: true,
          r: 255,
          g: 255,
          b: 255,
          segments: [
            LedSegment(start: 0, count: totalLeds, r: 255, g: 255, b: 255, name: 'Full White'),
          ],
        ),
        LightPreset(
          index: 3,
          name: 'Pillar Highlight & Halo',
          brightness: 255,
          transitionStyle: 3, // Dual convergence
          ambientStyle: 2,    // Diya flutter
          cycleEnabled: false,
          r: 255,
          g: 180,
          b: 0,
          segments: [
            LedSegment(start: 0, count: 6, r: 255, g: 147, b: 41, name: 'Base 1–6'),
            LedSegment(
              start: totalLeds >= 106 ? 100 : totalLeds - 6,
              count: 6,
              r: 255,
              g: 255,
              b: 255,
              name: 'Apex 100–105',
            ),
          ],
        ),
        LightPreset(
          index: 4,
          name: 'Aarti Sacred Embers',
          brightness: 240,
          transitionStyle: 4, // Sparkle ignition
          ambientStyle: 4,    // Sacred amber embers
          cycleEnabled: false,
          r: 255,
          g: 120,
          b: 20,
          segments: [
            LedSegment(start: 0, count: totalLeds, r: 255, g: 120, b: 20, effect: 4, name: 'Sacred Fire'),
          ],
        ),
      ];
}

class RoomModel {
  const RoomModel({
    required this.id,
    required this.name,
    this.iconName = 'temple',
    this.deviceIds = const [],
  });

  final String id;
  final String name;
  final String iconName;
  final List<String> deviceIds;

  String get iconEmoji {
    switch (iconName.toLowerCase()) {
      case 'temple':
      case 'mandir':
        return '🛕';
      case 'living':
      case 'living_room':
        return '🛋️';
      case 'bed':
      case 'bedroom':
        return '🛏️';
      case 'dining':
        return '🍽️';
      case 'balcony':
        return '🪴';
      default:
        return '🏠';
    }
  }

  RoomModel copyWith({
    String? id,
    String? name,
    String? iconName,
    List<String>? deviceIds,
  }) =>
      RoomModel(
        id: id ?? this.id,
        name: name ?? this.name,
        iconName: iconName ?? this.iconName,
        deviceIds: deviceIds ?? this.deviceIds,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'icon': iconName,
        'devs': deviceIds,
      };

  factory RoomModel.fromJson(Map<String, dynamic> json) => RoomModel(
        id: json['id'] as String? ?? 'room_${DateTime.now().millisecondsSinceEpoch}',
        name: json['name'] as String? ?? 'Room',
        iconName: json['icon'] as String? ?? 'temple',
        deviceIds: (json['devs'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );

  static const List<RoomModel> defaultRooms = [
    RoomModel(id: 'room_temple', name: 'Puja Mandir', iconName: 'temple'),
    RoomModel(id: 'room_living', name: 'Living Room', iconName: 'living'),
    RoomModel(id: 'room_bedroom', name: 'Master Bedroom', iconName: 'bedroom'),
  ];
}

class SacredScene {
  const SacredScene({
    required this.id,
    required this.name,
    required this.emoji,
    required this.subtitle,
    required this.kelvin,
    required this.r,
    required this.g,
    required this.b,
    required this.brightness,
    required this.transitionStyle,
    required this.ambientStyle,
    this.ambientDepth = 50,
  });

  final String id;
  final String name;
  final String emoji;
  final String subtitle;
  final int kelvin;
  final int r;
  final int g;
  final int b;
  final int brightness;
  final int transitionStyle;
  final int ambientStyle;
  final int ambientDepth;

  static const List<SacredScene> defaultScenes = [
    SacredScene(
      id: 'scene_aarti',
      name: 'Morning Aarti',
      emoji: '🌅',
      subtitle: 'Warm Dawn Radiance',
      kelvin: 3200,
      r: 255,
      g: 170,
      b: 80,
      brightness: 255,
      transitionStyle: 1, // Sunrise Sweep
      ambientStyle: 1,    // Gentle Breathe
    ),
    SacredScene(
      id: 'scene_diya',
      name: 'Evening Diya',
      emoji: '🪔',
      subtitle: 'Candlelight Flutter',
      kelvin: 2200,
      r: 255,
      g: 147,
      b: 41,
      brightness: 210,
      transitionStyle: 0, // Center Out
      ambientStyle: 2,    // Diya Flutter
    ),
    SacredScene(
      id: 'scene_starlight',
      name: 'Temple Starlight',
      emoji: '✨',
      subtitle: 'Golden Shimmer',
      kelvin: 2700,
      r: 255,
      g: 185,
      b: 70,
      brightness: 140,
      transitionStyle: 4, // Sparkle Ignition
      ambientStyle: 3,    // Temple Twinkle
    ),
    SacredScene(
      id: 'scene_night',
      name: 'Night Sanctuary',
      emoji: '🌙',
      subtitle: 'Gentle Amber Glow',
      kelvin: 2000,
      r: 255,
      g: 120,
      b: 20,
      brightness: 35,
      transitionStyle: 6, // Uniform Cinema Fade
      ambientStyle: 0,    // Pure Solid
    ),
    SacredScene(
      id: 'scene_aurora',
      name: 'Divine Aura',
      emoji: '🌈',
      subtitle: 'Sacred Hue Flow',
      kelvin: 4000,
      r: 255,
      g: 180,
      b: 100,
      brightness: 190,
      transitionStyle: 5, // Domino Cascade
      ambientStyle: 5,    // Aurora Wave
    ),
  ];
}

enum WifiPhase {
  idle,
  scanning,
  connecting,
  gotIp,
  internetOk,
  saved,
  connected,
  failed,
  disconnected,
}

class WifiNetworkItem {
  const WifiNetworkItem({
    required this.ssid,
    required this.rssi,
    required this.auth,
  });

  final String ssid;
  final int rssi;
  final String auth;

  bool get isSecured => auth.toUpperCase() != 'OPEN' && auth.isNotEmpty;

  int get signalBars {
    if (rssi >= -60) return 3;
    if (rssi >= -75) return 2;
    return 1;
  }

  factory WifiNetworkItem.fromJson(Map<String, dynamic> json) => WifiNetworkItem(
        ssid: json['ssid'] as String? ?? '',
        rssi: (json['rssi'] as num?)?.toInt() ?? -100,
        auth: json['auth'] as String? ?? 'WPA2',
      );

  Map<String, dynamic> toJson() => {
        'ssid': ssid,
        'rssi': rssi,
        'auth': auth,
      };
}

class WifiConnectionState {
  const WifiConnectionState({
    this.phase = WifiPhase.idle,
    this.currentSsid = '',
    this.ipAddress = '',
    this.rssi = 0,
    this.failureReason = 'none',
    this.scannedNetworks = const [],
    this.isScanning = false,
    this.lastNtpSyncEpoch,
  });

  final WifiPhase phase;
  final String currentSsid;
  final String ipAddress;
  final int rssi;
  final String failureReason;
  final List<WifiNetworkItem> scannedNetworks;
  final bool isScanning;
  final int? lastNtpSyncEpoch;

  bool get isConnected => phase == WifiPhase.connected && ipAddress.isNotEmpty;
  bool get isConnecting => phase == WifiPhase.connecting || phase == WifiPhase.gotIp || phase == WifiPhase.internetOk;
  bool get hasFailed => phase == WifiPhase.failed;

  String get humanReadableStatus {
    switch (phase) {
      case WifiPhase.scanning:
        return 'Scanning 2.4 GHz networks…';
      case WifiPhase.connecting:
        return 'Connecting to $currentSsid…';
      case WifiPhase.gotIp:
        return 'IP assigned ($ipAddress)…';
      case WifiPhase.internetOk:
        return 'Internet verified…';
      case WifiPhase.saved:
        return 'Credentials saved';
      case WifiPhase.connected:
        return currentSsid.isNotEmpty ? 'Connected ($currentSsid)' : 'Connected';
      case WifiPhase.failed:
        return 'Connection failed: $failureReason';
      case WifiPhase.disconnected:
        return 'Disconnected';
      case WifiPhase.idle:
        return 'Not Configured';
    }
  }

  WifiConnectionState copyWith({
    WifiPhase? phase,
    String? currentSsid,
    String? ipAddress,
    int? rssi,
    String? failureReason,
    List<WifiNetworkItem>? scannedNetworks,
    bool? isScanning,
    int? lastNtpSyncEpoch,
  }) =>
      WifiConnectionState(
        phase: phase ?? this.phase,
        currentSsid: currentSsid ?? this.currentSsid,
        ipAddress: ipAddress ?? this.ipAddress,
        rssi: rssi ?? this.rssi,
        failureReason: failureReason ?? this.failureReason,
        scannedNetworks: scannedNetworks ?? this.scannedNetworks,
        isScanning: isScanning ?? this.isScanning,
        lastNtpSyncEpoch: lastNtpSyncEpoch ?? this.lastNtpSyncEpoch,
      );

  static const idle = WifiConnectionState();
}

