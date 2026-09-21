import 'package:flutter/material.dart';
import '../../domain/models.dart';
import '../theme.dart';

/// Connection and Relay status pill with pulsing live indicator.
class StatusPill extends StatefulWidget {
  const StatusPill({
    super.key,
    required this.connState,
    required this.isRelayOn,
  });

  final ConnState connState;
  final bool isRelayOn;

  @override
  State<StatusPill> createState() => _StatusPillState();
}

class _StatusPillState extends State<StatusPill> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Color get _statusColor {
    if (widget.connState.phase == ConnPhase.connected) {
      return widget.isRelayOn ? AppTheme.green : AppTheme.cyan;
    }
    if (widget.connState.isConnecting) return AppTheme.gold;
    if (widget.connState.isScanning) return AppTheme.cyan;
    return AppTheme.red;
  }

  String get _statusText {
    switch (widget.connState.phase) {
      case ConnPhase.connected:
        final rssiStr = widget.connState.rssi != null ? ' (${widget.connState.rssi} dBm)' : '';
        return widget.isRelayOn ? 'RELAY CLOSED • ON$rssiStr' : 'RELAY OPEN • OFF$rssiStr';
      case ConnPhase.connecting:
        return 'CONNECTING...';
      case ConnPhase.reconnecting:
        return 'RECONNECTING...';
      case ConnPhase.scanning:
        return 'SCANNING FOR RELAY...';
      case ConnPhase.failed:
        return 'CONNECTION FAILED';
      case ConnPhase.disconnected:
      case ConnPhase.idle:
        return 'DISCONNECTED';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.12),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, _) {
              final scale = widget.isRelayOn || widget.connState.isConnecting
                  ? 0.8 + (_pulseController.value * 0.4)
                  : 1.0;
              final glowAlpha = widget.isRelayOn ? 0.8 : 0.4;

              return Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: glowAlpha),
                      blurRadius: 6 * scale,
                      spreadRadius: 2 * scale,
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 10),
          Text(
            _statusText,
            style: AppTheme.heading(
              size: 11.5,
              color: color,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
