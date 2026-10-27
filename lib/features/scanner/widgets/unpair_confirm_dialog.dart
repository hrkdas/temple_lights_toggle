import 'package:flutter/material.dart';
import '../../../core/haptics.dart';
import '../../../ui/theme.dart';

/// Modal dialog confirming the unpairing of a light with destructive alert styling.
/// Modeled after Boturo's UnpairConfirmDialog, styled with Temple Lights Serene Alabaster luxury.
class UnpairConfirmDialog extends StatelessWidget {
  const UnpairConfirmDialog({
    super.key,
    required this.deviceName,
  });

  final String deviceName;

  static Future<bool?> show(BuildContext context, {required String deviceName}) {
    AppHaptics.warning();
    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => UnpairConfirmDialog(deviceName: deviceName),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: AppTheme.border, width: 1.2),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row: Red Link-Off Badge + Title
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppTheme.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.red.withValues(alpha: 0.35),
                      width: 1.2,
                    ),
                  ),
                  child: const Icon(
                    Icons.link_off_rounded,
                    size: 20,
                    color: AppTheme.red,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Unpair Temple Light?',
                    style: AppTheme.heading(size: 17, color: AppTheme.textPrimary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Reassuring & Clear Copy
            Text.rich(
              TextSpan(
                style: AppTheme.body(size: 13, color: AppTheme.textSecondary),
                children: [
                  const TextSpan(text: 'Are you sure you want to unpair '),
                  TextSpan(
                    text: '"$deviceName"',
                    style: AppTheme.heading(size: 13, color: AppTheme.textPrimary),
                  ),
                  const TextSpan(
                    text:
                        '? It will be disconnected and removed from your device manager. You can re-pair it anytime by scanning nearby.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Action Buttons (Cancel / Unpair)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    AppHaptics.selection();
                    Navigator.of(context).pop(false);
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    foregroundColor: AppTheme.textMuted,
                  ),
                  child: Text(
                    'Cancel',
                    style: AppTheme.heading(size: 13, color: AppTheme.textMuted),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    AppHaptics.heavy();
                    Navigator.of(context).pop(true);
                  },
                  icon: const Icon(Icons.link_off_rounded, size: 16),
                  label: const Text('Unpair'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.red,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
