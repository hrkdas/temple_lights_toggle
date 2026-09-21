import 'dart:typed_data';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

class OtaConstants {
  OtaConstants._();

  // Dedicated Boturo Go OTA GATT UUIDs
  static final Uuid otaServiceUuid =
      Uuid.parse('f71a0001-2c98-4a7b-a7f9-5e8fbc2d0100');
  static final Uuid otaControlCharacteristicUuid =
      Uuid.parse('f71a0002-2c98-4a7b-a7f9-5e8fbc2d0100');
  static final Uuid otaDataCharacteristicUuid =
      Uuid.parse('f71a0003-2c98-4a7b-a7f9-5e8fbc2d0100');
  static final Uuid otaStatusCharacteristicUuid =
      Uuid.parse('f71a0004-2c98-4a7b-a7f9-5e8fbc2d0100');

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
}
