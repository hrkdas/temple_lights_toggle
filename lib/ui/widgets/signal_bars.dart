import 'package:flutter/material.dart';
import '../theme.dart';

/// 4-bar RSSI signal visualizer.
class SignalBars extends StatelessWidget {
  const SignalBars({
    super.key,
    required this.rssi,
    this.color = AppTheme.cyan,
  });

  final int rssi;
  final Color color;

  int get _activeBars {
    if (rssi >= -60) return 4;
    if (rssi >= -70) return 3;
    if (rssi >= -80) return 2;
    if (rssi >= -90) return 1;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final bars = _activeBars;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (i) {
        final filled = i < bars;
        return Padding(
          padding: const EdgeInsets.only(right: 2.5),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 3.5,
            height: 6.0 + (i * 3.5),
            decoration: BoxDecoration(
              color: filled ? color : color.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(1.0),
            ),
          ),
        );
      }),
    );
  }
}
