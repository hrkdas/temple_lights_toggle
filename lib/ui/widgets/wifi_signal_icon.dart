import 'package:flutter/material.dart';
import '../theme.dart';

/// Dynamic Wi-Fi signal icon that renders the exact signal strength arc/bars
/// based on the RSSI value in dBm.
class WifiSignalIcon extends StatelessWidget {
  const WifiSignalIcon({
    super.key,
    required this.rssi,
    this.size = 20,
    this.color,
    this.showQualityColor = true,
  });

  final int rssi;
  final double size;
  final Color? color;
  final bool showQualityColor;

  static int barsForRssi(int rssi) {
    if (rssi == 0 || rssi < -90) return 0;
    if (rssi >= -55) return 4;
    if (rssi >= -68) return 3;
    if (rssi >= -78) return 2;
    return 1;
  }

  static String qualityLabelForRssi(int rssi) {
    if (rssi == 0) return 'No Signal';
    if (rssi >= -55) return 'Excellent';
    if (rssi >= -68) return 'Good';
    if (rssi >= -78) return 'Fair';
    if (rssi >= -88) return 'Weak';
    return 'Critical';
  }

  static Color colorForRssi(int rssi) {
    if (rssi == 0 || rssi < -90) return AppTheme.textMuted;
    if (rssi >= -60) return AppTheme.green;
    if (rssi >= -75) return AppTheme.amber;
    return const Color(0xFFE57373); // Soft coral red
  }

  IconData get _iconData {
    final bars = barsForRssi(rssi);
    switch (bars) {
      case 4:
        return Icons.wifi_rounded;
      case 3:
        return Icons.network_wifi_3_bar_rounded;
      case 2:
        return Icons.wifi_2_bar_rounded;
      case 1:
        return Icons.wifi_1_bar_rounded;
      default:
        return Icons.wifi_off_rounded;
    }
  }

  Color get _effectiveColor {
    if (color != null) return color!;
    if (!showQualityColor) return AppTheme.amber;
    return colorForRssi(rssi);
  }

  @override
  Widget build(BuildContext context) {
    final bars = barsForRssi(rssi);
    final label = qualityLabelForRssi(rssi);

    return Semantics(
      label: 'Wi-Fi signal $label ($bars of 4 bars, $rssi dBm)',
      child: Icon(
        _iconData,
        size: size,
        color: _effectiveColor,
      ),
    );
  }
}
