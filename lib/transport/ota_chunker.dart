import 'dart:typed_data';

import '../contract/ota_constants.dart';

class OtaChunk {
  OtaChunk({
    required this.chunkIndex,
    required this.offset,
    required this.payload,
  });

  final int chunkIndex;
  final int offset;
  final Uint8List payload;
}

typedef ChunkSender = Future<void> Function(OtaChunk chunk);
typedef ChunkAckWaiter = Future<void> Function(int chunkIndex);
typedef ChunkProgress = void Function(int sentBytes, int totalBytes);
typedef ChunkRetryLogger = void Function(
  int chunkIndex,
  int attempt,
  Object error,
);
typedef ChunkWindowAck = void Function(int chunkIndex, int ackedBytes);

class OtaChunker {
  OtaChunker({
    this.chunkPayloadBytes = OtaConstants.defaultChunkPayloadBytes,
    this.ackWindowPackets = OtaConstants.defaultAckWindowPackets,
    this.maxAckRetries = OtaConstants.maxAckRetries,
  });

  final int chunkPayloadBytes;
  final int ackWindowPackets;
  final int maxAckRetries;

  static int totalChunksForSize(int firmwareSize, int payloadBytes) {
    if (firmwareSize <= 0 || payloadBytes <= 0) {
      return 0;
    }
    return (firmwareSize + payloadBytes - 1) ~/ payloadBytes;
  }

  int totalChunksForCurrentPayload(int totalBytes) {
    return OtaChunker.totalChunksForSize(totalBytes, chunkPayloadBytes);
  }

  Iterable<OtaChunk> split(Uint8List firmware) sync* {
    int offset = 0;
    int chunkIndex = 0;

    while (offset < firmware.length) {
      final int end = (offset + chunkPayloadBytes) > firmware.length
          ? firmware.length
          : (offset + chunkPayloadBytes);
      final Uint8List payload = Uint8List.sublistView(firmware, offset, end);
      yield OtaChunk(chunkIndex: chunkIndex, offset: offset, payload: payload);
      offset = end;
      chunkIndex += 1;
    }
  }

  Future<void> transfer({
    required Uint8List firmware,
    required ChunkSender sendChunk,
    required ChunkAckWaiter waitForAck,
    required ChunkProgress onProgress,
    ChunkRetryLogger? onRetry,
    ChunkWindowAck? onWindowAck,
  }) async {
    final int total = firmware.length;
    if (total == 0) {
      onProgress(0, 0);
      return;
    }

    final int totalChunks =
        OtaChunker.totalChunksForSize(total, chunkPayloadBytes);
    int windowStart = 0;

    while (windowStart < totalChunks) {
      final int windowEnd = (windowStart + ackWindowPackets - 1) < totalChunks
          ? (windowStart + ackWindowPackets - 1)
          : (totalChunks - 1);
      int attempt = 0;
      while (true) {
        attempt += 1;

        try {
          for (int chunkIndex = windowStart;
              chunkIndex <= windowEnd;
              chunkIndex++) {
            final int offset = chunkIndex * chunkPayloadBytes;
            final int end = (offset + chunkPayloadBytes) > total
                ? total
                : (offset + chunkPayloadBytes);
            final Uint8List payload =
                Uint8List.sublistView(firmware, offset, end);

            await sendChunk(
              OtaChunk(
                chunkIndex: chunkIndex,
                offset: offset,
                payload: payload,
              ),
            );

            final int packetsSentInWindow = chunkIndex - windowStart + 1;
            if (packetsSentInWindow < (windowEnd - windowStart + 1) &&
                packetsSentInWindow % OtaConstants.burstPacketsBeforeYield ==
                    0) {
              await Future<void>.delayed(
                const Duration(milliseconds: OtaConstants.burstYieldDelayMs),
              );
            }
          }

          await waitForAck(windowEnd);
          final int committed = ((windowEnd + 1) * chunkPayloadBytes) > total
              ? total
              : ((windowEnd + 1) * chunkPayloadBytes);
          onWindowAck?.call(windowEnd, committed);
          onProgress(committed, total);
          windowStart = windowEnd + 1;
          break;
        } catch (e) {
          if (attempt > maxAckRetries) {
            throw OtaChunkTransferException(
              'ACK timeout for chunk $windowEnd after $maxAckRetries retries',
              cause: e,
            );
          }
          onRetry?.call(windowEnd, attempt, e);
        }
      }
    }
  }
}

class OtaChunkTransferException implements Exception {
  OtaChunkTransferException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'OtaChunkTransferException: $message';
}
