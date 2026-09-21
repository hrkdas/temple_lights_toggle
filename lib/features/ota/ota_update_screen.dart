import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/haptics.dart';
import '../../domain/models.dart';
import '../../domain/providers.dart';
import '../../ui/theme.dart';

/// Serene Luxury Light UI animated firmware OTA update screen.
class OtaUpdateScreen extends ConsumerStatefulWidget {
  const OtaUpdateScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const OtaUpdateScreen(),
      ),
    );
  }

  @override
  ConsumerState<OtaUpdateScreen> createState() => _OtaUpdateScreenState();
}

class _OtaUpdateScreenState extends ConsumerState<OtaUpdateScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final otaState = ref.watch(otaProgressProvider);
    final isUpdating = otaState.isInProgress;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: AppTheme.textPrimary),
          onPressed: isUpdating
              ? () => _confirmCancel(context)
              : () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Firmware Update',
          style: AppTheme.heading(size: 18, color: AppTheme.textPrimary),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Version & Device Info Card
              _buildVersionBanner(otaState),
              const SizedBox(height: 32),

              // Animated Radial Progress Ring
              _buildProgressRing(otaState),
              const SizedBox(height: 28),

              // Status Message & Subtitle
              Text(
                otaState.statusMessage,
                textAlign: TextAlign.center,
                style: AppTheme.heading(
                  size: 20,
                  color: otaState.phase == OtaPhase.failed
                      ? AppTheme.red
                      : otaState.phase == OtaPhase.completed
                          ? AppTheme.green
                          : AppTheme.amber,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _getSubstatusText(otaState),
                textAlign: TextAlign.center,
                style: AppTheme.body(size: 13, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 24),

              // Metrics Dashboard (Speed, ETA, Size)
              if (isUpdating || otaState.bytesWritten > 0)
                _buildMetricsCard(otaState),

              const SizedBox(height: 24),

              // Step Progress Timeline
              _buildStepTimeline(otaState),

              const SizedBox(height: 28),

              // Safety Precaution Notice
              if (isUpdating)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.amber.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.amber.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          size: 22, color: AppTheme.amber),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Keep phone nearby and powered on. Do not disconnect Temple Lights power.',
                          style: AppTheme.body(size: 11.5, color: AppTheme.gold),
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 32),

              // Primary Action Buttons
              _buildActionButtons(otaState),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVersionBanner(OtaProgressState ota) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: AppTheme.textPrimary.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'CURRENT FIRMWARE',
                style: AppTheme.mono(size: 10.5, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 2),
              Text(
                ota.deviceFirmwareVersion != null
                    ? 'v${ota.deviceFirmwareVersion}'
                    : 'v1.0.0 (Pre-OTA)',
                style: AppTheme.heading(size: 14, color: AppTheme.textPrimary),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.amber.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_forward_rounded,
                size: 16, color: AppTheme.amber),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'BUNDLED APK FIRMWARE',
                style: AppTheme.mono(size: 10.5, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 2),
              Text(
                'v${ota.bundledFirmwareVersion}',
                style: AppTheme.heading(size: 14, color: AppTheme.amber),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressRing(OtaProgressState ota) {
    final progress = ota.progress;
    final pct = ota.percentage;

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final glowOpacity = ota.isInProgress
            ? 0.15 + 0.15 * _pulseController.value
            : (ota.phase == OtaPhase.completed ? 0.25 : 0.08);

        return Stack(
          alignment: Alignment.center,
          children: [
            // Ambient Sacred Gold Glow
            Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (ota.phase == OtaPhase.completed
                            ? AppTheme.green
                            : ota.phase == OtaPhase.failed
                                ? AppTheme.red
                                : AppTheme.amber)
                        .withValues(alpha: glowOpacity),
                    blurRadius: 54,
                    spreadRadius: 8,
                  ),
                ],
              ),
            ),

            // Base Porcelain Disc
            Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                color: AppTheme.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.border, width: 2),
              ),
            ),

            // Circular Progress Indicator
            SizedBox(
              width: 180,
              height: 180,
              child: CircularProgressIndicator(
                value: ota.isInProgress
                    ? (progress > 0 ? progress : null)
                    : (ota.phase == OtaPhase.completed ? 1.0 : 0.0),
                strokeWidth: 9,
                strokeCap: StrokeCap.round,
                backgroundColor: AppTheme.border.withValues(alpha: 0.6),
                valueColor: AlwaysStoppedAnimation<Color>(
                  ota.phase == OtaPhase.completed
                      ? AppTheme.green
                      : ota.phase == OtaPhase.failed
                          ? AppTheme.red
                          : AppTheme.amber,
                ),
              ),
            ),

            // Center Content
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (ota.phase == OtaPhase.completed) ...[
                  const Icon(Icons.check_circle_rounded,
                      size: 48, color: AppTheme.green)
                      .animate()
                      .scale(duration: 400.ms, curve: Curves.easeOutBack),
                  const SizedBox(height: 6),
                  Text('SUCCESS',
                      style: AppTheme.mono(size: 12, color: AppTheme.green)),
                ] else if (ota.phase == OtaPhase.failed) ...[
                  const Icon(Icons.error_outline_rounded,
                      size: 48, color: AppTheme.red)
                      .animate()
                      .shake(duration: 400.ms),
                  const SizedBox(height: 6),
                  Text('FAILED',
                      style: AppTheme.mono(size: 12, color: AppTheme.red)),
                ] else ...[
                  Text(
                    '$pct%',
                    style: AppTheme.mono(
                      size: 42,
                      weight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    ota.phase == OtaPhase.rebooting
                        ? 'REBOOTING'
                        : ota.phase == OtaPhase.verifying
                            ? 'VERIFYING'
                            : 'PROGRESS',
                    style: AppTheme.mono(size: 11, color: AppTheme.textMuted),
                  ),
                ],
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildMetricsCard(OtaProgressState ota) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildMetricItem(
              icon: Icons.data_usage_rounded,
              label: 'TRANSFERRED',
              value: ota.formattedBytes,
            ),
          ),
          Container(width: 1, height: 32, color: AppTheme.border),
          Expanded(
            child: _buildMetricItem(
              icon: Icons.speed_rounded,
              label: 'SPEED',
              value: ota.formattedSpeed,
            ),
          ),
          Container(width: 1, height: 32, color: AppTheme.border),
          Expanded(
            child: _buildMetricItem(
              icon: Icons.timer_outlined,
              label: 'REMAINING',
              value: ota.formattedEta,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricItem({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 13, color: AppTheme.textMuted),
            const SizedBox(width: 4),
            Text(label, style: AppTheme.mono(size: 9.5, color: AppTheme.textMuted)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTheme.mono(
            size: 12.5,
            weight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildStepTimeline(OtaProgressState ota) {
    final steps = [
      {'title': 'Package & Handshake', 'active': ota.phase.index >= OtaPhase.preparing.index},
      {'title': 'Flash Transmission', 'active': ota.phase.index >= OtaPhase.transferring.index},
      {'title': 'Integrity Check', 'active': ota.phase.index >= OtaPhase.verifying.index},
      {'title': 'Device Reboot', 'active': ota.phase.index >= OtaPhase.rebooting.index},
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('UPDATE PROGRESSION',
              style: AppTheme.mono(size: 10.5, color: AppTheme.textMuted)),
          const SizedBox(height: 12),
          for (int i = 0; i < steps.length; i++) ...[
            Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (steps[i]['active'] as bool)
                        ? AppTheme.amber
                        : AppTheme.surfaceRaised,
                    border: Border.all(
                      color: (steps[i]['active'] as bool)
                          ? AppTheme.amber
                          : AppTheme.border,
                    ),
                  ),
                  child: Center(
                    child: (steps[i]['active'] as bool)
                        ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                        : Text('${i + 1}',
                            style: AppTheme.mono(size: 10, color: AppTheme.textMuted)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    steps[i]['title'] as String,
                    style: AppTheme.body(
                      size: 13,
                      weight: (steps[i]['active'] as bool)
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: (steps[i]['active'] as bool)
                          ? AppTheme.textPrimary
                          : AppTheme.textMuted,
                    ),
                  ),
                ),
              ],
            ),
            if (i < steps.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Container(
                  width: 2,
                  height: 14,
                  color: (steps[i]['active'] as bool)
                      ? AppTheme.amber.withValues(alpha: 0.5)
                      : AppTheme.border,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButtons(OtaProgressState ota) {
    if (ota.isInProgress) {
      return OutlinedButton.icon(
        icon: const Icon(Icons.cancel_outlined, color: AppTheme.red),
        label: Text('Cancel Update',
            style: AppTheme.heading(size: 14, color: AppTheme.red)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppTheme.red),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: () => _confirmCancel(context),
      );
    }

    if (ota.phase == OtaPhase.completed) {
      return ElevatedButton.icon(
        icon: const Icon(Icons.done_all_rounded, color: Colors.white),
        label: Text('Return to Lights',
            style: AppTheme.heading(size: 15, color: Colors.white)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.green,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 2,
        ),
        onPressed: () {
          ref.read(otaProgressProvider.notifier).reset();
          Navigator.of(context).pop();
        },
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: const Icon(Icons.system_update_rounded, color: Colors.white),
        label: Text(
          ota.phase == OtaPhase.failed ? 'Retry Firmware Update' : 'Start Firmware Update',
          style: AppTheme.heading(size: 15, color: Colors.white),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.amber,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 3,
          shadowColor: AppTheme.amber.withValues(alpha: 0.4),
        ),
        onPressed: () {
          AppHaptics.medium();
          ref.read(otaProgressProvider.notifier).startUpdate();
        },
      ),
    );
  }

  String _getSubstatusText(OtaProgressState ota) {
    switch (ota.phase) {
      case OtaPhase.idle:
        return 'Ready to flash bundled v${ota.bundledFirmwareVersion} firmware';
      case OtaPhase.loadingAsset:
        return 'Extracting firmware binary from APK assets';
      case OtaPhase.connecting:
        return 'Connecting to Temple Lights over BLE';
      case OtaPhase.preparing:
        return 'Partitioning ESP32 OTA flash space';
      case OtaPhase.transferring:
        return 'Streaming 256-byte acknowledged blocks over GATT';
      case OtaPhase.verifying:
        return 'Validating MD5 cryptographic checksum';
      case OtaPhase.rebooting:
        return 'ESP32 is swapping active partition and booting';
      case OtaPhase.completed:
        return 'Temple Lights has rebooted with new firmware';
      case OtaPhase.failed:
        return ota.errorMessage ?? 'An error occurred during update';
      case OtaPhase.canceled:
        return 'Update was stopped by user request';
    }
  }

  void _confirmCancel(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('Cancel Firmware Update?',
            style: AppTheme.heading(size: 18, color: AppTheme.red)),
        content: Text(
          'Aborting mid-update will cancel the transfer. Your ESP32 will safely stay on its current firmware partition.',
          style: AppTheme.body(size: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Keep Updating',
                style: AppTheme.heading(size: 13, color: AppTheme.amber)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(otaProgressProvider.notifier).cancelUpdate();
            },
            child: Text('Abort',
                style: AppTheme.heading(size: 13, color: AppTheme.red)),
          ),
        ],
      ),
    );
  }
}
