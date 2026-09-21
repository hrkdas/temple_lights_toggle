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
  });

  final bool isOn;
  final int mode;
  final int brightness;
  final int r, g, b;
  final bool isSending;
  final DateTime? lastToggled;
  final String? firmwareVersion;

  bool get isOff => !isOn || brightness == 0;

  String get modeName {
    switch (mode) {
      case 0:
        return 'Warm White (All 2.5m)';
      case 1:
        return 'Warm White (Center 1.5m)';
      case 2:
        return 'Pure White (All 2.5m)';
      case 3:
        return 'Custom RGB';
      default:
        return 'Mode $mode';
    }
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
  });

  final String id;
  String name;
  DateTime lastSeen;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lastSeen': lastSeen.toIso8601String(),
      };

  factory PairedDevice.fromJson(Map<String, dynamic> json) => PairedDevice(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Temple Lights',
        lastSeen: DateTime.tryParse(json['lastSeen'] as String? ?? '') ?? DateTime.now(),
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
        turnOnHour: json['turnOnHour'] as int? ?? 18,
        turnOnMinute: json['turnOnMinute'] as int? ?? 0,
        hasTurnOff: json['hasTurnOff'] as bool? ?? true,
        turnOffHour: json['turnOffHour'] as int? ?? 6,
        turnOffMinute: json['turnOffMinute'] as int? ?? 0,
        repeatDays: (json['repeatDays'] as List<dynamic>?)
                ?.map((e) => e as int)
                .toList() ??
            const [1, 2, 3, 4, 5, 6, 7],
        lastTriggeredKey: json['lastTriggeredKey'] as String?,
        targetMode: json['targetMode'] as int? ?? 0,
        targetBrightness: json['targetBrightness'] as int? ?? 255,
        targetR: json['targetR'] as int? ?? 255,
        targetG: json['targetG'] as int? ?? 147,
        targetB: json['targetB'] as int? ?? 41,
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

