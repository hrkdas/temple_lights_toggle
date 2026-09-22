import 'dart:typed_data';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

class OtaConstants {
  OtaConstants._();

  // Primary Hardware-Matched High-Speed OTA UUIDs
  // Dedicated OTA Service: 95d6fedc-cac3-48e2-8221-f534a2782710
  // Primary Lighting Service: 95d6fedc-cac3-48e2-8221-f534a2782704
  static final Uuid primaryOtaServiceUuid =
      Uuid.parse('95d6fedc-cac3-48e2-8221-f534a2782710');
  static final Uuid primaryServiceUuid =
      Uuid.parse('95d6fedc-cac3-48e2-8221-f534a2782704');
  static final Uuid primaryOtaControlUuid =
      Uuid.parse('0ddad461-e5e3-457b-a173-da66bd52bf4e');
  static final Uuid primaryOtaDataUuid =
      Uuid.parse('0ddad461-e5e3-457b-a173-da66bd52bf4f');
  static final Uuid primaryOtaStatusUuid =
      Uuid.parse('0ddad461-e5e3-457b-a173-da66bd52bf50');

  // Legacy Temple Lights High-Speed OTA UUIDs (under a1b2c3d4-e5f6-7890-abcd-ef1234567890)
  static final Uuid legacyServiceUuid =
      Uuid.parse('a1b2c3d4-e5f6-7890-abcd-ef1234567890');
  static final Uuid legacyOtaControlUuid =
      Uuid.parse('a1b2c3d4-e5f6-7890-abcd-ef1234567892');
  static final Uuid legacyOtaDataUuid =
      Uuid.parse('a1b2c3d4-e5f6-7890-abcd-ef1234567893');
  static final Uuid legacyOtaStatusUuid =
      Uuid.parse('a1b2c3d4-e5f6-7890-abcd-ef1234567894');

  // Active default getters
  static Uuid get templeLightsServiceUuid => primaryOtaServiceUuid;
  static Uuid get templeLightsOtaControlUuid => primaryOtaControlUuid;
  static Uuid get templeLightsOtaDataUuid => primaryOtaDataUuid;
  static Uuid get templeLightsOtaStatusUuid => primaryOtaStatusUuid;

  static Uuid get otaServiceUuid => primaryOtaServiceUuid;
  static Uuid get otaControlCharacteristicUuid => primaryOtaControlUuid;
  static Uuid get otaDataCharacteristicUuid => primaryOtaDataUuid;
  static Uuid get otaStatusCharacteristicUuid => primaryOtaStatusUuid;

  static const int targetMtu = 517;
  static const int fallbackMtu = 247;
  static const int defaultChunkPayloadBytes = 240;
  static const int safeMaxChunkPayloadBytes = 480;
  static const int minChunkPayloadBytes = 40;
  static const int chunkHeaderBytes = 4; // chunk index (LE u32)
  static const int defaultAckWindowPackets = 16;
  static const int maxAckRetries = 4;
  static const int burstPacketsBeforeYield = 6;
  static const int burstYieldDelayMs = 1;
  static const int maxFirmwareBytes = 2 * 1024 * 1024;

  static const Duration connectTimeout = Duration(seconds: 18);
  static const Duration serviceDiscoveryTimeout = Duration(seconds: 8);
  static const Duration commandTimeout = Duration(seconds: 5);
  static const Duration ackTimeout = Duration(milliseconds: 1500);
  static const Duration doneTimeout = Duration(seconds: 20);
  static const Duration postStartSettleDelay = Duration(milliseconds: 100);
  static const Duration expectedRebootDisconnectWindow = Duration(seconds: 10);

  // Control plane opcodes (mobile -> ESP via OTA_CONTROL)
  static const int opStartOta = 0x01;
  static const int opEndOta = 0x02;

  // Status plane opcodes (ESP -> mobile via OTA_STATUS notify)
  static const int stStartAccepted = 0x10;
  static const int stAck = 0x11;
  static const int stDone = 0x12;
  static const int stError = 0x13;

  // Frame builders
  static Uint8List makeChunkFrame(int chunkIndex, Uint8List payload) {
    final frame = Uint8List(payload.length + 4);
    final view = ByteData.sublistView(frame);
    view.setUint32(0, chunkIndex, Endian.little);
    frame.setRange(4, frame.length, payload);
    return frame;
  }

  static Uint8List makeStartFrame(int firmwareSizeBytes) {
    final frame = Uint8List(5);
    frame[0] = opStartOta;
    final view = ByteData.sublistView(frame);
    view.setUint32(1, firmwareSizeBytes, Endian.little);
    return frame;
  }

  static Uint8List makeEndFrame() => Uint8List.fromList(<int>[opEndOta]);

  /// Dynamically resolves and matches the OTA Service and Characteristic UUIDs
  /// based on the discovered services from the connected hardware.
  static ResolvedOtaUuids? resolveOtaUuids({
    required Iterable<dynamic> discoveredServices,
    String? preferredServiceUuid,
  }) {
    final summaries = <DiscoveredServiceSummary>[];
    for (final s in discoveredServices) {
      if (s is DiscoveredServiceSummary) {
        summaries.add(s);
      } else if (s is Service) {
        summaries.add(
          DiscoveredServiceSummary(
            serviceId: s.id,
            characteristicIds: s.characteristics.map((c) => c.id).toList(),
          ),
        );
      } else if (s is DiscoveredService) {
        summaries.add(
          DiscoveredServiceSummary(
            serviceId: s.serviceId,
            characteristicIds: s.characteristicIds,
          ),
        );
      }
    }

    final targetServiceStr =
        (preferredServiceUuid ?? primaryOtaServiceUuid.toString()).toLowerCase();

    // 1. Check for dedicated OTA service (95d6fedc-cac3-48e2-8221-f534a2782710)
    for (final s in summaries) {
      if (s.serviceId.toString().toLowerCase() ==
          primaryOtaServiceUuid.toString().toLowerCase()) {
        final charMap = {
          for (final c in s.characteristicIds) c.toString().toLowerCase(): c
        };
        final cControl =
            charMap[primaryOtaControlUuid.toString().toLowerCase()] ??
            primaryOtaControlUuid;
        final cData =
            charMap[primaryOtaDataUuid.toString().toLowerCase()] ??
            primaryOtaDataUuid;
        final cStatus =
            charMap[primaryOtaStatusUuid.toString().toLowerCase()] ??
            primaryOtaStatusUuid;

        return ResolvedOtaUuids(
          serviceUuid: s.serviceId,
          controlUuid: cControl,
          dataUuid: cData,
          statusUuid: cStatus,
          sourceDescription: 'Matched Dedicated OTA Service (${s.serviceId})',
        );
      }
    }

    // 2. Check preferred service match with primary OTA characteristics
    for (final s in summaries) {
      if (s.serviceId.toString().toLowerCase() == targetServiceStr) {
        final charMap = {
          for (final c in s.characteristicIds) c.toString().toLowerCase(): c
        };

        // Check primary characteristics
        final cControl =
            charMap[primaryOtaControlUuid.toString().toLowerCase()];
        final cData = charMap[primaryOtaDataUuid.toString().toLowerCase()];
        final cStatus = charMap[primaryOtaStatusUuid.toString().toLowerCase()];
        if (cControl != null && cData != null) {
          return ResolvedOtaUuids(
            serviceUuid: s.serviceId,
            controlUuid: cControl,
            dataUuid: cData,
            statusUuid: cStatus ?? cControl,
            sourceDescription: 'Matched Preferred Service (${s.serviceId})',
          );
        }

        // Check legacy characteristics under preferred service
        final cLegControl =
            charMap[legacyOtaControlUuid.toString().toLowerCase()];
        final cLegData = charMap[legacyOtaDataUuid.toString().toLowerCase()];
        final cLegStatus =
            charMap[legacyOtaStatusUuid.toString().toLowerCase()];
        if (cLegControl != null && cLegData != null) {
          return ResolvedOtaUuids(
            serviceUuid: s.serviceId,
            controlUuid: cLegControl,
            dataUuid: cLegData,
            statusUuid: cLegStatus ?? cLegControl,
            sourceDescription:
                'Matched Preferred Service with Legacy OTA (${s.serviceId})',
          );
        }
      }
    }

    // 3. Check legacy service (a1b2c3d4-e5f6-7890-abcd-ef1234567890)
    for (final s in summaries) {
      if (s.serviceId.toString().toLowerCase() ==
          legacyServiceUuid.toString().toLowerCase()) {
        final charMap = {
          for (final c in s.characteristicIds) c.toString().toLowerCase(): c
        };
        final cControl =
            charMap[legacyOtaControlUuid.toString().toLowerCase()];
        final cData = charMap[legacyOtaDataUuid.toString().toLowerCase()];
        final cStatus =
            charMap[legacyOtaStatusUuid.toString().toLowerCase()];
        if (cControl != null && cData != null) {
          return ResolvedOtaUuids(
            serviceUuid: s.serviceId,
            controlUuid: cControl,
            dataUuid: cData,
            statusUuid: cStatus ?? cControl,
            sourceDescription: 'Matched Legacy Service (${s.serviceId})',
          );
        }
      }
    }

    // 4. Search all discovered services for presence of either OTA characteristic set
    for (final s in summaries) {
      final charMap = {
        for (final c in s.characteristicIds) c.toString().toLowerCase(): c
      };

      // Check primary set
      final cControl =
          charMap[primaryOtaControlUuid.toString().toLowerCase()];
      final cData = charMap[primaryOtaDataUuid.toString().toLowerCase()];
      final cStatus = charMap[primaryOtaStatusUuid.toString().toLowerCase()];
      if (cControl != null && cData != null) {
        return ResolvedOtaUuids(
          serviceUuid: s.serviceId,
          controlUuid: cControl,
          dataUuid: cData,
          statusUuid: cStatus ?? cControl,
          sourceDescription:
              'Discovered Service with Primary OTA (${s.serviceId})',
        );
      }

      // Check legacy set
      final cLegControl =
          charMap[legacyOtaControlUuid.toString().toLowerCase()];
      final cLegData = charMap[legacyOtaDataUuid.toString().toLowerCase()];
      final cLegStatus =
          charMap[legacyOtaStatusUuid.toString().toLowerCase()];
      if (cLegControl != null && cLegData != null) {
        return ResolvedOtaUuids(
          serviceUuid: s.serviceId,
          controlUuid: cLegControl,
          dataUuid: cLegData,
          statusUuid: cLegStatus ?? cLegControl,
          sourceDescription:
              'Discovered Service with Legacy OTA (${s.serviceId})',
        );
      }
    }

    return null;
  }
}

class DiscoveredServiceSummary {
  const DiscoveredServiceSummary({
    required this.serviceId,
    required this.characteristicIds,
  });

  final Uuid serviceId;
  final List<Uuid> characteristicIds;
}

class ResolvedOtaUuids {
  const ResolvedOtaUuids({
    required this.serviceUuid,
    required this.controlUuid,
    required this.dataUuid,
    required this.statusUuid,
    required this.sourceDescription,
  });

  final Uuid serviceUuid;
  final Uuid controlUuid;
  final Uuid dataUuid;
  final Uuid statusUuid;
  final String sourceDescription;
}
