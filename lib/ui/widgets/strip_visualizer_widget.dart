import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/haptics.dart';
import '../../domain/models.dart';
import '../theme.dart';

/// Interactive visual ruler and canvas representing an addressable WS2812B LED strip.
/// Allows zooming, segment selection, live glowing animations, and quick range input.
class StripVisualizerWidget extends StatefulWidget {
  const StripVisualizerWidget({
    super.key,
    required this.totalLeds,
    required this.segments,
    required this.onSegmentsChanged,
    this.readOnly = false,
    this.height = 80,
  });

  final int totalLeds;
  final List<LedSegment> segments;
  final ValueChanged<List<LedSegment>> onSegmentsChanged;
  final bool readOnly;
  final double height;

  @override
  State<StripVisualizerWidget> createState() => _StripVisualizerWidgetState();
}

class _StripVisualizerWidgetState extends State<StripVisualizerWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  int? _highlightedLedIndex;
  int? _dragStartIndex;
  int? _dragEndIndex;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  // --- Architectural Snap Presets ---
  void _applyFullStripPreset() {
    if (widget.readOnly || widget.totalLeds <= 0) return;
    AppHaptics.selection();
    final seg = LedSegment(
      start: 0,
      count: widget.totalLeds,
      r: 255,
      g: 147,
      b: 41,
      name: 'Full Strip',
    );
    widget.onSegmentsChanged([seg]);
  }

  void _applyCenterAltarPreset() {
    if (widget.readOnly || widget.totalLeds <= 0) return;
    AppHaptics.selection();
    final centerCount = (widget.totalLeds * 0.6).round().clamp(1, widget.totalLeds);
    final start = ((widget.totalLeds - centerCount) / 2).round().clamp(0, widget.totalLeds - 1);
    final seg = LedSegment(
      start: start,
      count: centerCount,
      r: 255,
      g: 180,
      b: 0,
      name: 'Center Altar Focus',
    );
    widget.onSegmentsChanged([seg]);
  }

  void _applyPillarsAndHaloPreset() {
    if (widget.readOnly || widget.totalLeds <= 0) return;
    AppHaptics.selection();
    final pillarCount = math.min(6, widget.totalLeds);
    final haloCount = math.min(6, widget.totalLeds);
    final haloStart = math.max(pillarCount, widget.totalLeds - haloCount);

    final seg1 = LedSegment(
      start: 0,
      count: pillarCount,
      r: 255,
      g: 147,
      b: 41,
      name: 'Pillar LEDs 1–$pillarCount',
    );

    final seg2 = LedSegment(
      start: haloStart,
      count: widget.totalLeds - haloStart,
      r: 255,
      g: 220,
      b: 100,
      name: 'Halo LEDs ${haloStart + 1}–${widget.totalLeds}',
    );

    widget.onSegmentsChanged([seg1, seg2]);
  }

  void _applyDualHalvesPreset() {
    if (widget.readOnly || widget.totalLeds <= 0) return;
    AppHaptics.selection();
    final half = widget.totalLeds ~/ 2;
    final seg1 = LedSegment(
      start: 0,
      count: half,
      r: 255,
      g: 147,
      b: 41,
      name: 'Left Sanctum',
    );
    final seg2 = LedSegment(
      start: half,
      count: widget.totalLeds - half,
      r: 255,
      g: 200,
      b: 60,
      name: 'Right Sanctum',
    );
    widget.onSegmentsChanged([seg1, seg2]);
  }

  void _showQuickRangeDialog() {
    final textController = TextEditingController(
      text: widget.segments.map((s) => '${s.start + 1}-${s.end + 1}').join(', '),
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.tune_rounded, color: AppTheme.amber, size: 22),
            const SizedBox(width: 8),
            Text('Quick Range Entry', style: AppTheme.heading(size: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter LED numbers or ranges separated by commas (e.g. 1-6, 100-105):',
              style: AppTheme.body(size: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              autofocus: true,
              style: AppTheme.body(size: 14),
              decoration: InputDecoration(
                hintText: 'e.g. 1-6, 100-105',
                hintStyle: AppTheme.body(size: 14, color: AppTheme.textMuted),
                filled: true,
                fillColor: AppTheme.surfaceRaised,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.amber),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Strip has ${widget.totalLeds} LEDs total (1 to ${widget.totalLeds}).',
              style: AppTheme.body(size: 11, color: AppTheme.textMuted),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: AppTheme.body(size: 13, color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.amber,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              final newSegs = _parseRanges(textController.text.trim());
              if (newSegs.isNotEmpty) {
                widget.onSegmentsChanged(newSegs);
              }
              Navigator.of(ctx).pop();
            },
            child: Text('Apply Ranges', style: AppTheme.heading(size: 13, color: Colors.black)),
          ),
        ],
      ),
    );
  }

  List<LedSegment> _parseRanges(String input) {
    if (input.trim().isEmpty) return [];
    final parts = input.split(RegExp(r'[,;]+'));
    final List<LedSegment> parsed = [];

    for (final raw in parts) {
      final part = raw.trim();
      if (part.isEmpty) continue;

      if (part.contains('-')) {
        final bounds = part.split('-');
        if (bounds.length == 2) {
          final s1 = int.tryParse(bounds[0].trim());
          final s2 = int.tryParse(bounds[1].trim());
          if (s1 != null && s2 != null && s1 > 0 && s2 >= s1) {
            final start0 = (s1 - 1).clamp(0, widget.totalLeds - 1);
            final end0 = (s2 - 1).clamp(start0, widget.totalLeds - 1);
            final count = end0 - start0 + 1;
            parsed.add(LedSegment(
              start: start0,
              count: count,
              r: 255,
              g: 147,
              b: 41,
              name: 'LEDs #$s1–#$s2',
            ));
          }
        }
      } else {
        final single = int.tryParse(part);
        if (single != null && single > 0 && single <= widget.totalLeds) {
          final idx0 = single - 1;
          parsed.add(LedSegment(
            start: idx0,
            count: 1,
            r: 255,
            g: 147,
            b: 41,
            name: 'LED #$single',
          ));
        }
      }
    }
    return parsed;
  }

  int _posToLedIndex(Offset localPos, double width) {
    if (widget.totalLeds <= 0 || width <= 24) return 0;
    final usableWidth = width - 24;
    final relX = (localPos.dx - 12).clamp(0.0, usableWidth);
    final frac = relX / usableWidth;
    return (frac * widget.totalLeds).floor().clamp(0, widget.totalLeds - 1);
  }

  void _onTapStrip(Offset localPos, double width) {
    if (widget.totalLeds <= 0) return;
    final tappedIndex = _posToLedIndex(localPos, width);
    setState(() {
      _highlightedLedIndex = tappedIndex;
    });
    AppHaptics.selection();
  }

  void _onDragStart(DragStartDetails details, double width) {
    if (widget.readOnly || widget.totalLeds <= 0) return;
    final idx = _posToLedIndex(details.localPosition, width);
    setState(() {
      _dragStartIndex = idx;
      _dragEndIndex = idx;
      _highlightedLedIndex = idx;
    });
    AppHaptics.light();
  }

  void _onDragUpdate(DragUpdateDetails details, double width) {
    if (widget.readOnly || widget.totalLeds <= 0 || _dragStartIndex == null) return;
    final idx = _posToLedIndex(details.localPosition, width);
    if (idx != _dragEndIndex) {
      setState(() {
        _dragEndIndex = idx;
      });
      AppHaptics.selection();
    }
  }

  void _onDragEnd(DragEndDetails details) {
    if (widget.readOnly || widget.totalLeds <= 0) return;
    if (_dragStartIndex != null && _dragEndIndex != null) {
      final s = math.min(_dragStartIndex!, _dragEndIndex!);
      final e = math.max(_dragStartIndex!, _dragEndIndex!);
      final count = e - s + 1;

      final newSeg = LedSegment(
        start: s,
        count: count,
        r: 255,
        g: 147,
        b: 41,
        name: count == 1 ? 'LED #${s + 1}' : 'LEDs #${s + 1}–#${e + 1}',
      );

      widget.onSegmentsChanged([newSeg]);
      AppHaptics.medium();
    }

    setState(() {
      _dragStartIndex = null;
      _dragEndIndex = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Strip Overview Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.linear_scale_rounded, size: 16, color: AppTheme.amber),
                const SizedBox(width: 6),
                Text(
                  'LED STRIP RULER (${widget.totalLeds} LEDs)',
                  style: AppTheme.heading(size: 12, color: AppTheme.textSecondary, letterSpacing: 1.2),
                ),
              ],
            ),
            if (!widget.readOnly)
              TextButton.icon(
                icon: const Icon(Icons.add_circle_outline_rounded, size: 14, color: AppTheme.amber),
                label: Text(
                  'Quick Range',
                  style: AppTheme.heading(size: 11, color: AppTheme.amber),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: _showQuickRangeDialog,
              ),
          ],
        ),
        const SizedBox(height: 8),

        // Animated Interactive Strip Canvas with Touch Drag Range Selection
        LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            return GestureDetector(
              onTapUp: (details) => _onTapStrip(details.localPosition, w),
              onHorizontalDragStart: (details) => _onDragStart(details, w),
              onHorizontalDragUpdate: (details) => _onDragUpdate(details, w),
              onHorizontalDragEnd: _onDragEnd,
              child: Container(
                height: widget.height,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF141210),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _dragStartIndex != null ? AppTheme.amber : AppTheme.border,
                    width: _dragStartIndex != null ? 1.6 : 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: AnimatedBuilder(
                    animation: _animController,
                    builder: (context, child) {
                      return CustomPaint(
                        painter: _StripPainter(
                          totalLeds: widget.totalLeds,
                          segments: widget.segments,
                          highlightIndex: _highlightedLedIndex,
                          dragStartIndex: _dragStartIndex,
                          dragEndIndex: _dragEndIndex,
                          animPhase: _animController.value,
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),

        // Subtext / Legend
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('LED #1 (Start)', style: AppTheme.body(size: 10, color: AppTheme.textMuted)),
            if (_dragStartIndex != null && _dragEndIndex != null)
              Text(
                'Selecting: LEDs #${math.min(_dragStartIndex!, _dragEndIndex!) + 1}–#${math.max(_dragStartIndex!, _dragEndIndex!) + 1}',
                style: AppTheme.heading(size: 11, color: AppTheme.amber),
              )
            else if (_highlightedLedIndex != null)
              Text(
                'Selected: LED #${_highlightedLedIndex! + 1}',
                style: AppTheme.heading(size: 11, color: AppTheme.amber),
              ),
            Text('LED #${widget.totalLeds} (End)', style: AppTheme.body(size: 10, color: AppTheme.textMuted)),
          ],
        ),

        // Architectural Snap Presets
        if (!widget.readOnly) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              _buildSnapChip(
                label: 'Pillars & Halo',
                icon: '🏛️',
                onTap: _applyPillarsAndHaloPreset,
              ),
              const SizedBox(width: 6),
              _buildSnapChip(
                label: 'Center Altar',
                icon: '🛕',
                onTap: _applyCenterAltarPreset,
              ),
              const SizedBox(width: 6),
              _buildSnapChip(
                label: 'Full Strip',
                icon: '✨',
                onTap: _applyFullStripPreset,
              ),
              const SizedBox(width: 6),
              _buildSnapChip(
                label: 'Dual Halves',
                icon: '🌗',
                onTap: _applyDualHalvesPreset,
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildSnapChip({
    required String label,
    required String icon,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          decoration: BoxDecoration(
            color: AppTheme.surfaceRaised,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(icon, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 2),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.heading(size: 9.5, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StripPainter extends CustomPainter {
  _StripPainter({
    required this.totalLeds,
    required this.segments,
    this.highlightIndex,
    this.dragStartIndex,
    this.dragEndIndex,
    required this.animPhase,
  });

  final int totalLeds;
  final List<LedSegment> segments;
  final int? highlightIndex;
  final int? dragStartIndex;
  final int? dragEndIndex;
  final double animPhase;

  @override
  void paint(Canvas canvas, Size size) {
    if (totalLeds <= 0) return;

    final centerY = size.height * 0.5;
    final trackY = centerY;

    // Draw background track PCB line
    final trackPaint = Paint()
      ..color = const Color(0xFF2C2720)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(12, trackY), Offset(size.width - 12, trackY), trackPaint);

    final usableWidth = size.width - 24;
    final step = usableWidth / totalLeds;

    // Draw drag selection bounding box if dragging
    if (dragStartIndex != null && dragEndIndex != null) {
      final s = math.min(dragStartIndex!, dragEndIndex!);
      final e = math.max(dragStartIndex!, dragEndIndex!);
      final leftX = 12 + s * step;
      final rightX = 12 + (e + 1) * step;

      final selRect = Rect.fromLTRB(leftX, centerY - 18, rightX, centerY + 18);
      final selRRect = RRect.fromRectAndRadius(selRect, const Radius.circular(8));

      final selFill = Paint()..color = AppTheme.amber.withValues(alpha: 0.22);
      final selBorder = Paint()
        ..color = AppTheme.amber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8;

      canvas.drawRRect(selRRect, selFill);
      canvas.drawRRect(selRRect, selBorder);
    }

    // Build LED color lookup
    final List<Color?> ledColors = List.filled(totalLeds, null);
    final List<int> ledEffects = List.filled(totalLeds, 0);

    for (final seg in segments) {
      final sEnd = (seg.start + seg.count).clamp(0, totalLeds);
      for (int i = seg.start; i < sEnd; i++) {
        ledColors[i] = seg.color;
        ledEffects[i] = seg.effect;
      }
    }

    // Draw LED pixels
    final ledRadius = (step * 0.45).clamp(2.5, 6.0);

    for (int i = 0; i < totalLeds; i++) {
      final cx = 12 + i * step + step * 0.5;
      final color = ledColors[i];

      if (color != null) {
        // Active glowing LED
        final fx = ledEffects[i];
        double pulse = 1.0;

        if (fx == 1) { // Breathe
          pulse = 0.7 + 0.3 * (0.5 * (1.0 + math.sin(animPhase * 2 * math.pi)));
        } else if (fx == 2) { // Diya Flutter
          pulse = 0.8 + 0.2 * math.sin(animPhase * 18 + i);
        }

        final activeColor = color.withValues(alpha: pulse.clamp(0.2, 1.0));

        // Radiant Aura Glow
        final glowPaint = Paint()
          ..color = activeColor.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
        canvas.drawCircle(Offset(cx, centerY), ledRadius * 2.2, glowPaint);

        // Core LED body
        final ledPaint = Paint()..color = activeColor;
        canvas.drawCircle(Offset(cx, centerY), ledRadius, ledPaint);

        // Bright white center phosphor point
        final centerPointPaint = Paint()..color = Colors.white.withValues(alpha: 0.85);
        canvas.drawCircle(Offset(cx, centerY), ledRadius * 0.35, centerPointPaint);
      } else {
        // Dark unlit LED
        final offPaint = Paint()..color = const Color(0xFF383228);
        canvas.drawCircle(Offset(cx, centerY), ledRadius * 0.75, offPaint);
      }

      // Highlight marker if tapped
      if (highlightIndex == i) {
        final ringPaint = Paint()
          ..color = AppTheme.amber
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        canvas.drawCircle(Offset(cx, centerY), ledRadius * 2.8, ringPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StripPainter oldDelegate) {
    return oldDelegate.animPhase != animPhase ||
        oldDelegate.segments != segments ||
        oldDelegate.totalLeds != totalLeds ||
        oldDelegate.highlightIndex != highlightIndex ||
        oldDelegate.dragStartIndex != dragStartIndex ||
        oldDelegate.dragEndIndex != dragEndIndex;
  }
}
