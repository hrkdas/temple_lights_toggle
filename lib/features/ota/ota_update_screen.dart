import 'dart:math' as math;
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
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _stripAnimController;
  int? _hoveredLedIndex;
  double? _touchProgressFraction;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _stripAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _stripAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final otaState = ref.watch(otaProgressProvider);
    final activeDevice = ref.watch(activeDeviceProvider);
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
              _buildVersionBanner(otaState, activeDevice),
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

              // Interactive End-to-End RGB Strip Light Progress
              _buildInteractiveStripCard(otaState, activeDevice),
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

  Widget _buildVersionBanner(OtaProgressState ota, PairedDevice? activeDevice) {
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
      child: Column(
        children: [
          if (activeDevice != null) ...[
            Row(
              children: [
                const Icon(Icons.lightbulb_rounded, size: 16, color: AppTheme.amber),
                const SizedBox(width: 8),
                Text(
                  'TARGET LIGHT:',
                  style: AppTheme.mono(size: 10, color: AppTheme.textMuted),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    activeDevice.displayName,
                    style: AppTheme.heading(size: 13, color: AppTheme.amber),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Divider(height: 18, color: AppTheme.border),
          ],
          Row(
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

  Widget _buildInteractiveStripCard(OtaProgressState ota, PairedDevice? activeDevice) {
    final totalLeds = activeDevice?.effectiveLedCount ?? 150;
    final isUpdating = ota.isInProgress;
    final isCompleted = ota.phase == OtaPhase.completed;
    final isFailed = ota.phase == OtaPhase.failed;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isCompleted
              ? AppTheme.green.withValues(alpha: 0.5)
              : isFailed
                  ? AppTheme.red.withValues(alpha: 0.4)
                  : (isUpdating ? AppTheme.amber.withValues(alpha: 0.45) : AppTheme.border),
        ),
        boxShadow: [
          BoxShadow(
            color: (isCompleted
                    ? AppTheme.green
                    : (isUpdating ? AppTheme.amber : Colors.black))
                .withValues(alpha: isUpdating ? 0.08 : 0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Title & Real-Time Sync Indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.linear_scale_rounded,
                    size: 16,
                    color: isCompleted
                        ? AppTheme.green
                        : (isFailed ? AppTheme.red : AppTheme.amber),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'INTERACTIVE RGB STRIP LIGHT',
                    style: AppTheme.mono(size: 11, color: AppTheme.textPrimary, weight: FontWeight.w700),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isCompleted
                          ? AppTheme.green
                          : (isUpdating ? AppTheme.amber : AppTheme.border))
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: (isCompleted
                            ? AppTheme.green
                            : (isUpdating ? AppTheme.amber : AppTheme.border))
                        .withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isCompleted
                            ? AppTheme.green
                            : (isFailed ? AppTheme.red : (isUpdating ? AppTheme.amber : AppTheme.textMuted)),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isCompleted
                          ? 'BOOTED'
                          : (isUpdating ? 'END-TO-END FLOW' : 'HARDWARE SYNC'),
                      style: AppTheme.mono(
                        size: 9.5,
                        color: isCompleted
                            ? AppTheme.green
                            : (isFailed ? AppTheme.red : (isUpdating ? AppTheme.amber : AppTheme.textMuted)),
                        weight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Strip Ruler Indices (Start / Current Sector / End)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'PIN 4 • LED 1',
                style: AppTheme.mono(size: 9.5, color: AppTheme.textMuted),
              ),
              Text(
                'SECTOR: ${(ota.progress * totalLeds).floor()} / $totalLeds LEDS',
                style: AppTheme.mono(
                  size: 9.5,
                  color: isCompleted ? AppTheme.green : AppTheme.amber,
                  weight: FontWeight.w600,
                ),
              ),
              Text(
                'LED $totalLeds (${activeDevice?.formattedLength ?? "2.5m"})',
                style: AppTheme.mono(size: 9.5, color: AppTheme.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Interactive Animated Canvas Strip
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return GestureDetector(
                key: const Key('ota_strip_gesture_detector'),
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (details) => _handleStripTouch(details.localPosition.dx, width, totalLeds),
                onHorizontalDragUpdate: (details) => _handleStripTouch(details.localPosition.dx, width, totalLeds),
                onHorizontalDragEnd: (_) => setState(() {
                  _hoveredLedIndex = null;
                  _touchProgressFraction = null;
                }),
                onTapDown: (details) => _handleStripTouch(details.localPosition.dx, width, totalLeds),
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFF101216),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border.withValues(alpha: 0.6)),
                  ),
                  child: AnimatedBuilder(
                    animation: _stripAnimController,
                    builder: (context, _) {
                      return CustomPaint(
                        size: Size(width, 52),
                        painter: _OtaStripCanvasPainter(
                          progress: ota.progress,
                          phase: ota.phase,
                          animValue: _stripAnimController.value,
                          totalLeds: totalLeds,
                          touchFraction: _touchProgressFraction,
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 10),

          // Interactive Touch Readout or Color Legend
          if (_hoveredLedIndex != null && _touchProgressFraction != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.amber.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.amber.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'INSPECTING: LED #$_hoveredLedIndex',
                    style: AppTheme.mono(size: 10, color: AppTheme.amber, weight: FontWeight.w700),
                  ),
                  Text(
                    '${(_touchProgressFraction! * 100).toStringAsFixed(0)}% • ${_touchProgressFraction! <= ota.progress ? "WRITTEN (FLASH SECURED)" : "PENDING GUIDE"}',
                    style: AppTheme.mono(
                      size: 10,
                      color: _touchProgressFraction! <= ota.progress ? AppTheme.amber : AppTheme.textMuted,
                      weight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildLegendItem(const Color(0xFFFF9E22), 'Written Flash'),
                _buildLegendItem(Colors.white, 'Active Spark Head'),
                _buildLegendItem(const Color(0xFF323B54), 'Pending Guide Track'),
              ],
            ),
        ],
      ),
    );
  }

  void _handleStripTouch(double localX, double width, int totalLeds) {
    const margin = 12.0;
    final usableW = width - (margin * 2);
    if (usableW <= 0) return;
    final rawFrac = ((localX - margin) / usableW).clamp(0.0, 1.0);
    final led = 1 + (rawFrac * (totalLeds - 1)).round();
    if (led != _hoveredLedIndex) {
      AppHaptics.selection();
    }
    setState(() {
      _hoveredLedIndex = led;
      _touchProgressFraction = rawFrac;
    });
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 3,
              ),
            ],
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: AppTheme.mono(size: 9.5, color: AppTheme.textMuted),
        ),
      ],
    );
  }
}

class _OtaStripCanvasPainter extends CustomPainter {
  _OtaStripCanvasPainter({
    required this.progress,
    required this.phase,
    required this.animValue,
    required this.totalLeds,
    this.touchFraction,
  });

  final double progress;
  final OtaPhase phase;
  final double animValue;
  final int totalLeds;
  final double? touchFraction;

  @override
  void paint(Canvas canvas, Size size) {
    const margin = 12.0;
    final trackW = size.width - (margin * 2);
    final centerY = size.height / 2;

    // 1. Metallic ribbon trace behind diodes
    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(margin, centerY), Offset(size.width - margin, centerY), trackPaint);

    final diodeCount = math.min(totalLeds, 48);
    if (diodeCount <= 1) return;

    final isSuccess = phase == OtaPhase.completed || phase == OtaPhase.rebooting;
    final isFailed = phase == OtaPhase.failed;

    for (int i = 0; i < diodeCount; i++) {
      final diodeFrac = i / (diodeCount - 1);
      final x = margin + diodeFrac * trackW;

      if (isSuccess) {
        // Triumphant Emerald-Gold Bloom wave across all diodes
        final centerNorm = (diodeFrac - 0.5).abs() * 2.0;
        final waveVal = (math.sin((animValue * 3.0 - centerNorm * 1.5) * math.pi) * 0.5 + 0.5);
        final diodeColor = Color.lerp(
          const Color(0xFF22C55E),
          const Color(0xFFFFD54F),
          waveVal,
        )!;

        final glowPaint = Paint()
          ..color = diodeColor.withValues(alpha: 0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5.0);
        canvas.drawCircle(Offset(x, centerY), 4.5, glowPaint);

        final corePaint = Paint()..color = diodeColor;
        canvas.drawCircle(Offset(x, centerY), 2.8, corePaint);

        final specPaint = Paint()..color = Colors.white.withValues(alpha: 0.85);
        canvas.drawCircle(Offset(x, centerY), 1.2, specPaint);
        continue;
      }

      if (isFailed) {
        // Warning pulse in coral red
        final pulse = 0.5 + 0.5 * math.sin(animValue * 4 * math.pi);
        final diodeColor = const Color(0xFFEF4444).withValues(alpha: 0.2 + 0.6 * pulse);
        final corePaint = Paint()..color = diodeColor;
        canvas.drawCircle(Offset(x, centerY), 2.5, corePaint);
        continue;
      }

      final dist = (diodeFrac - progress) * (diodeCount - 1);

      if (dist < -1.5) {
        // Written Diode (Behind Active Head): Sacred Amber-Gold with gentle breath
        final breath = 0.82 + 0.18 * math.sin(animValue * 2 * math.pi * 2 + (i * 0.25));
        final baseColor = const Color(0xFFFF9E22);
        final effColor = baseColor.withValues(alpha: breath.clamp(0.0, 1.0));

        final glowPaint = Paint()
          ..color = effColor.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);
        canvas.drawCircle(Offset(x, centerY), 4.5, glowPaint);

        final diodePaint = Paint()..color = effColor;
        canvas.drawCircle(Offset(x, centerY), 2.8, diodePaint);

        final specPaint = Paint()..color = Colors.white.withValues(alpha: 0.65 * breath);
        canvas.drawCircle(Offset(x, centerY), 1.1, specPaint);
      } else if (dist > 1.5) {
        // Unwritten Diode (Guide Track Ahead): Deep dusk indigo with starlight shimmer
        final shimmer = 0.5 + 0.5 * math.sin(animValue * 2 * math.pi * 3 - (i * 0.35));
        final trackColor = Color.lerp(
          const Color(0xFF1B202E),
          const Color(0xFF38446B),
          shimmer,
        )!;

        final diodePaint = Paint()..color = trackColor;
        canvas.drawCircle(Offset(x, centerY), 2.2, diodePaint);
      } else {
        // Active Flash Head / Spark Diode (|dist| <= 1.5)
        final headFactor = (1.0 - (dist.abs() / 1.5)).clamp(0.0, 1.0);
        final pulse = 0.80 + 0.20 * math.sin(animValue * 8 * math.pi);

        final haloPaint = Paint()
          ..color = const Color(0xFFFFB300).withValues(alpha: 0.75 * headFactor * pulse)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.5);
        canvas.drawCircle(Offset(x, centerY), 6.5, haloPaint);

        final sparkColor = Color.lerp(
          const Color(0xFFFF9E22),
          const Color(0xFFFFFFFF),
          headFactor * pulse,
        )!;
        final sparkPaint = Paint()..color = sparkColor;
        canvas.drawCircle(Offset(x, centerY), 3.4, sparkPaint);

        final specPaint = Paint()..color = Colors.white;
        canvas.drawCircle(Offset(x, centerY), 1.5, specPaint);
      }
    }

    // Touch inspection crosshair & indicator needle
    if (touchFraction != null) {
      final touchX = margin + touchFraction! * trackW;
      final touchPaint = Paint()
        ..color = AppTheme.amber.withValues(alpha: 0.8)
        ..strokeWidth = 1.5;
      canvas.drawLine(Offset(touchX, 6), Offset(touchX, size.height - 6), touchPaint);

      final needleCircle = Paint()..color = AppTheme.amber;
      canvas.drawCircle(Offset(touchX, centerY), 4.5, needleCircle);

      final needleHole = Paint()..color = const Color(0xFF101216);
      canvas.drawCircle(Offset(touchX, centerY), 2.0, needleHole);
    }
  }

  @override
  bool shouldRepaint(covariant _OtaStripCanvasPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.phase != phase ||
        oldDelegate.animValue != animValue ||
        oldDelegate.touchFraction != touchFraction;
  }
}
