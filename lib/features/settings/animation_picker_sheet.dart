import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/providers.dart';
import '../../ui/theme.dart';

/// Modal bottom sheet to select devotional animation transitions and ambient aura styles.
class AnimationPickerSheet extends ConsumerStatefulWidget {
  const AnimationPickerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => const AnimationPickerSheet(),
    );
  }

  @override
  ConsumerState<AnimationPickerSheet> createState() => _AnimationPickerSheetState();
}

class _AnimationPickerSheetState extends ConsumerState<AnimationPickerSheet> {
  late int _transitionStyle;
  late int _ambientStyle;
  late int _ambientDepth;

  @override
  void initState() {
    super.initState();
    final light = ref.read(lightControlProvider);
    _transitionStyle = light.transitionStyle;
    _ambientStyle = light.ambientStyle;
    _ambientDepth = light.ambientDepth;
  }

  Future<void> _save() async {
    await ref.read(lightControlProvider.notifier).setAnimationConfig(
          transitionStyle: _transitionStyle,
          ambientStyle: _ambientStyle,
          depth: _ambientDepth,
        );

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppTheme.surfaceRaised,
          content: Text(
            'Animation & Living Aura saved to Temple Light',
            style: TextStyle(color: AppTheme.green, fontSize: 13),
          ),
        ),
      );
    }
  }

  Widget _buildOptionTile({
    required String title,
    required String description,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    Color activeColor = AppTheme.amber,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isSelected ? activeColor.withValues(alpha: 0.12) : AppTheme.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected ? activeColor : AppTheme.border,
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isSelected ? activeColor.withValues(alpha: 0.2) : AppTheme.border.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: isSelected ? activeColor : AppTheme.textSecondary),
        ),
        title: Text(
          title,
          style: AppTheme.heading(
            size: 14,
            color: isSelected ? activeColor : AppTheme.textPrimary,
          ),
        ),
        subtitle: Text(
          description,
          style: AppTheme.body(size: 12, color: AppTheme.textMuted),
        ),
        trailing: isSelected
            ? Icon(Icons.check_circle_rounded, color: activeColor, size: 20)
            : null,
        onTap: onTap,
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
        initialChildSize: 0.85,
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
                        Text('Devotional Animations', style: AppTheme.heading(size: 19)),
                        const SizedBox(height: 2),
                        Text(
                          'Configure visual transitions for $targetName',
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

                // Section 1: Power ON/OFF & Mode Transitions
                Text('Power ON/OFF & Switch Transitions', style: AppTheme.heading(size: 14, color: AppTheme.amber)),
                const SizedBox(height: 4),
                Text(
                  'How light emerges and recedes across your shrine:',
                  style: AppTheme.body(size: 12, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 12),

                _buildOptionTile(
                  title: 'Center-Out Dawn (Symmetric Bloom)',
                  description: 'Light radiates from behind the deity outwards to the altar borders.',
                  icon: Icons.unfold_more_rounded,
                  isSelected: _transitionStyle == 0,
                  activeColor: AppTheme.amber,
                  onTap: () => setState(() => _transitionStyle = 0),
                ),
                _buildOptionTile(
                  title: 'Sunrise Flow (Linear Sweep)',
                  description: 'Smooth, continuous flow from one end to the other.',
                  icon: Icons.east_rounded,
                  isSelected: _transitionStyle == 1,
                  activeColor: AppTheme.amber,
                  onTap: () => setState(() => _transitionStyle = 1),
                ),
                _buildOptionTile(
                  title: 'Uniform Smooth Fade',
                  description: 'All LEDs fade simultaneously without spatial wave propagation.',
                  icon: Icons.blur_linear_rounded,
                  isSelected: _transitionStyle == 2,
                  activeColor: AppTheme.amber,
                  onTap: () => setState(() => _transitionStyle = 2),
                ),

                const SizedBox(height: 20),

                // Section 2: Living Ambient Aura
                Text('Living Ambient Aura (When ON)', style: AppTheme.heading(size: 14, color: AppTheme.cyan)),
                const SizedBox(height: 4),
                Text(
                  'Subtle motion while your temple sanctuary is illuminated:',
                  style: AppTheme.body(size: 12, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 12),

                _buildOptionTile(
                  title: 'Gentle Breathing',
                  description: 'Slow, peaceful sinusoidal oscillation at a calm 3-second cycle.',
                  icon: Icons.air_rounded,
                  isSelected: _ambientStyle == 1,
                  activeColor: AppTheme.cyan,
                  onTap: () => setState(() => _ambientStyle = 1),
                ),
                _buildOptionTile(
                  title: 'Sacred Diya / Candle Flame Flutter',
                  description: 'Warm organic micro-flicker imitating brass oil lamps and diyas.',
                  icon: Icons.local_fire_department_rounded,
                  isSelected: _ambientStyle == 2,
                  activeColor: AppTheme.cyan,
                  onTap: () => setState(() => _ambientStyle = 2),
                ),
                _buildOptionTile(
                  title: 'Pure Solid Radiance',
                  description: 'Completely still, undisturbed illumination with zero motion.',
                  icon: Icons.wb_sunny_rounded,
                  isSelected: _ambientStyle == 0,
                  activeColor: AppTheme.cyan,
                  onTap: () => setState(() => _ambientStyle = 0),
                ),

                if (_ambientStyle != 0) ...[
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Aura Oscillation Depth', style: AppTheme.heading(size: 13, color: AppTheme.textSecondary)),
                      Text('$_ambientDepth%', style: AppTheme.mono(size: 13, color: AppTheme.cyan)),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: AppTheme.cyan,
                      inactiveTrackColor: AppTheme.surfaceRaised,
                      thumbColor: AppTheme.cyan,
                      overlayColor: AppTheme.cyan.withValues(alpha: 0.15),
                    ),
                    child: Slider(
                      value: _ambientDepth.toDouble(),
                      min: 3,
                      max: 18,
                      divisions: 15,
                      label: '$_ambientDepth%',
                      onChanged: (val) => setState(() => _ambientDepth = val.round()),
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Save Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle_rounded, size: 18, color: Colors.white),
                    label: Text('Save Animation Settings', style: AppTheme.heading(size: 14, color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.cyan,
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
