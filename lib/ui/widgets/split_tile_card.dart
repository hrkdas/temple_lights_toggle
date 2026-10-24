import 'package:flutter/material.dart';
import '../../core/haptics.dart';
import '../theme.dart';

/// Next-generation Apple Home + Mushroom Card hybrid "Split-Tile" widget.
/// - Left circle: instant 0-latency power toggle with tactile haptic pulse.
/// - Card body: tap opens deep control drawer; drag across card scrubs brightness in real time.
/// - Dynamic Ambient Bloom: card surface radiates with the active light color when ON.
class SplitTileCard extends StatefulWidget {
  const SplitTileCard({
    super.key,
    required this.name,
    required this.roomLabel,
    required this.isOn,
    required this.brightness,
    required this.color,
    required this.modeLabel,
    required this.onTogglePower,
    required this.onOpenDetail,
    required this.onBrightnessScrub,
    this.isConnected = true,
  });

  final String name;
  final String roomLabel;
  final bool isOn;
  final int brightness; // 0..255
  final Color color;
  final String modeLabel;
  final VoidCallback onTogglePower;
  final VoidCallback onOpenDetail;
  final ValueChanged<int> onBrightnessScrub;
  final bool isConnected;

  @override
  State<SplitTileCard> createState() => _SplitTileCardState();
}

class _SplitTileCardState extends State<SplitTileCard> {
  bool _isScrubbing = false;
  int? _scrubValue;

  int get _effectiveBrightness => _scrubValue ?? widget.brightness;
  int get _brightnessPct => ((_effectiveBrightness / 255.0) * 100).round();

  void _handleHorizontalDragStart(DragStartDetails details, double width) {
    if (!widget.isConnected) return;
    setState(() {
      _isScrubbing = true;
    });
    _handleDragUpdate(details.localPosition.dx, width);
    AppHaptics.light();
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details, double width) {
    if (!_isScrubbing) return;
    _handleDragUpdate(details.localPosition.dx, width);
  }

  void _handleDragUpdate(double localX, double width) {
    // Body is right ~70% of tile width
    final bodyX = (localX - 60).clamp(0.0, width - 60);
    final frac = (bodyX / (width - 60)).clamp(0.0, 1.0);
    final val = (frac * 255).round();

    if (val != _scrubValue) {
      setState(() {
        _scrubValue = val;
      });
      widget.onBrightnessScrub(val);
      if (val % 25 == 0) {
        AppHaptics.selection();
      }
    }
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    if (!_isScrubbing) return;
    setState(() {
      _isScrubbing = false;
      _scrubValue = null;
    });
    AppHaptics.selection();
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = widget.isOn ? widget.color : AppTheme.textMuted;
    final isDeviceActive = widget.isOn && widget.brightness > 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: isDeviceActive
                ? widget.color.withValues(alpha: 0.12)
                : AppTheme.surfaceRaised,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDeviceActive
                  ? widget.color.withValues(alpha: 0.45)
                  : AppTheme.border,
              width: isDeviceActive ? 1.5 : 1.0,
            ),
            boxShadow: isDeviceActive
                ? [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.18),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: widget.onOpenDetail,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragStart: (d) => _handleHorizontalDragStart(d, totalWidth),
                onHorizontalDragUpdate: (d) => _handleHorizontalDragUpdate(d, totalWidth),
                onHorizontalDragEnd: _handleHorizontalDragEnd,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      // --- Left Split-Tile: Power Icon Button ---
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          AppHaptics.medium();
                          widget.onTogglePower();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDeviceActive
                                ? widget.color.withValues(alpha: 0.25)
                                : const Color(0xFF231F1A),
                            border: Border.all(
                              color: isDeviceActive ? widget.color : AppTheme.border,
                              width: 1.5,
                            ),
                            boxShadow: isDeviceActive
                                ? [
                                    BoxShadow(
                                      color: widget.color.withValues(alpha: 0.35),
                                      blurRadius: 10,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Icon(
                            Icons.power_settings_new_rounded,
                            size: 22,
                            color: isDeviceActive ? widget.color : AppTheme.textMuted,
                          ),
                        ),
                      ),

                      const SizedBox(width: 14),

                      // --- Right Split-Tile: Device Information & Live Scrubber Feedback ---
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: Text(
                                    widget.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTheme.heading(
                                      size: 14,
                                      color: isDeviceActive ? AppTheme.textPrimary : AppTheme.textSecondary,
                                      letterSpacing: 0.6,
                                    ),
                                  ),
                                ),
                                if (isDeviceActive)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: widget.color.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '$_brightnessPct%',
                                      style: AppTheme.mono(
                                        size: 11,
                                        color: widget.color,
                                        weight: FontWeight.w700,
                                      ),
                                    ),
                                  )
                                else
                                  Text(
                                    'OFF',
                                    style: AppTheme.mono(size: 11, color: AppTheme.textMuted),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  widget.roomLabel,
                                  style: AppTheme.body(size: 11, color: AppTheme.textMuted),
                                ),
                                if (isDeviceActive)
                                  Text(
                                    widget.modeLabel,
                                    style: AppTheme.body(
                                      size: 11,
                                      color: activeColor,
                                      weight: FontWeight.w500,
                                    ),
                                  ),
                              ],
                            ),
                            if (_isScrubbing) ...[
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(2),
                                child: LinearProgressIndicator(
                                  value: _effectiveBrightness / 255.0,
                                  backgroundColor: AppTheme.border,
                                  valueColor: AlwaysStoppedAnimation(widget.color),
                                  minHeight: 3,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      const SizedBox(width: 8),

                      // Chevron indicator hinting deep sheet
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: AppTheme.textMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
