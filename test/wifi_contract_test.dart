import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:temple_lights_toggle/contract/light_contract.dart';
import 'package:temple_lights_toggle/domain/models.dart';
import 'package:temple_lights_toggle/ui/widgets/wifi_signal_icon.dart';

void main() {
  group('Temple Lights WiFi & NTP Contract Tests (Dual-Slot Support)', () {
    test('LightPacketEncoder encodes WiFi scan command', () {
      final bytes = LightPacketEncoder.encodeWifiScan();
      final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      expect(map['cmd'], equals('wifi_scan'));
    });

    test('LightPacketEncoder encodes WiFi connect command with slot 1 default', () {
      final bytes = LightPacketEncoder.encodeWifiConnect(
        ssid: 'TempleNet_2.4G',
        psk: 'DivinePassword108',
        save: true,
      );
      final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      expect(map['cmd'], equals('wifi_connect'));
      expect(map['slot'], equals(1));
      expect(map['ssid'], equals('TempleNet_2.4G'));
      expect(map['psk'], equals('DivinePassword108'));
      expect(map['save'], isTrue);
    });

    test('LightPacketEncoder encodes WiFi connect command with explicit slot 2 backup', () {
      final bytes = LightPacketEncoder.encodeWifiConnect(
        ssid: 'Priest_Hotspot',
        psk: 'BackupSecret777',
        slot: 2,
        save: true,
      );
      final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      expect(map['cmd'], equals('wifi_connect'));
      expect(map['slot'], equals(2));
      expect(map['ssid'], equals('Priest_Hotspot'));
      expect(map['psk'], equals('BackupSecret777'));
      expect(map['save'], isTrue);
    });

    test('LightPacketEncoder encodes WiFi forget command for specific slot', () {
      final bytesSlot1 = LightPacketEncoder.encodeWifiForget(slot: 1);
      final map1 = jsonDecode(utf8.decode(bytesSlot1)) as Map<String, dynamic>;
      expect(map1['cmd'], equals('wifi_forget'));
      expect(map1['slot'], equals(1));

      final bytesAll = LightPacketEncoder.encodeWifiForget(slot: 0);
      final mapAll = jsonDecode(utf8.decode(bytesAll)) as Map<String, dynamic>;
      expect(mapAll['cmd'], equals('wifi_forget'));
      expect(mapAll['slot'], equals(0));
    });

    test('LightPacketEncoder encodes WiFi switch slot command', () {
      final bytes = LightPacketEncoder.encodeWifiSwitchSlot(slot: 2);
      final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      expect(map['cmd'], equals('wifi_switch_slot'));
      expect(map['slot'], equals(2));
    });

    test('LightPacketEncoder encodes WiFi status query command', () {
      final bytes = LightPacketEncoder.encodeWifiStatus();
      final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      expect(map['cmd'], equals('wifi_status'));
    });

    test('LightPacketEncoder encodes NTP trigger command', () {
      final bytes = LightPacketEncoder.encodeTriggerNtp();
      final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      expect(map['cmd'], equals('ntp_sync'));
    });

    test('LightPacketEncoder encodes time sync with timezone offset and epoch', () {
      final fixedEpoch = DateTime(2026, 9, 25, 12, 0, 0);
      final bytes = LightPacketEncoder.encodeTimeSync(fixedEpoch);
      final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      expect(map['cmd'], equals('time'));
      expect(map['epoch'], equals(fixedEpoch.millisecondsSinceEpoch ~/ 1000));
      expect(map['y'], equals(2026));
      expect(map['mon'], equals(9));
      expect(map['d'], equals(25));
      expect(map['h'], equals(12));
      expect(map['m'], equals(0));
      expect(map['s'], equals(0));
      expect(map['tz_min'], equals(fixedEpoch.timeZoneOffset.inMinutes));
    });
  });

  group('WifiNetworkItem Model & Signal Tests', () {
    test('WifiNetworkItem parses from ESP32 scan JSON', () {
      final rawJson = {
        'ssid': 'TempleSanctum_2G',
        'rssi': -58,
        'auth': 'WPA2',
      };

      final item = WifiNetworkItem.fromJson(rawJson);
      expect(item.ssid, equals('TempleSanctum_2G'));
      expect(item.rssi, equals(-58));
      expect(item.isSecured, isTrue);
      expect(item.auth, equals('WPA2'));
    });

    test('WifiNetworkItem recognizes open unencrypted networks', () {
      final openJson = {
        'ssid': 'TempleGuest_Open',
        'rssi': -70,
        'auth': 'OPEN',
      };

      final item = WifiNetworkItem.fromJson(openJson);
      expect(item.ssid, equals('TempleGuest_Open'));
      expect(item.isSecured, isFalse);
    });

    test('WifiNetworkItem computes signal bars and labels accurately', () {
      expect(const WifiNetworkItem(ssid: 'A', rssi: -50, auth: 'WPA2').signalBars, equals(3));
      expect(const WifiNetworkItem(ssid: 'B', rssi: -65, auth: 'WPA2').signalBars, equals(2));
      expect(const WifiNetworkItem(ssid: 'C', rssi: -85, auth: 'WPA2').signalBars, equals(1));

      expect(const WifiNetworkItem(ssid: 'A', rssi: -50, auth: 'WPA2').signalQualityLabel, equals('Excellent'));
      expect(const WifiNetworkItem(ssid: 'B', rssi: -65, auth: 'WPA2').signalQualityLabel, equals('Good'));
      expect(const WifiNetworkItem(ssid: 'C', rssi: -75, auth: 'WPA2').signalQualityLabel, equals('Fair'));
      expect(const WifiNetworkItem(ssid: 'D', rssi: -85, auth: 'WPA2').signalQualityLabel, equals('Weak'));
    });
  });

  group('WifiSignalIcon RSSI Mapping Tests', () {
    test('barsForRssi accurately categorizes signal levels', () {
      expect(WifiSignalIcon.barsForRssi(-50), equals(4)); // Excellent >= -55
      expect(WifiSignalIcon.barsForRssi(-62), equals(3)); // Good >= -68
      expect(WifiSignalIcon.barsForRssi(-74), equals(2)); // Fair >= -78
      expect(WifiSignalIcon.barsForRssi(-85), equals(1)); // Weak >= -88
      expect(WifiSignalIcon.barsForRssi(-95), equals(0)); // Out of range
      expect(WifiSignalIcon.barsForRssi(0), equals(0));   // Disconnected
    });

    test('qualityLabelForRssi provides user-friendly descriptions', () {
      expect(WifiSignalIcon.qualityLabelForRssi(-52), equals('Excellent'));
      expect(WifiSignalIcon.qualityLabelForRssi(-65), equals('Good'));
      expect(WifiSignalIcon.qualityLabelForRssi(-73), equals('Fair'));
      expect(WifiSignalIcon.qualityLabelForRssi(-83), equals('Weak'));
      expect(WifiSignalIcon.qualityLabelForRssi(-92), equals('Critical'));
      expect(WifiSignalIcon.qualityLabelForRssi(0), equals('No Signal'));
    });
  });

  group('WifiConnectionState Status Descriptions & Multi-Slot Progression', () {
    test('Reports connected status with Slot 1 active', () {
      const state = WifiConnectionState(
        phase: WifiPhase.connected,
        currentSsid: 'TempleNet_2.4G',
        ipAddress: '192.168.1.108',
        activeSlot: 1,
        slot1: WifiSlotItem(slot: 1, ssid: 'TempleNet_2.4G', isConfigured: true, isActive: true),
        slot2: WifiSlotItem(slot: 2, ssid: 'Priest_Hotspot', isConfigured: true, isActive: false),
      );

      expect(state.isConnected, isTrue);
      expect(state.isConnecting, isFalse);
      expect(state.activeSlot, equals(1));
      expect(state.hasSlot1, isTrue);
      expect(state.hasSlot2, isTrue);
      expect(state.hasAnySavedSlot, isTrue);
      expect(state.activeSlotItem?.ssid, equals('TempleNet_2.4G'));
      expect(state.humanReadableStatus, equals('Connected (TempleNet_2.4G [Slot 1])'));
    });

    test('Reports connecting phase status', () {
      const state = WifiConnectionState(
        phase: WifiPhase.connecting,
        currentSsid: 'TempleNet_2.4G',
        activeSlot: 1,
      );

      expect(state.isConnected, isFalse);
      expect(state.isConnecting, isTrue);
      expect(state.humanReadableStatus, equals('Connecting to TempleNet_2.4G…'));
    });

    test('Reports internet verified phase', () {
      const state = WifiConnectionState(
        phase: WifiPhase.internetOk,
        currentSsid: 'TempleNet_2.4G',
        ipAddress: '192.168.1.108',
      );

      expect(state.isConnecting, isTrue);
      expect(state.humanReadableStatus, equals('Internet verified…'));
    });

    test('Reports failure phase with reason', () {
      const state = WifiConnectionState(
        phase: WifiPhase.failed,
        failureReason: 'auth_failed',
      );

      expect(state.hasFailed, isTrue);
      expect(state.humanReadableStatus, equals('Connection failed: auth_failed'));
    });

    test('Reports backoff auto-recovery phase', () {
      const state = WifiConnectionState(
        phase: WifiPhase.backoff,
        slot1: WifiSlotItem(slot: 1, ssid: 'TempleNet_2.4G', isConfigured: true, isActive: false),
        slot2: WifiSlotItem(slot: 2, ssid: 'Priest_Hotspot', isConfigured: true, isActive: false),
      );

      expect(state.hasAnySavedSlot, isTrue);
      expect(state.humanReadableStatus, equals('Reconnecting between saved networks…'));
    });

    test('Reports idle state with saved networks ready', () {
      const state = WifiConnectionState(
        phase: WifiPhase.idle,
        slot1: WifiSlotItem(slot: 1, ssid: 'TempleNet_2.4G', isConfigured: true, isActive: false),
      );

      expect(state.isConnected, isFalse);
      expect(state.hasAnySavedSlot, isTrue);
      expect(state.humanReadableStatus, equals('Offline • Saved Networks Ready'));
    });
  });

  group('ESP32 Live JSON Notification Parsing Simulation (Dual-Slot & Backward Compatibility)', () {
    test('Parses enhanced dual-slot wifi_status notification JSON from firmware', () {
      const esp32Notification = '{"type":"wifi_status","state":"connected","reason":"none","ssid":"TempleSanctuary","ip":"192.168.31.200","rssi":-55,"active_slot":1,"slots":[{"slot":1,"ssid":"TempleSanctuary","configured":true,"active":true},{"slot":2,"ssid":"Temple_Backup","configured":true,"active":false}]}';
      final map = jsonDecode(esp32Notification) as Map<String, dynamic>;

      expect(map['type'], equals('wifi_status'));
      expect(map['state'], equals('connected'));
      expect(map['ssid'], equals('TempleSanctuary'));
      expect(map['ip'], equals('192.168.31.200'));
      expect(map['rssi'], equals(-55));
      expect(map['active_slot'], equals(1));

      final slots = map['slots'] as List<dynamic>;
      expect(slots.length, equals(2));
      final slot1 = WifiSlotItem.fromJson(slots[0] as Map<String, dynamic>);
      expect(slot1.slot, equals(1));
      expect(slot1.ssid, equals('TempleSanctuary'));
      expect(slot1.isConfigured, isTrue);
      expect(slot1.isActive, isTrue);

      final slot2 = WifiSlotItem.fromJson(slots[1] as Map<String, dynamic>);
      expect(slot2.slot, equals(2));
      expect(slot2.ssid, equals('Temple_Backup'));
      expect(slot2.isConfigured, isTrue);
      expect(slot2.isActive, isFalse);
    });

    test('Backward Compatibility: Parses legacy v1 notification JSON without slots array cleanly', () {
      const legacyEsp32Notification = '{"type":"wifi_status","state":"connected","reason":"none","ssid":"LegacySanctum","ip":"192.168.1.50","rssi":-60}';
      final map = jsonDecode(legacyEsp32Notification) as Map<String, dynamic>;

      expect(map['type'], equals('wifi_status'));
      expect(map['ssid'], equals('LegacySanctum'));
      expect(map.containsKey('slots'), isFalse);
      expect(map.containsKey('active_slot'), isFalse);

      // Verify that missing slots don't throw, and fallback can be constructed
      final slotFallback = WifiSlotItem(
        slot: 1,
        ssid: map['ssid'] as String,
        isConfigured: true,
        isActive: map['state'] == 'connected',
        rssi: map['rssi'] as int,
      );
      expect(slotFallback.slot, equals(1));
      expect(slotFallback.ssid, equals('LegacySanctum'));
      expect(slotFallback.isConfigured, isTrue);
      expect(slotFallback.isActive, isTrue);
    });

    test('Parses wifi_scan_item notification emitted by ESP32 firmware', () {
      const esp32ScanItem = '{"type":"wifi_scan_item","idx":0,"total":1,"ssid":"Temple_WiFi_2.4G","rssi":-62,"auth":"WPA2"}';
      final map = jsonDecode(esp32ScanItem) as Map<String, dynamic>;

      final item = WifiNetworkItem.fromJson(map);
      expect(item.ssid, equals('Temple_WiFi_2.4G'));
      expect(item.rssi, equals(-62));
      expect(item.isSecured, isTrue);
      expect(item.auth, equals('WPA2'));
    });

    test('Parses ntp_synced notification emitted by ESP32 firmware', () {
      const esp32NtpEvent = '{"type":"ntp_synced","epoch":1774372950,"tz_min":330}';
      final map = jsonDecode(esp32NtpEvent) as Map<String, dynamic>;

      expect(map['type'], equals('ntp_synced'));
      expect(map['epoch'], equals(1774372950));
      expect(map['tz_min'], equals(330));
    });
  });
}
