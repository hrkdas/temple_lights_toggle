import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/haptics.dart';
import '../../../domain/models.dart';
import '../../../domain/providers.dart';
import '../../../ui/theme.dart';

/// Interactive hardware calibration panel displaying physical strip range,
/// LED count text field, power budget (mA), and color channel order.
class LedRangeCalibrationCard extends ConsumerStatefulWidget {
  const LedRangeCalibrationCard({
    super.key,
    required this.device,
    required this.isConnected,
    this.onSaved,
  });

  final PairedDevice device;
  final bool isConnected;
  final VoidCallback? onSaved;

  @override
  ConsumerState<LedRangeCalibrationCard> createState() => _LedRangeCalibrationCardState();
}

class _LedRangeCalibrationCardState extends ConsumerState<LedRangeCalibrationCard> {
  late int _ledCount;
  late int _maxCurrentMa;
  late int _colorOrder;
  late final TextEditingController _countController;
  late final TextEditingController _currentController;
  String? _countError;
  bool _isSaving = false;

  final List<int> _ledPresets = const [60, 105, 120, 150, 180, 300];
  final List<int> _currentPresets = const [1500, 2000, 3000, 5000];

  @override
  void initState() {
    super.initState();
    _ledCount = widget.device.effectiveLedCount;
    _maxCurrentMa = widget.device.effectiveMaxCurrentMa;
    _colorOrder = widget.device.effectiveColorOrder;
    _countController = TextEditingController(text: _ledCount.toString());
    _currentController = TextEditingController(text: _maxCurrentMa.toString());
  }

  @override
  void didUpdateWidget(covariant LedRangeCalibrationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.device.id != oldWidget.device.id) {
      _ledCount = widget.device.effectiveLedCount;
      _maxCurrentMa = widget.device.effectiveMaxCurrentMa;
      _colorOrder = widget.device.effectiveColorOrder;
      _countController.text = _ledCount.toString();
      _currentController.text = _maxCurrentMa.toString();
    }
  }

  @override
  void dispose() {
    _countController.dispose();
    _currentController.dispose();
    super.dispose();
  }

  double get _stripLengthMeters => _ledCount / 60.0;
  double get _wattageRating => (5.0 * _maxCurrentMa) / 1000.0;

  void _updateCount(int count) {
    final clamped = count.clamp(10, 600);
    setState(() {
      _ledCount = clamped;
      _countController.text = clamped.toString();
      _countError = null;
    });
  }

  Future<void> _saveCalibration() async {
    final parsedCount = int.tryParse(_countController.text.trim());
    if (parsedCount == null || parsedCount < 10 || parsedCount > 600) {
      setState(() => _countError = 'Enter a valid count between 10 and 600 LEDs');
      return;
    }

    final parsedCurrent = int.tryParse(_currentController.text.trim()) ?? _maxCurrentMa;

    setState(() {
      _isSaving = true;
      _countError = null;
    });

    try {
      AppHaptics.medium();

      // 1. Update local PairedDevices store
      await ref.read(pairedDevicesProvider.notifier).updateHardwareConfig(
            id: widget.device.id,
            ledCount: parsedCount,
            maxCurrentMa: parsedCurrent,
            colorOrder: _colorOrder,
          );

      // 2. If actively connected to this peripheral, dispatch directly to ESP32 NVS
      final conn = ref.read(lightSessionProvider);
      if (conn.isConnected && conn.deviceId == widget.device.id) {
        await ref.read(lightControlProvider.notifier).setHardwareConfig(
              leds: parsedCount,
              maxCurrentMa: parsedCurrent,
              colorOrder: _colorOrder,
            );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.green,
            content: Text(
              'Calibrated: $parsedCount LEDs (${_stripLengthMeters.toStringAsFixed(1)}m) • ${parsedCurrent}mA Max',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
        widget.onSaved?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _countError = 'Failed to save: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.cyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.tune_rounded,
                  size: 18,
                  color: AppTheme.cyan,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LED RANGE & HARDWARE CALIBRATION',
                      style: AppTheme.heading(
                        size: 12,
                        color: AppTheme.textMuted,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Physical strip metrology and power limits',
                      style: AppTheme.body(size: 11, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              // Strip length indicator badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Text(
                  '${_stripLengthMeters.toStringAsFixed(1)}m length',
                  style: AppTheme.heading(size: 11, color: AppTheme.cyan),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Visual Strip Range Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.linear_scale_rounded, size: 16, color: AppTheme.amber),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Range: LED #1 (0.0m) ➔ LED #$_ledCount (${_stripLengthMeters.toStringAsFixed(2)}m)',
                          style: AppTheme.mono(size: 11.5, color: AppTheme.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '60 LED/m',
                  style: AppTheme.body(size: 10.5, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // LED Count Text Field & Steppers
          Text('TOTAL PHYSICAL LEDS', style: AppTheme.heading(size: 10.5, color: AppTheme.textMuted, letterSpacing: 1.0)),
          const SizedBox(height: 6),
          Row(
            children: [
              IconButton.filledTonal(
                icon: const Icon(Icons.remove_rounded, size: 18),
                onPressed: () => _updateCount(_ledCount - 5),
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.all(8),
                  minimumSize: const Size(36, 36),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _countController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: AppTheme.mono(size: 15, color: AppTheme.textPrimary),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    errorText: _countError,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.cyan, width: 1.6),
                    ),
                    suffixText: 'LEDs',
                    suffixStyle: AppTheme.body(size: 11, color: AppTheme.textMuted),
                  ),
                  onChanged: (val) {
                    final parsed = int.tryParse(val);
                    if (parsed != null && parsed >= 10 && parsed <= 600) {
                      setState(() {
                        _ledCount = parsed;
                        _countError = null;
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                icon: const Icon(Icons.add_rounded, size: 18),
                onPressed: () => _updateCount(_ledCount + 5),
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.all(8),
                  minimumSize: const Size(36, 36),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Quick Presets Wrap
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _ledPresets.map((count) {
              final isSelected = _ledCount == count;
              final meters = (count / 60.0).toStringAsFixed(1);
              return ChoiceChip(
                label: Text('$count ($meters m)'),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) {
                    AppHaptics.selection();
                    _updateCount(count);
                  }
                },
                selectedColor: AppTheme.cyan.withValues(alpha: 0.18),
                backgroundColor: AppTheme.surface,
                side: BorderSide(
                  color: isSelected ? AppTheme.cyan : AppTheme.border,
                ),
                labelStyle: AppTheme.heading(
                  size: 11,
                  color: isSelected ? AppTheme.cyan : AppTheme.textSecondary,
                ),
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),

          const SizedBox(height: 16),

          // Power Budget Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('POWER CURRENT BUDGET', style: AppTheme.heading(size: 10.5, color: AppTheme.textMuted, letterSpacing: 1.0)),
              Text(
                'Max ${_wattageRating.toStringAsFixed(1)}W • 5V PSU',
                style: AppTheme.body(size: 10.5, color: AppTheme.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _currentPresets.map((ma) {
              final isSelected = _maxCurrentMa == ma;
              return ChoiceChip(
                label: Text('${ma}mA (${(5.0 * ma / 1000).toStringAsFixed(1)}W)'),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) {
                    AppHaptics.selection();
                    setState(() {
                      _maxCurrentMa = ma;
                      _currentController.text = ma.toString();
                    });
                  }
                },
                selectedColor: AppTheme.gold.withValues(alpha: 0.18),
                backgroundColor: AppTheme.surface,
                side: BorderSide(
                  color: isSelected ? AppTheme.gold : AppTheme.border,
                ),
                labelStyle: AppTheme.heading(
                  size: 11,
                  color: isSelected ? AppTheme.gold : AppTheme.textSecondary,
                ),
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),

          const SizedBox(height: 16),

          // Color Channel Order (GRB vs RGB vs BRG)
          Text('COLOR CHANNEL ORDER', style: AppTheme.heading(size: 10.5, color: AppTheme.textMuted, letterSpacing: 1.0)),
          const SizedBox(height: 6),
          Row(
            children: [
              for (int i = 0; i < 3; i++) ...[
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      AppHaptics.selection();
                      setState(() => _colorOrder = i);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _colorOrder == i ? AppTheme.surface : AppTheme.surface.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _colorOrder == i ? AppTheme.amber : AppTheme.border,
                          width: _colorOrder == i ? 1.5 : 1.0,
                        ),
                      ),
                      child: Text(
                        LightState.colorOrderNames[i],
                        style: AppTheme.heading(
                          size: 12,
                          color: _colorOrder == i ? AppTheme.amber : AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
                if (i < 2) const SizedBox(width: 8),
              ],
            ],
          ),

          const SizedBox(height: 16),

          // Save Calibration Action Button
          SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveCalibration,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_rounded, size: 18),
              label: Text(
                _isSaving ? 'Saving Calibration...' : 'Save Hardware Calibration',
                style: AppTheme.heading(size: 13, color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.cyan,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
