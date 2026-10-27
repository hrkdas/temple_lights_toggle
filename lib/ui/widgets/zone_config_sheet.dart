import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/haptics.dart';
import '../../domain/models.dart';
import '../theme.dart';
import 'kelvin_warmth_slider.dart';

/// Modal bottom sheet for configuring one or multiple selected LED strip regions.
/// Supports batch synchronized color, Kelvin warmth, brightness, effects, and boundary tuning.
class ZoneConfigSheet extends StatefulWidget {
  const ZoneConfigSheet({
    super.key,
    required this.segments,
    required this.selectedIndices,
    required this.totalLeds,
    required this.onSegmentsUpdated,
    this.onSelectionCleared,
    this.onDeleteSelected,
  });

  final List<LedSegment> segments;
  final Set<int> selectedIndices;
  final int totalLeds;
  final ValueChanged<List<LedSegment>> onSegmentsUpdated;
  final VoidCallback? onSelectionCleared;
  final VoidCallback? onDeleteSelected;

  static Future<void> show({
    required BuildContext context,
    required List<LedSegment> segments,
    required Set<int> selectedIndices,
    required int totalLeds,
    required ValueChanged<List<LedSegment>> onSegmentsUpdated,
    VoidCallback? onSelectionCleared,
    VoidCallback? onDeleteSelected,
  }) {
    if (selectedIndices.isEmpty) return Future.value();

    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      builder: (ctx) => ZoneConfigSheet(
        segments: segments,
        selectedIndices: selectedIndices,
        totalLeds: totalLeds,
        onSegmentsUpdated: onSegmentsUpdated,
        onSelectionCleared: onSelectionCleared,
        onDeleteSelected: onDeleteSelected,
      ),
    );
  }

  @override
  State<ZoneConfigSheet> createState() => _ZoneConfigSheetState();
}

class _ZoneConfigSheetState extends State<ZoneConfigSheet> with SingleTickerProviderStateMixin {
  late List<LedSegment> _currentSegments;
  late int _r;
  late int _g;
  late int _b;
  late int _brightness;
  late int _effect;
  late int _speed;
  late TextEditingController _nameController;
  late final TabController _colorTabController;

  static const List<Map<String, dynamic>> _sacredPalettes = [
    {'name': 'Warm Amber', 'r': 255, 'g': 147, 'b': 41, 'color': Color(0xFFFF9329)},
    {'name': 'Saffron Gold', 'r': 255, 'g': 180, 'b': 0, 'color': Color(0xFFFFB400)},
    {'name': 'Temple Red', 'r': 255, 'g': 30, 'b': 30, 'color': Color(0xFFFF1E1E)},
    {'name': 'Sacred Blue', 'r': 0, 'g': 120, 'b': 255, 'color': Color(0xFF0078FF)},
    {'name': 'Divine Cyan', 'r': 0, 'g': 229, 'b': 255, 'color': Color(0xFF00E5FF)},
    {'name': 'Lotus Pink', 'r': 255, 'g': 80, 'b': 160, 'color': Color(0xFFFF50A0)},
    {'name': 'Holy Green', 'r': 0, 'g': 230, 'b': 118, 'color': Color(0xFF00E676)},
    {'name': 'Pure White', 'r': 255, 'g': 255, 'b': 255, 'color': Color(0xFFFFFFFF)},
  ];

  static const List<String> _effects = [
    'Pure Solid',
    'Gentle Breathe',
    'Diya Candle Flutter',
    'Starlight Twinkle',
    'Sacred Amber Embers',
    'Aurora Flow',
    'Rainbow Cycle',
  ];

  @override
  void initState() {
    super.initState();
    _currentSegments = List<LedSegment>.from(widget.segments);
    _colorTabController = TabController(length: 3, vsync: this);

    final firstIndex = widget.selectedIndices.first;
    final primarySeg = firstIndex < _currentSegments.length
        ? _currentSegments[firstIndex]
        : const LedSegment(start: 0, count: 1);

    _r = primarySeg.r;
    _g = primarySeg.g;
    _b = primarySeg.b;
    _brightness = primarySeg.brightness;
    _effect = primarySeg.effect.clamp(0, _effects.length - 1);
    _speed = primarySeg.speed;
    _nameController = TextEditingController(
      text: widget.selectedIndices.length == 1 ? (primarySeg.name ?? '') : '',
    );
  }

  @override
  void dispose() {
    _colorTabController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  int get _totalSelectedLeds {
    int sum = 0;
    for (final idx in widget.selectedIndices) {
      if (idx < _currentSegments.length) {
        sum += _currentSegments[idx].count;
      }
    }
    return sum;
  }

  void _applyBatchMutation({
    int? r,
    int? g,
    int? b,
    int? brightness,
    int? effect,
    int? speed,
    String? name,
  }) {
    if (r != null) _r = r;
    if (g != null) _g = g;
    if (b != null) _b = b;
    if (brightness != null) _brightness = brightness;
    if (effect != null) _effect = effect;
    if (speed != null) _speed = speed;

    final updated = List<LedSegment>.from(_currentSegments);
    for (final idx in widget.selectedIndices) {
      if (idx < updated.length) {
        final existing = updated[idx];
        updated[idx] = existing.copyWith(
          r: r ?? existing.r,
          g: g ?? existing.g,
          b: b ?? existing.b,
          brightness: brightness ?? existing.brightness,
          effect: effect ?? existing.effect,
          speed: speed ?? existing.speed,
          name: (widget.selectedIndices.length == 1 && name != null)
              ? (name.trim().isEmpty ? null : name.trim())
              : existing.name,
        );
      }
    }

    setState(() {
      _currentSegments = updated;
    });

    widget.onSegmentsUpdated(updated);
  }

  void _nudgeBoundary({required int index, int? deltaStart, int? deltaCount}) {
    if (index >= _currentSegments.length) return;
    final seg = _currentSegments[index];
    int newStart = seg.start;
    int newCount = seg.count;

    if (deltaStart != null) {
      newStart = (seg.start + deltaStart).clamp(0, widget.totalLeds - 1);
      // Ensure segment doesn't overflow strip end
      if (newStart + newCount > widget.totalLeds) {
        newCount = widget.totalLeds - newStart;
      }
    }

    if (deltaCount != null) {
      newCount = (seg.count + deltaCount).clamp(1, widget.totalLeds - newStart);
    }

    final updated = List<LedSegment>.from(_currentSegments);
    updated[index] = seg.copyWith(start: newStart, count: newCount);

    AppHaptics.selection();
    setState(() {
      _currentSegments = updated;
    });
    widget.onSegmentsUpdated(updated);
  }

  void _deleteCurrentSelected() {
    if (widget.onDeleteSelected != null) {
      widget.onDeleteSelected!();
      Navigator.of(context).pop();
      return;
    }

    // Default deletion logic
    final remaining = <LedSegment>[];
    for (int i = 0; i < _currentSegments.length; i++) {
      if (!widget.selectedIndices.contains(i)) {
        remaining.add(_currentSegments[i]);
      }
    }

    if (remaining.isEmpty) {
      // Revert to default full strip if all segments were deleted
      remaining.add(LedSegment(
        start: 0,
        count: widget.totalLeds,
        r: _r,
        g: _g,
        b: _b,
        name: 'Full Strip',
      ));
    }

    AppHaptics.medium();
    widget.onSegmentsUpdated(remaining);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isMulti = widget.selectedIndices.length > 1;
    final singleIndex = widget.selectedIndices.first;
    final singleSeg = singleIndex < _currentSegments.length ? _currentSegments[singleIndex] : null;

    final currentColor = Color.fromARGB(255, _r, _g, _b);
    final brightnessPct = ((_brightness / 255.0) * 100).round();

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.88,
          ),
          decoration: BoxDecoration(
            color: AppTheme.surface.withValues(alpha: 0.96),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: AppTheme.border),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF3B2E1E).withValues(alpha: 0.12),
                blurRadius: 28,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Grab Handle
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4.5,
                decoration: BoxDecoration(
                  color: AppTheme.borderBright,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 10),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    // Color Preview Avatar
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: currentColor,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: currentColor.withValues(alpha: 0.5),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Title & Scope
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isMulti
                                ? '${widget.selectedIndices.length} Regions Selected'
                                : (singleSeg?.displayName ?? 'Configure Region'),
                            style: AppTheme.heading(size: 16),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isMulti
                                ? '$_totalSelectedLeds LEDs total • Synchronized batch control'
                                : 'LEDs #${(singleSeg?.start ?? 0) + 1}–#{(singleSeg?.end ?? 0) + 1} (${singleSeg?.count ?? 0} LEDs)',
                            style: AppTheme.body(size: 12, color: AppTheme.amber),
                          ),
                        ],
                      ),
                    ),

                    // Actions in Header
                    if (widget.onSelectionCleared != null && isMulti)
                      TextButton(
                        onPressed: () {
                          widget.onSelectionCleared!();
                          Navigator.of(context).pop();
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: Text(
                          'Deselect',
                          style: AppTheme.body(size: 12, color: AppTheme.textMuted),
                        ),
                      ),

                    if (_currentSegments.length > 1)
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppTheme.red),
                        tooltip: 'Delete Region',
                        onPressed: _deleteCurrentSelected,
                      ),

                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 22, color: AppTheme.textMuted),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              const Divider(color: AppTheme.border, height: 16),

              // Scrollable Controls Body
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Zone Label Name Field (Single Selection)
                      if (!isMulti && singleSeg != null) ...[
                        Row(
                          children: [
                            const Icon(Icons.label_outline_rounded, size: 14, color: AppTheme.amber),
                            const SizedBox(width: 6),
                            Text(
                              'REGION NAME',
                              style: AppTheme.heading(size: 11, color: AppTheme.textMuted, letterSpacing: 1.1),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _nameController,
                          style: AppTheme.body(size: 13),
                          decoration: InputDecoration(
                            hintText: 'e.g. Left Sanctum, Center Altar, Spire',
                            hintStyle: AppTheme.body(size: 13, color: AppTheme.textMuted),
                            filled: true,
                            fillColor: AppTheme.surfaceRaised,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: AppTheme.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: AppTheme.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: AppTheme.amber),
                            ),
                          ),
                          onChanged: (text) => _applyBatchMutation(name: text),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Color Mode Tabs
                      Container(
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceRaised,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: TabBar(
                          controller: _colorTabController,
                          indicator: BoxDecoration(
                            color: AppTheme.amber.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.amber, width: 1.2),
                          ),
                          labelColor: AppTheme.amber,
                          unselectedLabelColor: AppTheme.textMuted,
                          labelStyle: AppTheme.heading(size: 11),
                          tabs: const [
                            Tab(text: 'Palettes'),
                            Tab(text: 'Warmth'),
                            Tab(text: 'Custom RGB'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Color Tab Views
                      SizedBox(
                        height: 150,
                        child: TabBarView(
                          controller: _colorTabController,
                          children: [
                            // 1. Temple Palettes
                            _buildPalettesGrid(),

                            // 2. Kelvin Warmth Slider
                            SingleChildScrollView(
                              child: KelvinWarmthSlider(
                                initialKelvin: rgbToClosestKelvin(_r, _g, _b),
                                onChanged: (k, r, g, b) {
                                  _applyBatchMutation(r: r, g: g, b: b);
                                },
                                onChangeEnd: (k, r, g, b) {
                                  _applyBatchMutation(r: r, g: g, b: b);
                                },
                              ),
                            ),

                            // 3. Custom RGB Sliders
                            SingleChildScrollView(
                              child: Column(
                                children: [
                                  _buildRgbSlider('Red', _r, Colors.red, (val) => _applyBatchMutation(r: val)),
                                  const SizedBox(height: 6),
                                  _buildRgbSlider('Green', _g, Colors.green, (val) => _applyBatchMutation(g: val)),
                                  const SizedBox(height: 6),
                                  _buildRgbSlider('Blue', _b, Colors.blue, (val) => _applyBatchMutation(b: val)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Synchronized Brightness Scrubber
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceRaised,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      const Icon(Icons.brightness_6_rounded, size: 14, color: AppTheme.amber),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'SYNCHRONIZED BRIGHTNESS',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTheme.heading(size: 10.5, color: AppTheme.textMuted, letterSpacing: 1.0),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '$brightnessPct%',
                                  style: AppTheme.heading(size: 13, color: AppTheme.amber),
                                ),
                              ],
                            ),
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                activeTrackColor: AppTheme.amber,
                                inactiveTrackColor: AppTheme.surface,
                                thumbColor: AppTheme.amber,
                                trackHeight: 4,
                              ),
                              child: Slider(
                                value: _brightness.toDouble().clamp(3.0, 255.0),
                                min: 3,
                                max: 255,
                                onChanged: (val) {
                                  _applyBatchMutation(brightness: val.round());
                                },
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Animation Effect Selector
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceRaised,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      const Icon(Icons.auto_awesome_rounded, size: 14, color: AppTheme.amber),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'SACRED EFFECT',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTheme.heading(size: 10.5, color: AppTheme.textMuted, letterSpacing: 1.0),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _effects[_effect],
                                  style: AppTheme.heading(size: 11.5, color: AppTheme.amber),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonHideUnderline(
                              child: DropdownButton<int>(
                                isExpanded: true,
                                value: _effect,
                                dropdownColor: AppTheme.surface,
                                items: _effects.asMap().entries.map((e) {
                                  return DropdownMenuItem<int>(
                                    value: e.key,
                                    child: Text(e.value, style: AppTheme.body(size: 12)),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    AppHaptics.selection();
                                    _applyBatchMutation(effect: val);
                                  }
                                },
                              ),
                            ),
                            if (_effect > 0) ...[
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Speed', style: AppTheme.body(size: 11, color: AppTheme.textSecondary)),
                                  Text('$_speed / 10', style: AppTheme.heading(size: 11, color: AppTheme.amber)),
                                ],
                              ),
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  activeTrackColor: AppTheme.amber,
                                  inactiveTrackColor: AppTheme.surface,
                                  thumbColor: AppTheme.amber,
                                  trackHeight: 3,
                                ),
                                child: Slider(
                                  value: _speed.toDouble().clamp(1.0, 10.0),
                                  min: 1,
                                  max: 10,
                                  divisions: 9,
                                  onChanged: (val) {
                                    _applyBatchMutation(speed: val.round());
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      // Boundary Fine-Tuning Steppers (Single Region)
                      if (!isMulti && singleSeg != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceRaised,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.tune_rounded, size: 14, color: AppTheme.amber),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      'PRECISE LED BOUNDARIES',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTheme.heading(size: 10.5, color: AppTheme.textMuted, letterSpacing: 1.0),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildBoundaryStepper(
                                      label: 'Start LED',
                                      value: '#${singleSeg.start + 1}',
                                      onDecrement: () => _nudgeBoundary(index: singleIndex, deltaStart: -1),
                                      onIncrement: () => _nudgeBoundary(index: singleIndex, deltaStart: 1),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildBoundaryStepper(
                                      label: 'End LED',
                                      value: '#${singleSeg.end + 1}',
                                      onDecrement: () => _nudgeBoundary(index: singleIndex, deltaCount: -1),
                                      onIncrement: () => _nudgeBoundary(index: singleIndex, deltaCount: 1),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // Done Button
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.amber,
                          foregroundColor: Colors.black,
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 2,
                        ),
                        onPressed: () {
                          AppHaptics.selection();
                          Navigator.of(context).pop();
                        },
                        child: Text(
                          isMulti ? 'Done (Apply to ${widget.selectedIndices.length} Regions)' : 'Done',
                          style: AppTheme.heading(size: 13, color: Colors.black),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPalettesGrid() {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _sacredPalettes.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.2,
      ),
      itemBuilder: (ctx, idx) {
        final p = _sacredPalettes[idx];
        final pr = p['r'] as int;
        final pg = p['g'] as int;
        final pb = p['b'] as int;
        final color = p['color'] as Color;
        final isSelected = _r == pr && _g == pg && _b == pb;

        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            AppHaptics.selection();
            _applyBatchMutation(r: pr, g: pg, b: pb);
          },
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.surfaceRaised,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? Colors.white : AppTheme.border,
                width: isSelected ? 2.0 : 1.0,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.4),
                        blurRadius: 6,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    p['name'] as String,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.body(
                      size: 9.5,
                      color: isSelected ? Colors.white : AppTheme.textSecondary,
                      weight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRgbSlider(String label, int val, Color trackColor, ValueChanged<int> onChanged) {
    return Row(
      children: [
        SizedBox(
          width: 44,
          child: Text(label, style: AppTheme.body(size: 11, color: AppTheme.textSecondary)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: trackColor,
              inactiveTrackColor: AppTheme.surfaceRaised,
              thumbColor: trackColor,
              trackHeight: 3.5,
            ),
            child: Slider(
              value: val.toDouble().clamp(0.0, 255.0),
              min: 0,
              max: 255,
              onChanged: (v) {
                onChanged(v.round());
              },
            ),
          ),
        ),
        SizedBox(
          width: 30,
          child: Text(
            '$val',
            textAlign: TextAlign.end,
            style: AppTheme.mono(size: 11, color: AppTheme.textPrimary),
          ),
        ),
      ],
    );
  }

  Widget _buildBoundaryStepper({
    required String label,
    required String value,
    required VoidCallback onDecrement,
    required VoidCallback onIncrement,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.body(size: 10, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onDecrement,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.remove_circle_outline_rounded, size: 18, color: AppTheme.amber),
                ),
              ),
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.heading(size: 11.5, color: AppTheme.amber),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onIncrement,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.add_circle_outline_rounded, size: 18, color: AppTheme.amber),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
