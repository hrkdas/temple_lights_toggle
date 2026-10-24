import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/haptics.dart';
import '../theme.dart';

/// Converts a color temperature in Kelvin (2000K to 6500K) to RGB components.
/// Uses the Planckian blackbody locus approximation algorithm (Tanner Helland / Neil Bartlett).
({int r, int g, int b, Color color}) kelvinToRgbComponents(int kelvin) {
  final temp = (kelvin / 100.0).clamp(20.0, 65.0);

  // Red
  double r;
  if (temp <= 66) {
    r = 255.0;
  } else {
    r = temp - 60;
    r = 329.698727446 * math.pow(r, -0.1332047592);
  }

  // Green
  double g;
  if (temp <= 66) {
    g = temp;
    g = 99.4708025861 * math.log(g) - 161.1195681661;
  } else {
    g = temp - 60;
    g = 288.1221695283 * math.pow(g, -0.0755148492);
  }

  // Blue
  double b;
  if (temp >= 66) {
    b = 255.0;
  } else if (temp <= 19) {
    b = 0.0;
  } else {
    b = temp - 10;
    b = 138.5177312231 * math.log(b) - 305.0447927307;
  }

  final ir = r.round().clamp(0, 255);
  final ig = g.round().clamp(0, 255);
  final ib = b.round().clamp(0, 255);

  return (r: ir, g: ig, b: ib, color: Color.fromARGB(255, ir, ig, ib));
}

/// Convenience wrapper returning Color
Color kelvinToRgb(int kelvin) => kelvinToRgbComponents(kelvin).color;

/// Approximate closest Kelvin value given RGB components
int rgbToClosestKelvin(int r, int g, int b) {
  // Common Temple warmth anchors
  if (r == 255 && g < 160 && b < 70) return 2000;
  if (r == 255 && g < 190 && b < 140) return 2700;
  if (r >= 240 && g >= 210 && b > 180 && b < 240) return 4000;
  if (r >= 235 && g >= 235 && b >= 245) return 6500;

  // Binary search for nearest Euclidean distance in RGB space
  int bestK = 2700;
  double minDiff = double.infinity;
  for (int k = 2000; k <= 6500; k += 100) {
    final c = kelvinToRgbComponents(k);
    final dr = (c.r - r).toDouble();
    final dg = (c.g - g).toDouble();
    final db = (c.b - b).toDouble();
    final diff = dr * dr + dg * dg + db * db;
    if (diff < minDiff) {
      minDiff = diff;
      bestK = k;
    }
  }
  return bestK;
}

class KelvinPreset {
  const KelvinPreset({
    required this.kelvin,
    required this.name,
    required this.emoji,
    required this.description,
  });

  final int kelvin;
  final String name;
  final String emoji;
  final String description;
}

const List<KelvinPreset> kSacredKelvinPresets = [
  KelvinPreset(
    kelvin: 2000,
    name: 'Diya Amber',
    emoji: '🪔',
    description: 'Traditional ghee lamp glow',
  ),
  KelvinPreset(
    kelvin: 2700,
    name: 'Warm Temple',
    emoji: '🕯️',
    description: 'Cozy golden sanctum warmth',
  ),
  KelvinPreset(
    kelvin: 4000,
    name: 'Sacred Dawn',
    emoji: '🌅',
    description: 'Balanced morning aarti sunlight',
  ),
  KelvinPreset(
    kelvin: 6500,
    name: 'Pure Sanctum',
    emoji: '☀️',
    description: 'Crisp noon diamond radiance',
  ),
];

/// Elegant, tactile slider widget for selecting White Warmth (2000K to 6500K).
class KelvinWarmthSlider extends StatefulWidget {
  const KelvinWarmthSlider({
    super.key,
    required this.initialKelvin,
    required this.onChanged,
    this.onChangeEnd,
  });

  final int initialKelvin;
  final void Function(int kelvin, int r, int g, int b) onChanged;
  final void Function(int kelvin, int r, int g, int b)? onChangeEnd;

  @override
  State<KelvinWarmthSlider> createState() => _KelvinWarmthSliderState();
}

class _KelvinWarmthSliderState extends State<KelvinWarmthSlider> {
  late double _currentKelvin;

  @override
  void initState() {
    super.initState();
    _currentKelvin = widget.initialKelvin.clamp(2000, 6500).toDouble();
  }

  @override
  void didUpdateWidget(covariant KelvinWarmthSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialKelvin != widget.initialKelvin) {
      _currentKelvin = widget.initialKelvin.clamp(2000, 6500).toDouble();
    }
  }

  void _applyKelvin(int k, {bool isFinal = false}) {
    final clamped = k.clamp(2000, 6500);
    final comp = kelvinToRgbComponents(clamped);
    widget.onChanged(clamped, comp.r, comp.g, comp.b);
    if (isFinal && widget.onChangeEnd != null) {
      widget.onChangeEnd!(clamped, comp.r, comp.g, comp.b);
    }
  }

  String _getWarmthLabel(int k) {
    if (k < 2300) return 'Diya Amber (2000K–2300K)';
    if (k < 3200) return 'Warm White (2700K–3200K)';
    if (k < 5000) return 'Neutral Dawn (4000K–5000K)';
    return 'Daylight Sanctum (6000K–6500K)';
  }

  @override
  Widget build(BuildContext context) {
    final kInt = _currentKelvin.round();
    final currentColor = kelvinToRgb(kInt);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Title and Live Color Preview Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.wb_sunny_outlined, size: 16, color: AppTheme.amber),
                  const SizedBox(width: 8),
                  Text(
                    'SACRED WARMTH (KELVIN)',
                    style: AppTheme.heading(size: 11, color: AppTheme.textMuted, letterSpacing: 1.2),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: currentColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: currentColor, width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: currentColor.withValues(alpha: 0.25),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: currentColor,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${kInt}K',
                      style: AppTheme.mono(size: 11, color: currentColor, weight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _getWarmthLabel(kInt),
            style: AppTheme.body(size: 11, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),

          // Custom Kelvin Gradient Slider Track
          LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  // Gradient track background
                  Container(
                    height: 12,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFFF9329), // ~2000K Candlelight
                          Color(0xFFFFBA71), // ~2700K Warm
                          Color(0xFFFFDDB4), // ~4000K Neutral
                          Color(0xFFF4F6FF), // ~5500K Sunlight
                          Color(0xFFD6E2FF), // ~6500K Pure White / Daylight
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: currentColor.withValues(alpha: 0.2),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                  SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: Colors.transparent,
                      inactiveTrackColor: Colors.transparent,
                      thumbColor: Colors.white,
                      overlayColor: currentColor.withValues(alpha: 0.3),
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 11,
                        elevation: 3,
                        pressedElevation: 6,
                      ),
                      trackHeight: 12,
                    ),
                    child: Slider(
                      value: _currentKelvin,
                      min: 2000,
                      max: 6500,
                      divisions: 45,
                      onChanged: (val) {
                        setState(() {
                          _currentKelvin = val;
                        });
                        _applyKelvin(val.round(), isFinal: false);
                      },
                      onChangeEnd: (val) {
                        AppHaptics.selection();
                        _applyKelvin(val.round(), isFinal: true);
                      },
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),

          // Quick Preset Chips (Diya, Warm, Neutral, Pure)
          Row(
            children: kSacredKelvinPresets.map((preset) {
              final isCurrent = (kInt - preset.kelvin).abs() < 150;
              final pColor = kelvinToRgb(preset.kelvin);

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      AppHaptics.selection();
                      setState(() {
                        _currentKelvin = preset.kelvin.toDouble();
                      });
                      _applyKelvin(preset.kelvin, isFinal: true);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                      decoration: BoxDecoration(
                        color: isCurrent ? pColor.withValues(alpha: 0.2) : AppTheme.surfaceRaised,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isCurrent ? pColor : AppTheme.border,
                          width: isCurrent ? 1.6 : 1.0,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(preset.emoji, style: const TextStyle(fontSize: 13)),
                          const SizedBox(height: 2),
                          Text(
                            preset.name,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.heading(
                              size: 9.5,
                              color: isCurrent ? pColor : AppTheme.textSecondary,
                            ),
                          ),
                          Text(
                            '${preset.kelvin}K',
                            style: AppTheme.mono(
                              size: 8.5,
                              color: isCurrent ? pColor : AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
