import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../contract/ota_constants.dart';

enum OtaStatusType {
  startAccepted,
  ack,
  done,
  error,
}

class OtaStatusEvent {
  OtaStatusEvent({
    required this.type,
    this.chunkIndex,
    this.errorCode,
    this.errorDetailType,
    this.errorDetailCode,
    this.rawAscii,
  });

  final OtaStatusType type;
  final int? chunkIndex;
  final int? errorCode;
  final int? errorDetailType;
  final int? errorDetailCode;
  final String? rawAscii;
}

class OtaProtocol {
  OtaProtocol({
    required FlutterReactiveBle ble,
    required String deviceId,
    required Uuid serviceUuid,
    required Uuid controlUuid,
    required Uuid dataUuid,
    required Uuid statusUuid,
    void Function(String message)? log,
  })  : _ble = ble,
        _log = log,
        _control = QualifiedCharacteristic(
          serviceId: serviceUuid,
          characteristicId: controlUuid,
          deviceId: deviceId,
        ),
        _data = QualifiedCharacteristic(
          serviceId: serviceUuid,
          characteristicId: dataUuid,
          deviceId: deviceId,
        ),
        _status = QualifiedCharacteristic(
          serviceId: serviceUuid,
          characteristicId: statusUuid,
          deviceId: deviceId,
        );

  static const int _packetTimeoutErrorCode = 8;
  static const Duration _staleStartupErrorIgnoreWindow = Duration(seconds: 2);

  final FlutterReactiveBle _ble;
  final void Function(String message)? _log;

  final QualifiedCharacteristic _control;
  final QualifiedCharacteristic _data;
  final QualifiedCharacteristic _status;
  final Uint8List _chunkFrameBuffer = Uint8List(
    OtaConstants.safeMaxChunkPayloadBytes + OtaConstants.chunkHeaderBytes,
  );

  final StreamController<OtaStatusEvent> _statusEvents =
      StreamController<OtaStatusEvent>.broadcast();

  StreamSubscription<List<int>>? _statusSubscription;
  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  int _highestAckChunkIndex = -1;
  bool _awaitingExpectedRebootDisconnect = false;
  bool _receivedErrorStatus = false;
  bool _receivedDoneStatus = false;
  bool _hasSentDataChunk = false;
  DateTime? _startAcceptedAt;
  DateTime? _endSentAt;

  Future<void> initialize() async {
    _statusSubscription = _ble.subscribeToCharacteristic(_status).listen(
      _onStatusPacket,
      onError: (Object error) {
        _log?.call('OTA status stream error: $error');
      },
    );
    _connectionSubscription = _ble.connectedDeviceStream.listen(
      _onConnectionUpdate,
      onError: (Object error) {
        _log?.call('OTA connection stream error: $error');
      },
    );
  }

  Future<void> sendStart({required int firmwareSizeBytes}) async {
    _log?.call('OTA->ESP START size=$firmwareSizeBytes');
    _awaitingExpectedRebootDisconnect = false;
    _receivedErrorStatus = false;
    _receivedDoneStatus = false;
    _hasSentDataChunk = false;
    _startAcceptedAt = null;
    _endSentAt = null;
    final payload = OtaConstants.makeStartFrame(firmwareSizeBytes);
    await _ble.writeCharacteristicWithResponse(_control, value: payload);
    final OtaStatusEvent event = await _waitFor(
      matcher: (event) =>
          event.type == OtaStatusType.startAccepted ||
          event.type == OtaStatusType.error,
      timeout: OtaConstants.commandTimeout,
    );
    if (event.type == OtaStatusType.error) {
      throw OtaProtocolException(
        'ESP rejected START_OTA: ${_describeError(event)}',
      );
    }
    _log?.call('ESP->OTA START accepted');
  }

  Future<void> sendChunk({
    required int chunkIndex,
    required Uint8List payload,
  }) {
    if (payload.isEmpty) {
      throw OtaProtocolException('Attempted to send empty OTA chunk');
    }
    _hasSentDataChunk = true;
    final Uint8List frame = _buildChunkFrame(
      chunkIndex: chunkIndex,
      payload: payload,
    );
    return _ble.writeCharacteristicWithoutResponse(_data, value: frame);
  }

  Future<void> waitForAck({required int chunkIndex, Duration? timeout}) async {
    if (_highestAckChunkIndex >= chunkIndex) {
      return;
    }

    final event = await _waitFor(
      matcher: (status) {
        if (status.type == OtaStatusType.error) {
          return true;
        }
        return status.type == OtaStatusType.ack &&
            (status.chunkIndex ?? -1) >= chunkIndex;
      },
      timeout: timeout ?? OtaConstants.ackTimeout,
    );

    if (event.type == OtaStatusType.error) {
      throw OtaProtocolException(
        'ESP reported OTA error while waiting ACK($chunkIndex): ${_describeError(event)}',
      );
    }
  }

  Future<void> sendEnd() async {
    _log?.call('OTA->ESP END');
    await _ble.writeCharacteristicWithoutResponse(
      _control,
      value: OtaConstants.makeEndFrame(),
    );
    _awaitingExpectedRebootDisconnect = true;
    _endSentAt = DateTime.now();
    _log?.call('OTA END sent; expecting reboot disconnect');
  }

  Future<void> waitForDone({Duration? timeout}) async {
    final OtaStatusEvent event;
    try {
      event = await _waitFor(
        matcher: (status) =>
            status.type == OtaStatusType.done ||
            status.type == OtaStatusType.error,
        timeout: timeout ?? OtaConstants.doneTimeout,
      );
    } on TimeoutException {
      _log?.call('OTA DONE not received before timeout; assuming reboot');
      return;
    }

    if (event.type == OtaStatusType.error) {
      throw OtaProtocolException(
        'ESP reported OTA error after END_OTA: ${_describeError(event)}',
      );
    }
    _log?.call('ESP->OTA DONE');
  }

  Future<void> dispose() async {
    await _statusSubscription?.cancel();
    await _connectionSubscription?.cancel();
    await _statusEvents.close();
  }

  Future<OtaStatusEvent> _waitFor({
    required bool Function(OtaStatusEvent event) matcher,
    required Duration timeout,
  }) {
    return _statusEvents.stream.firstWhere(matcher).timeout(timeout);
  }

  Uint8List _buildChunkFrame({
    required int chunkIndex,
    required Uint8List payload,
  }) {
    final int frameLength = payload.length + OtaConstants.chunkHeaderBytes;
    if (frameLength > _chunkFrameBuffer.length) {
      throw OtaProtocolException(
        'Chunk frame exceeds reusable buffer: $frameLength > ${_chunkFrameBuffer.length}',
      );
    }

    final ByteData view = ByteData.sublistView(
      _chunkFrameBuffer,
      0,
      frameLength,
    );
    view.setUint32(0, chunkIndex, Endian.little);
    _chunkFrameBuffer.setRange(
      OtaConstants.chunkHeaderBytes,
      frameLength,
      payload,
    );
    return Uint8List.sublistView(_chunkFrameBuffer, 0, frameLength);
  }

  void _onStatusPacket(List<int> packet) {
    if (packet.isEmpty) {
      return;
    }

    final OtaStatusEvent? event = _parseStatusPacket(packet);
    if (event == null) {
      _log?.call('Ignoring unknown OTA status packet: $packet');
      return;
    }

    if (_shouldIgnoreStaleStartupError(event)) {
      _log?.call(
        'Ignoring stale OTA error during new session startup: ${_describeError(event)}',
      );
      return;
    }

    _statusEvents.add(event);
    if (event.type == OtaStatusType.startAccepted) {
      _highestAckChunkIndex = -1;
      _awaitingExpectedRebootDisconnect = false;
      _receivedErrorStatus = false;
      _receivedDoneStatus = false;
      _hasSentDataChunk = false;
      _startAcceptedAt = DateTime.now();
      _endSentAt = null;
    } else if (event.type == OtaStatusType.ack && event.chunkIndex != null) {
      if (event.chunkIndex! > _highestAckChunkIndex) {
        _highestAckChunkIndex = event.chunkIndex!;
      }
    } else if (event.type == OtaStatusType.done) {
      _receivedDoneStatus = true;
      _awaitingExpectedRebootDisconnect = false;
    }
    if (event.type == OtaStatusType.error) {
      _receivedErrorStatus = true;
      _awaitingExpectedRebootDisconnect = false;
      _log?.call('ESP OTA ERROR: ${_describeError(event)}');
    }
  }

  bool _shouldIgnoreStaleStartupError(OtaStatusEvent event) {
    if (event.type != OtaStatusType.error) {
      return false;
    }
    if (event.errorCode != _packetTimeoutErrorCode) {
      return false;
    }
    if (_receivedDoneStatus ||
        _receivedErrorStatus ||
        _awaitingExpectedRebootDisconnect) {
      return false;
    }
    if (_hasSentDataChunk) {
      return false;
    }
    if (_startAcceptedAt == null) {
      return false;
    }
    final Duration sinceStartAccepted =
        DateTime.now().difference(_startAcceptedAt!);
    return sinceStartAccepted <= _staleStartupErrorIgnoreWindow;
  }

  void _onConnectionUpdate(ConnectionStateUpdate update) {
    if (update.deviceId != _control.deviceId) {
      return;
    }
    if (!_awaitingExpectedRebootDisconnect ||
        _receivedErrorStatus ||
        _receivedDoneStatus ||
        _endSentAt == null ||
        update.connectionState != DeviceConnectionState.disconnected) {
      return;
    }

    final Duration disconnectDelay = DateTime.now().difference(_endSentAt!);
    if (disconnectDelay > OtaConstants.expectedRebootDisconnectWindow) {
      return;
    }

    _awaitingExpectedRebootDisconnect = false;
    _receivedDoneStatus = true;
    _log?.call(
      'OTA success via expected reboot disconnect (${disconnectDelay.inMilliseconds}ms after END)',
    );
    _statusEvents.add(
      OtaStatusEvent(
        type: OtaStatusType.done,
        rawAscii: 'EXPECTED_REBOOT_DISCONNECT',
      ),
    );
  }

  String _describeError(OtaStatusEvent event) {
    if (event.rawAscii != null && event.rawAscii!.isNotEmpty) {
      return event.rawAscii!;
    }
    if (event.errorCode != null) {
      return 'code=${event.errorCode}';
    }
    return 'unknown';
  }

  OtaStatusEvent? _parseStatusPacket(List<int> packet) {
    final int opcode = packet[0];
    if (opcode == OtaConstants.stStartAccepted) {
      return OtaStatusEvent(type: OtaStatusType.startAccepted);
    }
    if (opcode == OtaConstants.stAck && packet.length >= 5) {
      final view = ByteData.sublistView(Uint8List.fromList(packet));
      final int chunkIndex = view.getUint32(1, Endian.little);
      return OtaStatusEvent(type: OtaStatusType.ack, chunkIndex: chunkIndex);
    }
    if (opcode == OtaConstants.stDone) {
      return OtaStatusEvent(type: OtaStatusType.done);
    }
    if (opcode == OtaConstants.stError) {
      final int code = packet.length > 1 ? packet[1] : -1;
      final int? detailType = packet.length > 2 ? packet[2] : null;
      final int? detailCode = packet.length > 3 ? packet[3] : null;
      return OtaStatusEvent(
        type: OtaStatusType.error,
        errorCode: code,
        errorDetailType: detailType,
        errorDetailCode: detailCode,
      );
    }

    // Backward-compatible ASCII fallback parser
    final String ascii = utf8.decode(packet, allowMalformed: true).trim();
    if (ascii == 'START_OK') {
      return OtaStatusEvent(type: OtaStatusType.startAccepted, rawAscii: ascii);
    }
    if (ascii == 'DONE') {
      return OtaStatusEvent(type: OtaStatusType.done, rawAscii: ascii);
    }
    if (ascii.startsWith('ACK:')) {
      final String raw = ascii.substring(4);
      final int? index = int.tryParse(raw);
      if (index != null) {
        return OtaStatusEvent(
          type: OtaStatusType.ack,
          chunkIndex: index,
          rawAscii: ascii,
        );
      }
    }
    if (ascii.startsWith('ERROR')) {
      return OtaStatusEvent(type: OtaStatusType.error, rawAscii: ascii);
    }

    return null;
  }
}

class OtaProtocolException implements Exception {
  OtaProtocolException(this.message);

  final String message;

  @override
  String toString() => 'OtaProtocolException: $message';
}
