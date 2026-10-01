import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:temple_lights_toggle/contract/light_contract.dart';
import 'package:temple_lights_toggle/domain/models.dart';

void main() {
  group('Temple Lights WiFi & NTP Contract Tests', () {
    test('LightPacketEncoder encodes WiFi scan command', () {
      final bytes = LightPacketEncoder.encodeWifiScan();
      final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      expect(map['cmd'], equals('wifi_scan'));
    });

    test('LightPacketEncoder encodes WiFi connect command with credentials', () {
      final bytes = LightPacketEncoder.encodeWifiConnect(
        ssid: 'TempleNet_2.4G',
        psk: 'DivinePassword108',
        save: true,
      );
      final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      expect(map['cmd'], equals('wifi_connect'));
      expect(map['ssid'], equals('TempleNet_2.4G'));
      expect(map['psk'], equals('DivinePassword108'));
      expect(map['save'], isTrue);
    });

    test('LightPacketEncoder encodes WiFi forget command', () {
      final bytes = LightPacketEncoder.encodeWifiForget();
      final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      expect(map['cmd'], equals('wifi_forget'));
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

    test('WifiNetworkItem computes signal bars accurately', () {
      expect(const WifiNetworkItem(ssid: 'A', rssi: -50, auth: 'WPA2').signalBars, equals(3));
      expect(const WifiNetworkItem(ssid: 'B', rssi: -65, auth: 'WPA2').signalBars, equals(2));
      expect(const WifiNetworkItem(ssid: 'C', rssi: -85, auth: 'WPA2').signalBars, equals(1));
    });
  });

  group('WifiConnectionState Status Descriptions & Phase Progression', () {
    test('Reports connected status with SSID and IP', () {
      const state = WifiConnectionState(
        phase: WifiPhase.connected,
        currentSsid: 'TempleNet_2.4G',
        ipAddress: '192.168.1.108',
      );

      expect(state.isConnected, isTrue);
      expect(state.isConnecting, isFalse);
      expect(state.humanReadableStatus, equals('Connected (TempleNet_2.4G)'));
    });

    test('Reports connecting phase status', () {
      const state = WifiConnectionState(
        phase: WifiPhase.connecting,
        currentSsid: 'TempleNet_2.4G',
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

    test('Reports idle not configured state', () {
      const state = WifiConnectionState.idle;

      expect(state.isConnected, isFalse);
      expect(state.isConnecting, isFalse);
      expect(state.humanReadableStatus, equals('Not Configured'));
    });
  });

  group('ESP32 Live JSON Notification Parsing Simulation', () {
    test('Parses wifi_status notification JSON emitted by ESP32 firmware', () {
      const esp32Notification = '{"type":"wifi_status","state":"connected","reason":"none","ssid":"TempleSanctuary","ip":"192.168.31.200","rssi":-55}';
      final map = jsonDecode(esp32Notification) as Map<String, dynamic>;

      expect(map['type'], equals('wifi_status'));
      expect(map['state'], equals('connected'));
      expect(map['reason'], equals('none'));
      expect(map['ssid'], equals('TempleSanctuary'));
      expect(map['ip'], equals('192.168.31.200'));
      expect(map['rssi'], equals(-55));
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
