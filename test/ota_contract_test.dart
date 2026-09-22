import 'dart:convert';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:temple_lights_toggle/contract/light_contract.dart';
import 'package:temple_lights_toggle/contract/ota_constants.dart';
import 'package:temple_lights_toggle/domain/models.dart';

void main() {
  group('Temple Lights OTA Contract & Packet Encoder Tests', () {
    test('LightBleUuids exposes default OTA characteristic UUID', () {
      expect(LightBleUuids.defaultOtaChar, '0ddad461-e5e3-457b-a173-da66bd52bf4e');
    });

    test('encodeOtaBegin serializes size and md5 into valid JSON payload', () {
      final pkt = LightPacketEncoder.encodeOtaBegin(
        size: 642161,
        md5: '5d41402abc4b2a76b9719d911017c592',
      );
      final jsonStr = utf8.decode(pkt);
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;

      expect(map['cmd'], 'ota_begin');
      expect(map['size'], 642161);
      expect(map['md5'], '5d41402abc4b2a76b9719d911017c592');
    });

    test('encodeOtaEnd serializes ota_end command correctly', () {
      final pkt = LightPacketEncoder.encodeOtaEnd();
      final jsonStr = utf8.decode(pkt);
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;

      expect(map['cmd'], 'ota_end');
    });

    test('encodeOtaAbort serializes ota_abort command correctly', () {
      final pkt = LightPacketEncoder.encodeOtaAbort();
      final jsonStr = utf8.decode(pkt);
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;

      expect(map['cmd'], 'ota_abort');
    });
  });

  group('OtaProgressState Calculations & Metrics', () {
    test('calculates fractional progress and percentage correctly', () {
      const stateZero = OtaProgressState(bytesWritten: 0, totalBytes: 1000);
      expect(stateZero.progress, 0.0);
      expect(stateZero.percentage, 0);

      const stateHalf = OtaProgressState(bytesWritten: 500, totalBytes: 1000);
      expect(stateHalf.progress, 0.5);
      expect(stateHalf.percentage, 50);

      const stateFull = OtaProgressState(bytesWritten: 1000, totalBytes: 1000);
      expect(stateFull.progress, 1.0);
      expect(stateFull.percentage, 100);

      const stateOverflow = OtaProgressState(bytesWritten: 1200, totalBytes: 1000);
      expect(stateOverflow.progress, 1.0);
    });

    test('formats transferred bytes in KB properly', () {
      const state = OtaProgressState(
        bytesWritten: 256 * 1024,
        totalBytes: 512 * 1024,
      );
      expect(state.formattedBytes, '256.0 / 512.0 KB');
    });

    test('formats transfer speed in KB/s properly', () {
      const stateIdle = OtaProgressState(speedBytesPerSec: 0);
      expect(stateIdle.formattedSpeed, '-- KB/s');

      const stateActive = OtaProgressState(speedBytesPerSec: 20.5 * 1024);
      expect(stateActive.formattedSpeed, '20.5 KB/s');
    });

    test('formats ETA in seconds and minutes properly', () {
      const stateZero = OtaProgressState(etaSeconds: 0);
      expect(stateZero.formattedEta, '--');

      const stateSec = OtaProgressState(etaSeconds: 45);
      expect(stateSec.formattedEta, '45s');

      const stateMin = OtaProgressState(etaSeconds: 125);
      expect(stateMin.formattedEta, '2m 5s');
    });

    test('isInProgress accurately reflects active OTA phases', () {
      expect(const OtaProgressState(phase: OtaPhase.idle).isInProgress, isFalse);
      expect(const OtaProgressState(phase: OtaPhase.loadingAsset).isInProgress, isTrue);
      expect(const OtaProgressState(phase: OtaPhase.preparing).isInProgress, isTrue);
      expect(const OtaProgressState(phase: OtaPhase.transferring).isInProgress, isTrue);
      expect(const OtaProgressState(phase: OtaPhase.verifying).isInProgress, isTrue);
      expect(const OtaProgressState(phase: OtaPhase.rebooting).isInProgress, isTrue);
      expect(const OtaProgressState(phase: OtaPhase.completed).isInProgress, isFalse);
      expect(const OtaProgressState(phase: OtaPhase.failed).isInProgress, isFalse);
      expect(const OtaProgressState(phase: OtaPhase.canceled).isInProgress, isFalse);
    });
  });

  group('Temple Lights OTA Service & Characteristic Matching Tests', () {
    test('LightBleUuids defines dedicated OTA service and characteristic UUIDs', () {
      expect(LightBleUuids.defaultService, '95d6fedc-cac3-48e2-8221-f534a2782704');
      expect(LightBleUuids.defaultControlChar, '0ddad461-e5e3-457b-a173-da66bd52bf4d');
      expect(LightBleUuids.defaultOtaService, '95d6fedc-cac3-48e2-8221-f534a2782710');
      expect(LightBleUuids.defaultOtaControlChar, '0ddad461-e5e3-457b-a173-da66bd52bf4e');
      expect(LightBleUuids.defaultOtaDataChar, '0ddad461-e5e3-457b-a173-da66bd52bf4f');
      expect(LightBleUuids.defaultOtaStatusChar, '0ddad461-e5e3-457b-a173-da66bd52bf50');
      expect(LightBleUuids.defaultOtaChar, LightBleUuids.defaultOtaControlChar);
      expect(LightBleUuids.knownServices, contains(LightBleUuids.defaultService));
      expect(LightBleUuids.knownServices, contains(LightBleUuids.defaultOtaService));
      expect(LightBleUuids.knownServices, contains(LightBleUuids.legacyService));
      expect(LightBleUuids.knownServices.length, 3);
    });

    test('resolveOtaUuids matches dedicated hardware Temple Lights OTA service', () {
      final services = [
        DiscoveredServiceSummary(
          serviceId: OtaConstants.primaryServiceUuid,
          characteristicIds: [Uuid.parse(LightBleUuids.defaultControlChar)],
        ),
        DiscoveredServiceSummary(
          serviceId: OtaConstants.primaryOtaServiceUuid,
          characteristicIds: [
            OtaConstants.primaryOtaControlUuid,
            OtaConstants.primaryOtaDataUuid,
            OtaConstants.primaryOtaStatusUuid,
          ],
        ),
      ];

      final resolved = OtaConstants.resolveOtaUuids(discoveredServices: services);
      expect(resolved, isNotNull);
      expect(resolved!.serviceUuid, OtaConstants.primaryOtaServiceUuid);
      expect(resolved.controlUuid, OtaConstants.primaryOtaControlUuid);
      expect(resolved.dataUuid, OtaConstants.primaryOtaDataUuid);
      expect(resolved.statusUuid, OtaConstants.primaryOtaStatusUuid);
      expect(resolved.sourceDescription, contains('Matched Dedicated OTA Service'));
    });

    test('resolveOtaUuids matches primary lighting service when characteristics are under it', () {
      final services = [
        DiscoveredServiceSummary(
          serviceId: OtaConstants.primaryServiceUuid,
          characteristicIds: [
            Uuid.parse(LightBleUuids.defaultControlChar),
            OtaConstants.primaryOtaControlUuid,
            OtaConstants.primaryOtaDataUuid,
            OtaConstants.primaryOtaStatusUuid,
          ],
        ),
      ];

      final resolved = OtaConstants.resolveOtaUuids(
        discoveredServices: services,
        preferredServiceUuid: OtaConstants.primaryServiceUuid.toString(),
      );
      expect(resolved, isNotNull);
      expect(resolved!.serviceUuid, OtaConstants.primaryServiceUuid);
      expect(resolved.controlUuid, OtaConstants.primaryOtaControlUuid);
      expect(resolved.dataUuid, OtaConstants.primaryOtaDataUuid);
      expect(resolved.statusUuid, OtaConstants.primaryOtaStatusUuid);
      expect(resolved.sourceDescription, contains('Matched Preferred Service'));
    });

    test('resolveOtaUuids matches legacy Temple Lights service characteristics', () {
      final services = [
        DiscoveredServiceSummary(
          serviceId: OtaConstants.legacyServiceUuid,
          characteristicIds: [
            Uuid.parse(LightBleUuids.legacyControlChar),
            OtaConstants.legacyOtaControlUuid,
            OtaConstants.legacyOtaDataUuid,
            OtaConstants.legacyOtaStatusUuid,
          ],
        ),
      ];

      final resolved = OtaConstants.resolveOtaUuids(discoveredServices: services);
      expect(resolved, isNotNull);
      expect(resolved!.serviceUuid, OtaConstants.legacyServiceUuid);
      expect(resolved.controlUuid, OtaConstants.legacyOtaControlUuid);
      expect(resolved.dataUuid, OtaConstants.legacyOtaDataUuid);
      expect(resolved.statusUuid, OtaConstants.legacyOtaStatusUuid);
      expect(resolved.sourceDescription, contains('Matched Legacy Service'));
    });

    test('resolveOtaUuids returns null when device only has lighting characteristic and no OTA service', () {
      final services = [
        DiscoveredServiceSummary(
          serviceId: OtaConstants.primaryServiceUuid,
          characteristicIds: [Uuid.parse(LightBleUuids.defaultControlChar)],
        ),
      ];

      final resolved = OtaConstants.resolveOtaUuids(discoveredServices: services);
      expect(resolved, isNull);
    });

    test('resolveOtaUuids returns null when foreign unknown service is discovered', () {
      final services = [
        DiscoveredServiceSummary(
          serviceId: Uuid.parse('12345678-1234-1234-1234-123456789abc'),
          characteristicIds: [Uuid.parse('12345678-1234-1234-1234-123456789abd')],
        ),
      ];

      final resolved = OtaConstants.resolveOtaUuids(discoveredServices: services);
      expect(resolved, isNull);
    });
  });
}
