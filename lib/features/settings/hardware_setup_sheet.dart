import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/haptics.dart';
import '../../domain/models.dart';
import '../../domain/providers.dart';
import '../../ui/theme.dart';

/// Modal bottom sheet to calibrate physical LED count, strip length, power budget, and color order.
class HardwareSetupSheet extends ConsumerStatefulWidget {
  const HardwareSetupSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => const HardwareSetupSheet(),
    );
  }

  @override
  ConsumerState<HardwareSetupSheet> createState() => _HardwareSetupSheetState();
}

class _HardwareSetupSheetState extends ConsumerState<HardwareSetupSheet> {
  late int _ledCount;
  late int _maxCurrentMa;
  late int _colorOrder;
  late final TextEditingController _customCountController;
  bool _isCustomCount = false;
  bool _testingAlignment = false;

  final List<int> _presetLedCounts = [60, 120, 150, 180, 300];
  final List<int> _presetCurrentBudgets = [1500, 2000, 3000, 5000, 8000];

  @override
  void initState() {
    super.initState();
    final light = ref.read(lightControlProvider);
    _ledCount = light.ledCount;
    _maxCurrentMa = light.maxCurrentMa;
    _colorOrder = light.colorOrder;
    _isCustomCount = !_presetLedCounts.contains(_ledCount);
    _customCountController = TextEditingController(text: _ledCount.toString());
  }

  @override
  void dispose() {
    _customCountController.dispose();
    super.dispose();
  }

  String _formatMeters(int count) {
    final m = count / 60.0;
    return '${m.toStringAsFixed(1)}m';
  }

  Future<void> _triggerTest() async {
    setState(() => _testingAlignment = true);
    await ref.read(lightControlProvider.notifier).triggerHwTest();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppTheme.surfaceRaised,
          content: Text(
            'Test Pattern Active: Start (Red) • Center (Green) • End (Blue)',
            style: TextStyle(color: AppTheme.gold, fontSize: 13),
          ),
          duration: Duration(seconds: 4),
        ),
      );
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) setState(() => _testingAlignment = false);
      });
    }
  }

  Future<void> _save() async {
    int finalCount = _ledCount;
    if (_isCustomCount) {
      final parsed = int.tryParse(_customCountController.text.trim());
      if (parsed != null && parsed >= 10 && parsed <= 600) {
        finalCount = parsed;
      }
    }

    await ref.read(lightControlProvider.notifier).setHardwareConfig(
          leds: finalCount,
          maxCurrentMa: _maxCurrentMa,
          colorOrder: _colorOrder,
        );

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.surfaceRaised,
          content: Text(
            'Hardware configured: $finalCount LEDs (${_formatMeters(finalCount)}) • Max ${_maxCurrentMa}mA • Color: ${LightState.colorOrderNames[_colorOrder.clamp(0, 3)]}',
            style: const TextStyle(color: AppTheme.green, fontSize: 13),
          ),
        ),
      );
    }
  }

  Widget _buildColorTestButton({
    required String name,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        AppHaptics.selection();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [
                  BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 4),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Text(name, style: AppTheme.heading(size: 11, color: AppTheme.textPrimary)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeDev = ref.watch(activeDeviceProvider);
    final targetName = activeDev?.displayName ?? 'Active Light';

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.88,
        minChildSize: 0.50,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: ListView(
              controller: scrollController,
              children: [
                // Grab handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.borderBright,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('LED Strip & Power Setup', style: AppTheme.heading(size: 19)),
                        const SizedBox(height: 2),
                        Text(
                          'Calibrate hardware for $targetName',
                          style: AppTheme.body(size: 12, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Strip Length / LED Count Section
                Text('Physical Strip Length & LED Count', style: AppTheme.heading(size: 14, color: AppTheme.amber)),
                const SizedBox(height: 6),
                Text(
                  'Select the physical number of LEDs on your shrine strip (assumes 60 LEDs/meter density):',
                  style: AppTheme.body(size: 12, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 12),

                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final count in _presetLedCounts)
                      ChoiceChip(
                        label: Text(
                          '$count LEDs (${_formatMeters(count)})',
                          style: AppTheme.heading(
                            size: 12,
                            color: (!_isCustomCount && _ledCount == count) ? Colors.black : AppTheme.textPrimary,
                          ),
                        ),
                        selected: !_isCustomCount && _ledCount == count,
                        selectedColor: AppTheme.amber,
                        backgroundColor: AppTheme.surfaceRaised,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        onSelected: (selected) {
                          if (selected) {
                            setState(() {
                              _isCustomCount = false;
                              _ledCount = count;
                            });
                          }
                        },
                      ),
                    ChoiceChip(
                      label: Text(
                        'Custom Count',
                        style: AppTheme.heading(
                          size: 12,
                          color: _isCustomCount ? Colors.black : AppTheme.textPrimary,
                        ),
                      ),
                      selected: _isCustomCount,
                      selectedColor: AppTheme.amber,
                      backgroundColor: AppTheme.surfaceRaised,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      onSelected: (selected) {
                        setState(() => _isCustomCount = selected);
                      },
                    ),
                  ],
                ),

                if (_isCustomCount) ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: _customCountController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 14, color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Custom LED Count (10 - 600 LEDs)',
                      labelStyle: AppTheme.body(size: 12, color: AppTheme.textMuted),
                      hintText: 'e.g. 240',
                      filled: true,
                      fillColor: AppTheme.surfaceRaised,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.amber, width: 2),
                      ),
                    ),
                    onChanged: (val) {
                      final parsed = int.tryParse(val.trim());
                      if (parsed != null && parsed >= 10 && parsed <= 600) {
                        setState(() => _ledCount = parsed);
                      }
                    },
                  ),
                ],

                const SizedBox(height: 24),

                // Power Budget / Current Limiter Section
                Row(
                  children: [
                    Text('Power Safety Budget (Software Fuse)', style: AppTheme.heading(size: 14, color: AppTheme.cyan)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.cyan.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$_maxCurrentMa mA',
                        style: AppTheme.mono(size: 11, color: AppTheme.cyan),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Dynamically dims full white output if total power exceeds your 5V adapter rating, eliminating brownouts and crashes:',
                  style: AppTheme.body(size: 12, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 12),

                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final ma in _presetCurrentBudgets)
                      ChoiceChip(
                        label: Text(
                          '${ma / 1000}A ($ma mA)',
                          style: AppTheme.heading(
                            size: 12,
                            color: _maxCurrentMa == ma ? Colors.black : AppTheme.textPrimary,
                          ),
                        ),
                        selected: _maxCurrentMa == ma,
                        selectedColor: AppTheme.cyan,
                        backgroundColor: AppTheme.surfaceRaised,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _maxCurrentMa = ma);
                          }
                        },
                      ),
                  ],
                ),

                const SizedBox(height: 24),

                // LED Strip Color Calibration Section
                Row(
                  children: [
                    const Icon(Icons.color_lens_rounded, size: 18, color: AppTheme.gold),
                    const SizedBox(width: 8),
                    Text('LED Strip Color Calibration', style: AppTheme.heading(size: 14, color: AppTheme.gold)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Aligns the physical wire color sequence to match your LED strip IC. Fixes green tint on warm white (choose RGB for WS2811/12V or GRB for WS2812B):',
                  style: AppTheme.body(size: 12, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 12),

                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (int i = 0; i < LightState.colorOrderNames.length; i++)
                      ChoiceChip(
                        label: Text(
                          LightState.colorOrderNames[i],
                          style: AppTheme.heading(
                            size: 11.5,
                            color: _colorOrder == i ? Colors.black : AppTheme.textPrimary,
                          ),
                        ),
                        selected: _colorOrder == i,
                        selectedColor: AppTheme.gold,
                        backgroundColor: AppTheme.surfaceRaised,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        onSelected: (selected) {
                          if (selected) {
                            setState(() => _colorOrder = i);
                            ref.read(lightControlProvider.notifier).setColorOrder(i);
                          }
                        },
                      ),
                  ],
                ),

                const SizedBox(height: 14),

                // Live Color Verification Chips
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
                      Text(
                        'QUICK COLOR VERIFICATION (TAP TO TEST STRIP)',
                        style: AppTheme.heading(size: 10.5, color: AppTheme.textMuted, letterSpacing: 1.0),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildColorTestButton(
                            name: 'Red',
                            color: const Color(0xFFFF2222),
                            onTap: () => ref.read(lightControlProvider.notifier).setLiveRgb(255, 0, 0),
                          ),
                          _buildColorTestButton(
                            name: 'Green',
                            color: const Color(0xFF00E676),
                            onTap: () => ref.read(lightControlProvider.notifier).setLiveRgb(0, 255, 0),
                          ),
                          _buildColorTestButton(
                            name: 'Blue',
                            color: const Color(0xFF2979FF),
                            onTap: () => ref.read(lightControlProvider.notifier).setLiveRgb(0, 0, 255),
                          ),
                          _buildColorTestButton(
                            name: 'Warm Amber',
                            color: const Color(0xFFFF9329),
                            onTap: () => ref.read(lightControlProvider.notifier).setLiveRgb(255, 147, 41),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Strip Alignment Diagnostic Test Button
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceRaised,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.flash_on_rounded, size: 20, color: AppTheme.amber),
                          const SizedBox(width: 10),
                          Text('Strip Alignment Test', style: AppTheme.heading(size: 14)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Flashes start in Red, center in Green, and end in Blue to confirm physical orientation:',
                        style: AppTheme.body(size: 12, color: AppTheme.textMuted),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: _testingAlignment
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.amber))
                              : const Icon(Icons.flash_on_rounded, size: 16, color: AppTheme.amber),
                          label: Text(
                            _testingAlignment ? 'Displaying Test Pattern...' : 'Run 3.5s Alignment Test',
                            style: AppTheme.heading(size: 12.5, color: AppTheme.amber),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppTheme.amber),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _testingAlignment ? null : _triggerTest,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Save Configuration Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle_rounded, size: 18, color: Colors.white),
                    label: Text('Save Hardware Calibration', style: AppTheme.heading(size: 14, color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.amber,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                    ),
                    onPressed: _save,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
