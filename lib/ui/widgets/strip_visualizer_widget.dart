import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/haptics.dart';
import '../../domain/models.dart';
import '../theme.dart';
import 'zone_config_sheet.dart';

/// Interactive visual ruler, ring mandala canvas, and pattern studio representing an addressable WS2812B LED strip.
/// Supports All-LEDs uniform mode, Alternate Odd/Even interleaving with dual colors and twinkling sparkle,
/// Circular Ring / Linear Strip dual projection, and arbitrary multi-segment zoning.
class StripVisualizerWidget extends StatefulWidget {
  const StripVisualizerWidget({
    super.key,
    required this.totalLeds,
    required this.segments,
    required this.onSegmentsChanged,
    this.readOnly = false,
    this.height = 80,
    this.enableMultiSelect = true,
    this.enableTapToConfigure = true,
    this.showZoneChips = true,
    this.stripOrientation = 0,
    this.title,
    this.trailingHeaderAction,
  });

  final int totalLeds;
  final List<LedSegment> segments;
  final ValueChanged<List<LedSegment>> onSegmentsChanged;
  final bool readOnly;
  final double height;
  final bool enableMultiSelect;
  final bool enableTapToConfigure;
  final bool showZoneChips;
  final int stripOrientation;
  final String? title;
  final Widget? trailingHeaderAction;

  @override
  State<StripVisualizerWidget> createState() => _StripVisualizerWidgetState();
}

class _StripVisualizerWidgetState extends State<StripVisualizerWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  final Set<int> _selectedSegmentIndices = {};
  bool _multiSelectActive = false;
  int? _highlightedLedIndex;
  int? _dragStartIndex;
  int? _dragEndIndex;

  // Projection Toggle (Linear Strip vs Circular Halo Ring)
  bool _isRingView = false;

  // Alternate Mode State
  Color _oddColor = const Color(0xFFFF9329); // Warm Amber
  Color _evenColor = const Color(0xFFFFB400); // Saffron Gold
  bool _oddActive = true;
  bool _evenActive = true;
  int _oddEffect = 0; // 0=Solid, 1=Breathe, 2=Diya, 3=Twinkle
  int _evenEffect = 0;
  int _oddBrightness = 255;
  int _evenBrightness = 255;

  static const List<Map<String, dynamic>> _templePalette = [
    {'name': 'Warm Amber', 'color': Color(0xFFFF9329), 'r': 255, 'g': 147, 'b': 41},
    {'name': 'Saffron Gold', 'color': Color(0xFFFFB400), 'r': 255, 'g': 180, 'b': 0},
    {'name': 'Temple Red', 'color': Color(0xFFFF1E1E), 'r': 255, 'g': 30, 'b': 30},
    {'name': 'Sacred Blue', 'color': Color(0xFF0078FF), 'r': 0, 'g': 120, 'b': 255},
    {'name': 'Divine Cyan', 'color': Color(0xFF00E5FF), 'r': 0, 'g': 229, 'b': 255},
    {'name': 'Lotus Pink', 'color': Color(0xFFFF50A0), 'r': 255, 'g': 80, 'b': 160},
    {'name': 'Holy Green', 'color': Color(0xFF00E676), 'r': 0, 'g': 230, 'b': 118},
    {'name': 'Pure White', 'color': Color(0xFFFFFFFF), 'r': 255, 'g': 255, 'b': 255},
  ];

  static const List<Map<String, dynamic>> _templeDuos = [
    {
      'title': 'Sanctum Dawn',
      'icon': '🛕',
      'c1': Color(0xFFFFB400), // Saffron Gold
      'c2': Color(0xFFFF9329), // Warm Amber
    },
    {
      'title': 'Diwali Diya',
      'icon': '🪔',
      'c1': Color(0xFFFF1E1E), // Temple Red
      'c2': Color(0xFFFFB400), // Saffron Gold
    },
    {
      'title': 'Radha Krishna',
      'icon': '🦚',
      'c1': Color(0xFF0078FF), // Sacred Blue
      'c2': Color(0xFFFF50A0), // Lotus Pink
    },
    {
      'title': 'Divine Shiva',
      'icon': '🕊️',
      'c1': Color(0xFFFFFFFF), // Pure White
      'c2': Color(0xFF00E5FF), // Divine Cyan
    },
    {
      'title': 'Tulsi Sanctum',
      'icon': '🌿',
      'c1': Color(0xFF00E676), // Holy Green
      'c2': Color(0xFFFFB400), // Saffron Gold
    },
  ];

  bool get _isAlternateMode => widget.segments.any((s) => s.isAlternate);
  bool get _isAllLedsMode =>
      !_isAlternateMode &&
      (widget.segments.isEmpty ||
          (widget.segments.length == 1 &&
              widget.segments.first.start == 0 &&
              widget.segments.first.count >= widget.totalLeds &&
              widget.segments.first.stride <= 1));

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _syncAlternateState();
  }

  @override
  void didUpdateWidget(covariant StripVisualizerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _selectedSegmentIndices.removeWhere((idx) => idx >= widget.segments.length);
    _syncAlternateState();
  }

  void _syncAlternateState() {
    for (final seg in widget.segments) {
      if (seg.isAlternateOdd) {
        _oddColor = seg.color;
        _oddEffect = seg.effect;
        _oddBrightness = seg.brightness;
        _oddActive = seg.brightness > 0;
      } else if (seg.isAlternateEven) {
        _evenColor = seg.color;
        _evenEffect = seg.effect;
        _evenBrightness = seg.brightness;
        _evenActive = seg.brightness > 0;
      }
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  // --- Hit Testing & Segment Lookup ---
  int? _findSegmentIndexAt(int ledIndex) {
    for (int i = 0; i < widget.segments.length; i++) {
      if (widget.segments[i].containsLed(ledIndex)) {
        return i;
      }
    }
    return null;
  }

  // --- Pop-up Sheet Trigger ---
  void _openConfigSheet() {
    if (widget.readOnly || _selectedSegmentIndices.isEmpty) return;

    ZoneConfigSheet.show(
      context: context,
      segments: widget.segments,
      selectedIndices: _selectedSegmentIndices,
      totalLeds: widget.totalLeds,
      onSegmentsUpdated: (newSegs) {
        widget.onSegmentsChanged(newSegs);
      },
      onSelectionCleared: () {
        setState(() {
          _selectedSegmentIndices.clear();
        });
      },
      onDeleteSelected: () {
        final remaining = <LedSegment>[];
        for (int i = 0; i < widget.segments.length; i++) {
          if (!_selectedSegmentIndices.contains(i)) {
            remaining.add(widget.segments[i]);
          }
        }
        if (remaining.isEmpty) {
          remaining.add(LedSegment.allLeds(totalLeds: widget.totalLeds));
        }
        setState(() {
          _selectedSegmentIndices.clear();
        });
        widget.onSegmentsChanged(remaining);
      },
    );
  }

  // --- Alternate Mode Handlers ---
  void _applyAlternateSegments() {
    final List<LedSegment> newSegs = [];
    if (_oddActive) {
      newSegs.add(LedSegment.alternateOdd(
        totalLeds: widget.totalLeds,
        r: (_oddColor.r * 255.0).round().clamp(0, 255),
        g: (_oddColor.g * 255.0).round().clamp(0, 255),
        b: (_oddColor.b * 255.0).round().clamp(0, 255),
        brightness: _oddBrightness,
        effect: _oddEffect,
      ));
    }
    if (_evenActive) {
      newSegs.add(LedSegment.alternateEven(
        totalLeds: widget.totalLeds,
        r: (_evenColor.r * 255.0).round().clamp(0, 255),
        g: (_evenColor.g * 255.0).round().clamp(0, 255),
        b: (_evenColor.b * 255.0).round().clamp(0, 255),
        brightness: _evenBrightness,
        effect: _evenEffect,
      ));
    }
    if (newSegs.isEmpty) {
      newSegs.add(LedSegment(start: 0, count: widget.totalLeds, brightness: 0));
    }
    setState(() {
      _selectedSegmentIndices.clear();
    });
    widget.onSegmentsChanged(newSegs);
  }

  void _swapAlternateColors() {
    AppHaptics.selection();
    final tempColor = _oddColor;
    final tempFx = _oddEffect;
    final tempActive = _oddActive;
    setState(() {
      _oddColor = _evenColor;
      _evenColor = tempColor;
      _oddEffect = _evenEffect;
      _evenEffect = tempFx;
      _oddActive = _evenActive;
      _evenActive = tempActive;
    });
    _applyAlternateSegments();
  }

  void _applyAllLedsMode([Color? color, int? effect]) {
    AppHaptics.selection();
    final c = color ?? _oddColor;
    final fx = effect ?? _oddEffect;
    final seg = LedSegment.allLeds(
      totalLeds: widget.totalLeds,
      r: (c.r * 255.0).round().clamp(0, 255),
      g: (c.g * 255.0).round().clamp(0, 255),
      b: (c.b * 255.0).round().clamp(0, 255),
      brightness: _oddBrightness,
      effect: fx,
    );
    setState(() {
      _selectedSegmentIndices.clear();
    });
    widget.onSegmentsChanged([seg]);
  }

  void _applyCustomMode() {
    AppHaptics.selection();
    if (_isAllLedsMode || _isAlternateMode) {
      // Split into 2 initial customizable halves for quick editing
      _applyDualHalvesPreset();
    }
  }

  // --- Non-Destructive Auto-Add Region ---
  void _addNewSegmentAuto() {
    if (widget.readOnly || widget.totalLeds <= 0 || widget.segments.length >= 16) return;

    AppHaptics.selection();
    final updated = List<LedSegment>.from(widget.segments);

    // Look for first unassigned LED range
    final occupied = List<bool>.filled(widget.totalLeds, false);
    for (final seg in updated) {
      final end = (seg.start + seg.count).clamp(0, widget.totalLeds);
      for (int i = seg.start; i < end; i++) {
        occupied[i] = true;
      }
    }

    int gapStart = -1;
    int gapLength = 0;
    for (int i = 0; i < widget.totalLeds; i++) {
      if (!occupied[i]) {
        if (gapStart == -1) gapStart = i;
        gapLength++;
        if (gapLength >= 20) break;
      } else if (gapStart != -1) {
        break;
      }
    }

    LedSegment newSeg;
    if (gapStart != -1 && gapLength > 0) {
      newSeg = LedSegment(
        start: gapStart,
        count: gapLength,
        r: 255,
        g: 180,
        b: 0,
        name: 'Zone ${updated.length + 1}',
      );
    } else {
      // If strip is full, carve out a new center 15-LED zone
      final centerStart = (widget.totalLeds * 0.4).round().clamp(0, widget.totalLeds - 1);
      final centerCount = math.min(15, widget.totalLeds - centerStart);
      newSeg = LedSegment(
        start: centerStart,
        count: centerCount,
        r: 255,
        g: 80,
        b: 160,
        name: 'Zone ${updated.length + 1}',
      );
    }

    updated.add(newSeg);
    updated.sort((a, b) => a.start.compareTo(b.start));
    final newIdx = updated.indexOf(newSeg);

    setState(() {
      if (!_multiSelectActive) {
        _selectedSegmentIndices.clear();
      }
      if (newIdx != -1) {
        _selectedSegmentIndices.add(newIdx);
      }
    });

    widget.onSegmentsChanged(updated);
    _openConfigSheet();
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
    setState(() {
      _selectedSegmentIndices.clear();
      _selectedSegmentIndices.add(0);
    });
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
    setState(() {
      _selectedSegmentIndices.clear();
      _selectedSegmentIndices.add(0);
    });
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

    setState(() {
      _selectedSegmentIndices.clear();
    });
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
    setState(() {
      _selectedSegmentIndices.clear();
    });
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
                setState(() {
                  _selectedSegmentIndices.clear();
                });
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
    final segIdx = _findSegmentIndexAt(tappedIndex);

    if (segIdx != null) {
      AppHaptics.selection();
      setState(() {
        _highlightedLedIndex = tappedIndex;
        if (_multiSelectActive) {
          if (_selectedSegmentIndices.contains(segIdx)) {
            _selectedSegmentIndices.remove(segIdx);
          } else {
            _selectedSegmentIndices.add(segIdx);
          }
        } else {
          _selectedSegmentIndices
            ..clear()
            ..add(segIdx);
        }
      });

      if (!_multiSelectActive && widget.enableTapToConfigure && !widget.readOnly && !_isAlternateMode && !_isAllLedsMode) {
        _openConfigSheet();
      }
    } else {
      setState(() {
        _highlightedLedIndex = tappedIndex;
        if (!_multiSelectActive) {
          _selectedSegmentIndices.clear();
        }
      });
    }
  }

  void _onTapRing(Offset localPos, Size size) {
    if (widget.totalLeds <= 0) return;
    final center = Offset(size.width * 0.5, size.height * 0.5);
    final dx = localPos.dx - center.dx;
    final dy = localPos.dy - center.dy;
    double angle = math.atan2(dy, dx) + math.pi * 0.5;
    if (angle < 0) angle += 2 * math.pi;
    final frac = angle / (2 * math.pi);
    final tappedIndex = (frac * widget.totalLeds).floor().clamp(0, widget.totalLeds - 1);

    AppHaptics.selection();
    setState(() {
      _highlightedLedIndex = tappedIndex;
    });

    final segIdx = _findSegmentIndexAt(tappedIndex);
    if (segIdx != null) {
      setState(() {
        _selectedSegmentIndices
          ..clear()
          ..add(segIdx);
      });
      if (widget.enableTapToConfigure && !widget.readOnly && !_isAlternateMode && !_isAllLedsMode) {
        _openConfigSheet();
      }
    }
  }

  void _onDragStart(DragStartDetails details, double width) {
    if (widget.readOnly || widget.totalLeds <= 0) return;
    final startIdx = _posToLedIndex(details.localPosition, width);
    setState(() {
      _dragStartIndex = startIdx;
      _dragEndIndex = startIdx;
      _highlightedLedIndex = startIdx;
    });
    AppHaptics.selection();
  }

  void _onDragUpdate(DragUpdateDetails details, double width) {
    if (widget.readOnly || widget.totalLeds <= 0 || _dragStartIndex == null) return;
    final currIdx = _posToLedIndex(details.localPosition, width);
    if (currIdx != _dragEndIndex) {
      setState(() {
        _dragEndIndex = currIdx;
        _highlightedLedIndex = currIdx;
      });
      AppHaptics.light();
    }
  }

  void _onDragEnd(DragEndDetails details) {
    if (widget.readOnly || _dragStartIndex == null || _dragEndIndex == null) return;

    final s = math.min(_dragStartIndex!, _dragEndIndex!);
    final e = math.max(_dragStartIndex!, _dragEndIndex!);
    final count = e - s + 1;

    if (count > 0) {
      final newSeg = LedSegment(
        start: s,
        count: count,
        r: 255,
        g: 147,
        b: 41,
        name: count == 1 ? 'LED #${s + 1}' : 'LEDs #${s + 1}–#${e + 1}',
      );

      final updated = List<LedSegment>.from(widget.segments);
      final overlappingIndices = <int>[];
      for (int i = 0; i < updated.length; i++) {
        if (updated[i].overlaps(newSeg)) {
          overlappingIndices.add(i);
        }
      }

      int targetIndex;
      if (overlappingIndices.length == 1 && updated[overlappingIndices.first].count == widget.totalLeds && updated[overlappingIndices.first].stride <= 1) {
        updated[overlappingIndices.first] = newSeg;
        targetIndex = overlappingIndices.first;
      } else if (overlappingIndices.isNotEmpty) {
        targetIndex = overlappingIndices.first;
        updated[targetIndex] = newSeg;
        for (int i = overlappingIndices.length - 1; i > 0; i--) {
          final idx = overlappingIndices[i];
          if (idx < updated.length) {
            updated.removeAt(idx);
          }
        }
      } else {
        if (updated.length < 16) {
          updated.add(newSeg);
          targetIndex = updated.length - 1;
        } else {
          targetIndex = updated.length - 1;
          updated[targetIndex] = newSeg;
        }
      }

      updated.sort((a, b) => a.start.compareTo(b.start));
      final finalIdx = updated.indexOf(newSeg);

      setState(() {
        if (!_multiSelectActive) {
          _selectedSegmentIndices.clear();
        }
        if (finalIdx != -1) {
          _selectedSegmentIndices.add(finalIdx);
        }
      });

      widget.onSegmentsChanged(updated);
      AppHaptics.medium();

      if (!_multiSelectActive && widget.enableTapToConfigure) {
        _openConfigSheet();
      }
    }

    setState(() {
      _dragStartIndex = null;
      _dragEndIndex = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final titleText = widget.title ?? 'LED STRIP RULER (${widget.totalLeds} LEDs)';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Strip/Ring Header with Projection Toggle, Multi-Select & Quick Range
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isRingView ? Icons.donut_large_rounded : Icons.linear_scale_rounded,
                    size: 16,
                    color: AppTheme.amber,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      titleText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.heading(size: 11, color: AppTheme.textSecondary, letterSpacing: 1.1),
                    ),
                  ),
                  if (widget.stripOrientation == 1) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: AppTheme.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppTheme.amber.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        'RTL',
                        style: AppTheme.mono(size: 8.5, color: AppTheme.amber),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (!widget.readOnly)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Projection Toggle (Ring Halo vs Strip Ruler)
                    _buildProjectionToggle(),
                    const SizedBox(width: 6),
                    // Multi-Select Toggle Pill
                    if (widget.enableMultiSelect)
                      InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          AppHaptics.selection();
                          setState(() {
                            _multiSelectActive = !_multiSelectActive;
                            if (!_multiSelectActive && _selectedSegmentIndices.length > 1) {
                              final first = _selectedSegmentIndices.first;
                              _selectedSegmentIndices
                                ..clear()
                                ..add(first);
                            }
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _multiSelectActive
                                ? AppTheme.amber.withValues(alpha: 0.22)
                                : AppTheme.surfaceRaised,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _multiSelectActive ? AppTheme.amber : AppTheme.border,
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _multiSelectActive ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                                size: 13,
                                color: _multiSelectActive ? AppTheme.amber : AppTheme.textMuted,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Multi-Select',
                                style: AppTheme.heading(
                                  size: 10,
                                  color: _multiSelectActive ? AppTheme.amber : AppTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(width: 6),
                    TextButton.icon(
                      icon: const Icon(Icons.add_circle_outline_rounded, size: 14, color: AppTheme.amber),
                      label: Text(
                        'Quick Range',
                        style: AppTheme.heading(size: 10.5, color: AppTheme.amber),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: _showQuickRangeDialog,
                    ),
                    if (widget.trailingHeaderAction != null) ...[
                      const SizedBox(width: 6),
                      widget.trailingHeaderAction!,
                    ],
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),

        // Mode Selector Bar (All LEDs | Alternate Odd/Even | Custom Zones)
        if (!widget.readOnly) _buildModeSelectorBar(),

        // Animated Interactive Strip or Circular Halo Canvas
        LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final canvasHeight = _isRingView ? 170.0 : widget.height;

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) {
                if (_isRingView) {
                  _onTapRing(details.localPosition, Size(w, canvasHeight));
                } else {
                  _onTapStrip(details.localPosition, w);
                }
              },
              onHorizontalDragStart: _isRingView ? null : (details) => _onDragStart(details, w),
              onHorizontalDragUpdate: _isRingView ? null : (details) => _onDragUpdate(details, w),
              onHorizontalDragEnd: _isRingView ? null : _onDragEnd,
              child: Container(
                height: canvasHeight,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF141210),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _dragStartIndex != null
                        ? AppTheme.amber
                        : (_selectedSegmentIndices.isNotEmpty ? AppTheme.amber.withValues(alpha: 0.5) : AppTheme.border),
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
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _animController,
                        builder: (context, child) {
                          if (_isRingView) {
                            return CustomPaint(
                              size: Size(w, canvasHeight),
                              painter: _RingPainter(
                                totalLeds: widget.totalLeds,
                                segments: widget.segments,
                                selectedSegmentIndices: _selectedSegmentIndices,
                                highlightIndex: _highlightedLedIndex,
                                animPhase: _animController.value,
                              ),
                            );
                          }
                          return CustomPaint(
                            size: Size(w, canvasHeight),
                            painter: _StripPainter(
                              totalLeds: widget.totalLeds,
                              segments: widget.segments,
                              selectedSegmentIndices: _selectedSegmentIndices,
                              highlightIndex: _highlightedLedIndex,
                              dragStartIndex: _dragStartIndex,
                              dragEndIndex: _dragEndIndex,
                              animPhase: _animController.value,
                            ),
                          );
                        },
                      ),
                      if (_isRingView)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF141210).withValues(alpha: 0.85),
                            shape: BoxShape.circle,
                            border: Border.all(color: AppTheme.borderBright, width: 1.2),
                            boxShadow: [
                              BoxShadow(
                                color: (_isAlternateMode ? _oddColor : (_isAllLedsMode ? _oddColor : AppTheme.amber))
                                    .withValues(alpha: 0.25),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _isAlternateMode ? '⚡' : (_isAllLedsMode ? '✨' : '🎨'),
                                style: const TextStyle(fontSize: 16),
                              ),
                              Text(
                                '${widget.totalLeds} LEDs',
                                style: AppTheme.mono(size: 9, color: AppTheme.amber),
                              ),
                            ],
                          ),
                        ),
                    ],
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
            Text(
              _isRingView
                  ? 'LED #1 (Top • 12 o\'clock)'
                  : (widget.stripOrientation == 1 ? 'LED #1 (Left • Inverted)' : 'LED #1 (Left)'),
              style: AppTheme.body(size: 10, color: AppTheme.textMuted),
            ),
            if (_dragStartIndex != null && _dragEndIndex != null)
              Text(
                'Selecting: LEDs #${math.min(_dragStartIndex!, _dragEndIndex!) + 1}–#${math.max(_dragStartIndex!, _dragEndIndex!) + 1}',
                style: AppTheme.heading(size: 11, color: AppTheme.amber),
              )
            else if (_isAlternateMode)
              Text(
                'Alternate Odd / Even Interleaved',
                style: AppTheme.heading(size: 10.5, color: AppTheme.amber),
              )
            else if (_selectedSegmentIndices.isNotEmpty)
              Text(
                '${_selectedSegmentIndices.length} Region${_selectedSegmentIndices.length > 1 ? "s" : ""} Selected (Tap to Configure)',
                style: AppTheme.heading(size: 10.5, color: AppTheme.amber),
              )
            else if (_highlightedLedIndex != null)
              Text(
                'LED #${_highlightedLedIndex! + 1}',
                style: AppTheme.heading(size: 11, color: AppTheme.amber),
              ),
            Text(
              _isRingView ? 'LED #${widget.totalLeds} (Full Ring)' : 'LED #${widget.totalLeds} (Right)',
              style: AppTheme.body(size: 10, color: AppTheme.textMuted),
            ),
          ],
        ),

        // Contextual Controls: Alternate Mode Panel OR All LEDs Palette & Architectural Snap Presets
        if (!widget.readOnly && _isAlternateMode) ...[
          _buildAlternateControlPanel(),
        ] else ...[
          if (!widget.readOnly && _isAllLedsMode) ...[
            _buildAllLedsControlPanel(),
          ],

          // Interactive Zone Chips Track for Custom Mode
          if (widget.showZoneChips && widget.segments.isNotEmpty && !_isAllLedsMode) ...[
            const SizedBox(height: 10),
            _buildZoneChipsTrack(),
          ],

          // Floating Batch Action Pill when Regions are Selected
          if (_selectedSegmentIndices.isNotEmpty && !widget.readOnly) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.amber.withValues(alpha: 0.45)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.layers_rounded, size: 16, color: AppTheme.amber),
                      const SizedBox(width: 8),
                      Text(
                        '${_selectedSegmentIndices.length} Selected',
                        style: AppTheme.heading(size: 11.5, color: AppTheme.amber),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () {
                          AppHaptics.selection();
                          setState(() {
                            _selectedSegmentIndices.clear();
                          });
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text('Deselect', style: AppTheme.body(size: 11, color: AppTheme.textMuted)),
                      ),
                      const SizedBox(width: 6),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.palette_rounded, size: 13, color: Colors.black),
                        label: Text(
                          'Configure Light',
                          style: AppTheme.heading(size: 11, color: Colors.black),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.amber,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _openConfigSheet,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

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
      ],
    );
  }

  Widget _buildProjectionToggle() {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        AppHaptics.selection();
        setState(() {
          _isRingView = !_isRingView;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: _isRingView ? AppTheme.amber.withValues(alpha: 0.22) : AppTheme.surfaceRaised,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _isRingView ? AppTheme.amber : AppTheme.border,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isRingView ? Icons.donut_large_rounded : Icons.linear_scale_rounded,
              size: 13,
              color: _isRingView ? AppTheme.amber : AppTheme.textMuted,
            ),
            const SizedBox(width: 4),
            Text(
              _isRingView ? 'Ring Halo' : 'Strip Ruler',
              style: AppTheme.heading(
                size: 10,
                color: _isRingView ? AppTheme.amber : AppTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeSelectorBar() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.surfaceRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          _buildModeTab('✨ All LEDs', _isAllLedsMode, () {
            _applyAllLedsMode();
          }),
          _buildModeTab('⚡ Alternate (Odd / Even)', _isAlternateMode, () {
            _applyAlternateSegments();
          }),
          _buildModeTab('🎨 Custom Zones', !_isAllLedsMode && !_isAlternateMode, () {
            _applyCustomMode();
          }),
        ],
      ),
    );
  }

  Widget _buildModeTab(String label, bool isSelected, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () {
          AppHaptics.selection();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.amber.withValues(alpha: 0.22) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: isSelected ? AppTheme.amber : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppTheme.heading(
              size: 10.5,
              color: isSelected ? AppTheme.amber : AppTheme.textMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAllLedsControlPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'ALL LEDS COLOR HARMONY',
              style: AppTheme.heading(size: 10, color: AppTheme.textMuted, letterSpacing: 1.0),
            ),
            Text(
              'Uniform Strip Illumination',
              style: AppTheme.mono(size: 9.5, color: AppTheme.amber),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _templePalette.map((p) {
            final col = p['color'] as Color;
            final isSel = _oddColor.toARGB32() == col.toARGB32();
            return InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _applyAllLedsMode(col),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isSel ? AppTheme.amber.withValues(alpha: 0.18) : AppTheme.surfaceRaised,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSel ? AppTheme.amber : AppTheme.border,
                    width: isSel ? 1.5 : 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: col,
                        border: Border.all(color: Colors.white, width: 1),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      p['name'] as String,
                      style: AppTheme.heading(
                        size: 10.5,
                        color: isSel ? AppTheme.amber : AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildAlternateControlPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        // Odd & Even Dual Cards
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildAlternateCard(
                title: 'Odd LEDs (#1, #3...)',
                subtitle: _oddActive ? 'Active' : 'Muted (Off)',
                color: _oddColor,
                isActive: _oddActive,
                onColorSelected: (c) {
                  setState(() {
                    _oddColor = c;
                    _oddActive = true;
                  });
                  _applyAlternateSegments();
                },
                onToggleActive: () {
                  setState(() => _oddActive = !_oddActive);
                  _applyAlternateSegments();
                },
              ),
            ),
            const SizedBox(width: 8),
            // Center Swap Button
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Column(
                children: [
                  IconButton(
                    tooltip: 'Swap Colors',
                    icon: const Icon(Icons.swap_horiz_rounded, color: AppTheme.amber, size: 20),
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.surfaceRaised,
                      padding: const EdgeInsets.all(8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(color: AppTheme.border),
                      ),
                    ),
                    onPressed: _swapAlternateColors,
                  ),
                  const SizedBox(height: 2),
                  Text('Swap', style: AppTheme.mono(size: 8.5, color: AppTheme.textMuted)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildAlternateCard(
                title: 'Even LEDs (#2, #4...)',
                subtitle: _evenActive ? 'Active' : 'Muted (Off)',
                color: _evenColor,
                isActive: _evenActive,
                onColorSelected: (c) {
                  setState(() {
                    _evenColor = c;
                    _evenActive = true;
                  });
                  _applyAlternateSegments();
                },
                onToggleActive: () {
                  setState(() => _evenActive = !_evenActive);
                  _applyAlternateSegments();
                },
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),
        // Alternate Motion & Sparkling Animation Picker
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'ALTERNATE MOTION & TWINKLE DYNAMICS',
              style: AppTheme.heading(size: 10, color: AppTheme.textMuted, letterSpacing: 1.0),
            ),
            Text(
              _oddEffect == 3
                  ? 'Sparkling Active'
                  : (_oddEffect == 2 ? 'Diya Flutter' : (_oddEffect == 1 ? 'Breathing' : 'Solid')),
              style: AppTheme.mono(size: 9.5, color: AppTheme.amber),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              _buildMotionChip('✨ Pure Solid', 0),
              const SizedBox(width: 6),
              _buildMotionChip('🌟 Starlight Twinkle (Sparkling)', 3),
              const SizedBox(width: 6),
              _buildMotionChip('🪔 Diya Flutter', 2),
              const SizedBox(width: 6),
              _buildMotionChip('🌬️ Gentle Breathe', 1),
            ],
          ),
        ),

        const SizedBox(height: 12),
        // Harmonious Temple Duos (1-tap sacred pairs)
        Text(
          'HARMONIOUS TEMPLE DUOS',
          style: AppTheme.heading(size: 10, color: AppTheme.textMuted, letterSpacing: 1.0),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: _templeDuos.map((duo) {
              final c1 = duo['c1'] as Color;
              final c2 = duo['c2'] as Color;
              final isMatch = _oddColor.toARGB32() == c1.toARGB32() &&
                  _evenColor.toARGB32() == c2.toARGB32();

              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    AppHaptics.selection();
                    setState(() {
                      _oddColor = c1;
                      _evenColor = c2;
                      _oddActive = true;
                      _evenActive = true;
                    });
                    _applyAlternateSegments();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                    decoration: BoxDecoration(
                      color: isMatch ? AppTheme.amber.withValues(alpha: 0.18) : AppTheme.surfaceRaised,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isMatch ? AppTheme.amber : AppTheme.border,
                        width: isMatch ? 1.4 : 1.0,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(duo['icon'] as String, style: const TextStyle(fontSize: 12)),
                        const SizedBox(width: 5),
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [c1, c2],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            border: Border.all(color: Colors.white, width: 1),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          duo['title'] as String,
                          style: AppTheme.heading(
                            size: 10.5,
                            color: isMatch ? AppTheme.amber : AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildAlternateCard({
    required String title,
    required String subtitle,
    required Color color,
    required bool isActive,
    required ValueChanged<Color> onColorSelected,
    required VoidCallback onToggleActive,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? color.withValues(alpha: 0.6) : AppTheme.border,
          width: isActive ? 1.3 : 1.0,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive ? color : const Color(0xFF383228),
                      border: Border.all(color: Colors.white, width: 1.2),
                      boxShadow: isActive
                          ? [
                              BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6),
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    title,
                    style: AppTheme.heading(size: 10.5, color: AppTheme.textPrimary),
                  ),
                ],
              ),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  AppHaptics.selection();
                  onToggleActive();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: isActive ? AppTheme.amber.withValues(alpha: 0.15) : AppTheme.border.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isActive ? AppTheme.amber : AppTheme.border,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    isActive ? 'Lit' : 'Muted',
                    style: AppTheme.mono(size: 8.5, color: isActive ? AppTheme.amber : AppTheme.textMuted),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: _templePalette.map((p) {
              final col = p['color'] as Color;
              final isSel = isActive && color.toARGB32() == col.toARGB32();

              return InkWell(
                onTap: () {
                  AppHaptics.selection();
                  onColorSelected(col);
                },
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: col,
                    border: Border.all(
                      color: isSel ? Colors.white : AppTheme.border,
                      width: isSel ? 2.2 : 0.8,
                    ),
                    boxShadow: isSel
                        ? [
                            BoxShadow(color: col.withValues(alpha: 0.6), blurRadius: 4),
                          ]
                        : null,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildMotionChip(String label, int effectVal) {
    final isSelected = _oddEffect == effectVal && _evenEffect == effectVal;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        AppHaptics.selection();
        setState(() {
          _oddEffect = effectVal;
          _evenEffect = effectVal;
        });
        _applyAlternateSegments();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.amber.withValues(alpha: 0.2) : AppTheme.surfaceRaised,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppTheme.amber : AppTheme.border,
            width: isSelected ? 1.4 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: AppTheme.heading(
            size: 10,
            color: isSelected ? AppTheme.amber : AppTheme.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildZoneChipsTrack() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          ...widget.segments.asMap().entries.map((entry) {
            final idx = entry.key;
            final seg = entry.value;
            final isSelected = _selectedSegmentIndices.contains(idx);

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  AppHaptics.selection();
                  setState(() {
                    if (_multiSelectActive) {
                      if (isSelected) {
                        _selectedSegmentIndices.remove(idx);
                      } else {
                        _selectedSegmentIndices.add(idx);
                      }
                    } else {
                      _selectedSegmentIndices
                        ..clear()
                        ..add(idx);
                    }
                  });

                  if (!_multiSelectActive && widget.enableTapToConfigure && !widget.readOnly) {
                    _openConfigSheet();
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.amber.withValues(alpha: 0.22)
                        : AppTheme.surfaceRaised,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? AppTheme.amber : AppTheme.border,
                      width: isSelected ? 1.6 : 1.0,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: AppTheme.amber.withValues(alpha: 0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_multiSelectActive)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(
                            isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                            size: 13,
                            color: isSelected ? AppTheme.amber : AppTheme.textMuted,
                          ),
                        ),
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: seg.color,
                          boxShadow: [
                            BoxShadow(
                              color: seg.color.withValues(alpha: 0.5),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        seg.displayName,
                        style: AppTheme.heading(
                          size: 11,
                          color: isSelected ? AppTheme.amber : AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        seg.stride > 1
                            ? '(stride ${seg.stride})'
                            : '#${seg.start + 1}–#${seg.end + 1}',
                        style: AppTheme.mono(
                          size: 9.5,
                          color: isSelected ? AppTheme.amber.withValues(alpha: 0.8) : AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),

          // "+ Add Region" button chip
          if (!widget.readOnly && widget.segments.length < 16)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _addNewSegmentAuto,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppTheme.amber.withValues(alpha: 0.6),
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add_rounded, size: 14, color: AppTheme.amber),
                      const SizedBox(width: 4),
                      Text(
                        'Add Region',
                        style: AppTheme.heading(size: 10.5, color: AppTheme.amber),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
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
    this.selectedSegmentIndices = const {},
    this.highlightIndex,
    this.dragStartIndex,
    this.dragEndIndex,
    required this.animPhase,
  });

  final int totalLeds;
  final List<LedSegment> segments;
  final Set<int> selectedSegmentIndices;
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

    // Draw bounding boxes for all selected segments
    if (selectedSegmentIndices.isNotEmpty) {
      for (final selIdx in selectedSegmentIndices) {
        if (selIdx < segments.length) {
          final seg = segments[selIdx];
          final leftX = 12 + seg.start * step;
          final rightX = 12 + (seg.end + 1) * step;

          final segRect = Rect.fromLTRB(leftX, centerY - 18, rightX, centerY + 18);
          final segRRect = RRect.fromRectAndRadius(segRect, const Radius.circular(8));

          final selFill = Paint()..color = AppTheme.amber.withValues(alpha: 0.18);
          final selBorder = Paint()
            ..color = AppTheme.amber
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8;

          canvas.drawRRect(segRRect, selFill);
          canvas.drawRRect(segRRect, selBorder);
        }
      }
    }

    // Build LED color lookup and check if LED belongs to a selected segment
    final List<Color?> ledColors = List.filled(totalLeds, null);
    final List<int> ledEffects = List.filled(totalLeds, 0);
    final List<bool> ledIsSelected = List.filled(totalLeds, false);

    for (int sIdx = 0; sIdx < segments.length; sIdx++) {
      final seg = segments[sIdx];
      final isSel = selectedSegmentIndices.contains(sIdx);
      final sEnd = (seg.start + seg.count).clamp(0, totalLeds);
      for (int i = seg.start; i < sEnd; i++) {
        if (seg.stride > 1 && ((i - seg.start) % seg.stride) != seg.offset) {
          continue;
        }
        ledColors[i] = seg.color;
        ledEffects[i] = seg.effect;
        if (isSel) ledIsSelected[i] = true;
      }
    }

    // Draw LED pixels
    final ledRadius = (step * 0.45).clamp(2.5, 6.0);
    final hasSelection = selectedSegmentIndices.isNotEmpty;

    for (int i = 0; i < totalLeds; i++) {
      final cx = 12 + i * step + step * 0.5;
      final color = ledColors[i];

      if (color != null) {
        final fx = ledEffects[i];
        final isLedSel = ledIsSelected[i];
        double pulse = 1.0;

        if (fx == 1) { // Breathe
          pulse = 0.7 + 0.3 * (0.5 * (1.0 + math.sin(animPhase * 2 * math.pi)));
        } else if (fx == 2) { // Diya Flutter
          pulse = 0.8 + 0.2 * math.sin(animPhase * 18 + i);
        } else if (fx == 3) { // Starlight Twinkle / Sparkle
          pulse = 0.75 + 0.25 * math.sin(animPhase * 24 + i * 2.39);
        }

        final dimFactor = (hasSelection && !isLedSel) ? 0.45 : 1.0;
        final activeColor = color.withValues(alpha: (pulse * dimFactor).clamp(0.2, 1.0));

        // Radiant Aura Glow
        final glowPaint = Paint()
          ..color = activeColor.withValues(alpha: isLedSel ? 0.45 : (0.35 * dimFactor))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
        canvas.drawCircle(Offset(cx, centerY), ledRadius * 2.2, glowPaint);

        // Core LED body
        final ledPaint = Paint()..color = activeColor;
        canvas.drawCircle(Offset(cx, centerY), ledRadius, ledPaint);

        // Bright white center phosphor point
        final centerPointPaint = Paint()
          ..color = Colors.white.withValues(alpha: isLedSel ? 0.95 : (0.85 * dimFactor));
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
        oldDelegate.dragEndIndex != dragEndIndex ||
        oldDelegate.selectedSegmentIndices != selectedSegmentIndices;
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.totalLeds,
    required this.segments,
    this.selectedSegmentIndices = const {},
    this.highlightIndex,
    required this.animPhase,
  });

  final int totalLeds;
  final List<LedSegment> segments;
  final Set<int> selectedSegmentIndices;
  final int? highlightIndex;
  final double animPhase;

  @override
  void paint(Canvas canvas, Size size) {
    if (totalLeds <= 0) return;

    final center = Offset(size.width * 0.5, size.height * 0.5);
    final radius = math.min(size.width, size.height) * 0.41;

    // Outer subtle gold circular track
    final trackPaint = Paint()
      ..color = const Color(0xFF2C2720)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;
    canvas.drawCircle(center, radius, trackPaint);

    final trackGlowPaint = Paint()
      ..color = AppTheme.amber.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(center, radius, trackGlowPaint);

    // Build LED color lookup
    final List<Color?> ledColors = List.filled(totalLeds, null);
    final List<int> ledEffects = List.filled(totalLeds, 0);
    final List<bool> ledIsSelected = List.filled(totalLeds, false);

    for (int sIdx = 0; sIdx < segments.length; sIdx++) {
      final seg = segments[sIdx];
      final isSel = selectedSegmentIndices.contains(sIdx);
      final sEnd = (seg.start + seg.count).clamp(0, totalLeds);
      for (int i = seg.start; i < sEnd; i++) {
        if (seg.stride > 1 && ((i - seg.start) % seg.stride) != seg.offset) {
          continue;
        }
        ledColors[i] = seg.color;
        ledEffects[i] = seg.effect;
        if (isSel) ledIsSelected[i] = true;
      }
    }

    final hasSelection = selectedSegmentIndices.isNotEmpty;
    final stepAngle = (2 * math.pi) / totalLeds;
    final ledRadius = (2 * math.pi * radius / totalLeds * 0.40).clamp(2.5, 5.5);

    for (int i = 0; i < totalLeds; i++) {
      final angle = -math.pi * 0.5 + i * stepAngle;
      final cx = center.dx + radius * math.cos(angle);
      final cy = center.dy + radius * math.sin(angle);
      final color = ledColors[i];

      if (color != null) {
        final fx = ledEffects[i];
        final isLedSel = ledIsSelected[i];
        double pulse = 1.0;

        if (fx == 1) { // Breathe
          pulse = 0.7 + 0.3 * (0.5 * (1.0 + math.sin(animPhase * 2 * math.pi)));
        } else if (fx == 2) { // Diya Flutter
          pulse = 0.8 + 0.2 * math.sin(animPhase * 18 + i);
        } else if (fx == 3) { // Starlight Twinkle / Sparkle
          pulse = 0.75 + 0.25 * math.sin(animPhase * 24 + i * 2.39);
        }

        final dimFactor = (hasSelection && !isLedSel) ? 0.45 : 1.0;
        final activeColor = color.withValues(alpha: (pulse * dimFactor).clamp(0.2, 1.0));

        // Radiant Aura Glow
        final glowPaint = Paint()
          ..color = activeColor.withValues(alpha: isLedSel ? 0.5 : (0.35 * dimFactor))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
        canvas.drawCircle(Offset(cx, cy), ledRadius * 2.2, glowPaint);

        // Core LED body
        final ledPaint = Paint()..color = activeColor;
        canvas.drawCircle(Offset(cx, cy), ledRadius, ledPaint);

        // Bright white center phosphor point
        final centerPointPaint = Paint()
          ..color = Colors.white.withValues(alpha: isLedSel ? 0.95 : (0.85 * dimFactor));
        canvas.drawCircle(Offset(cx, cy), ledRadius * 0.35, centerPointPaint);
      } else {
        // Dark unlit LED
        final offPaint = Paint()..color = const Color(0xFF383228);
        canvas.drawCircle(Offset(cx, cy), ledRadius * 0.75, offPaint);
      }

      if (highlightIndex == i) {
        final ringPaint = Paint()
          ..color = AppTheme.amber
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        canvas.drawCircle(Offset(cx, cy), ledRadius * 2.8, ringPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.animPhase != animPhase ||
        oldDelegate.segments != segments ||
        oldDelegate.totalLeds != totalLeds ||
        oldDelegate.highlightIndex != highlightIndex ||
        oldDelegate.selectedSegmentIndices != selectedSegmentIndices;
  }
}
