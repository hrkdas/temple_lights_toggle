import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../domain/models.dart';
import '../theme.dart';
import 'signal_bars.dart';

/// Prominent connection status and live signal quality telemetry card.
class ConnectionCard extends StatelessWidget {
  const ConnectionCard({
    super.key,
    required this.connState,
    required this.isDeviceOn,
    required this.onDisconnect,
    required this.onForget,
    required this.onScan,
  });

  final ConnState connState;
  final bool isDeviceOn;
  final VoidCallback onDisconnect;
  final VoidCallback onForget;
  final VoidCallback onScan;

  Color get _statusColor {
    if (connState.isConnected) {
      return isDeviceOn ? AppTheme.green : AppTheme.cyan;
    }
    if (connState.isReconnecting) return AppTheme.gold;
    if (connState.isConnecting || connState.isScanning) return AppTheme.cyan;
    return AppTheme.red;
  }

  String get _statusHeader {
    switch (connState.phase) {
      case ConnPhase.connected:
        return 'CONNECTED • IN RANGE';
      case ConnPhase.connecting:
        return 'ESTABLISHING LINK...';
      case ConnPhase.reconnecting:
        return 'OUT OF RANGE • RECONNECTING';
      case ConnPhase.scanning:
        return connState.isTargetPaired ? 'SEARCHING PAIRED DEVICE...' : 'SEARCHING FOR DEVICES...';
      case ConnPhase.failed:
        return 'CONNECTION LOST';
      case ConnPhase.disconnected:
      case ConnPhase.idle:
        return 'DISCONNECTED';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor;
    final isConnected = connState.isConnected;
    final isReconnecting = connState.isReconnecting;
    final signalPct = connState.signalStrengthPercent;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: color.withValues(alpha: isConnected || isReconnecting ? 0.45 : 0.25),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: isConnected ? 0.12 : (isReconnecting ? 0.08 : 0.02)),
            blurRadius: 14,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Status Badge & Quick Actions
          Row(
            children: [
              // Pulsing LED dot
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.8),
                      blurRadius: 6,
                      spreadRadius: 1.5,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _statusHeader,
                style: AppTheme.heading(
                  size: 12,
                  color: color,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              if (isConnected) ...[
                IconButton(
                  icon: const Icon(Icons.power_settings_new_rounded, color: AppTheme.red, size: 20),
                  tooltip: 'Disconnect',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: onDisconnect,
                ),
              ] else if (connState.isTargetPaired) ...[
                TextButton(
                  onPressed: onForget,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Unpair',
                    style: AppTheme.heading(size: 11, color: AppTheme.textMuted),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),

          // Row 2: Device Name & MAC / ID
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      connState.deviceName ?? 'No Device Paired',
                      style: AppTheme.heading(
                        size: 16,
                        color: connState.deviceName != null ? AppTheme.textPrimary : AppTheme.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      connState.deviceId != null
                          ? 'ID: ${connState.deviceId!.substring(0, connState.deviceId!.length > 17 ? 17 : connState.deviceId!.length)}'
                          : 'Pair a device to enable automatic long-range linking',
                      style: AppTheme.body(size: 11, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              if (isConnected && connState.rssi != null)
                SignalBars(rssi: connState.rssi!, color: color)
              else if (isReconnecting)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.gold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '#${connState.reconnectAttempt}',
                    style: AppTheme.heading(size: 11, color: AppTheme.gold),
                  ),
                ),
            ],
          ),

          // Row 3: Signal Strength Meter (Visible when connected)
          if (isConnected) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.surfaceRaised,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                children: [
                  Icon(Icons.wifi_tethering_rounded, size: 16, color: color),
                  const SizedBox(width: 8),
                  Text(
                    'Signal: ${connState.signalQualityLabel} (${connState.rssi != null ? "${connState.rssi} dBm" : "Measuring..."})',
                    style: AppTheme.body(size: 12, color: AppTheme.textSecondary),
                  ),
                  const Spacer(),
                  // Mini Progress Bar
                  SizedBox(
                    width: 54,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: signalPct / 100.0,
                        minHeight: 5,
                        backgroundColor: AppTheme.surface,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (isReconnecting) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.gold.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.gold.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(AppTheme.gold),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Auto-reconnect ACTIVE. Bring device closer or power on.',
                      style: AppTheme.body(size: 11.5, color: AppTheme.gold),
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(),
          ],
        ],
      ),
    );
  }
}
