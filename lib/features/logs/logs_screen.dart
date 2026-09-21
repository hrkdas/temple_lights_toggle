import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/haptics.dart';
import '../../domain/models.dart';
import '../../domain/providers.dart';
import '../../ui/theme.dart';

/// Screen displaying rolling 20 ON/OFF activity logs synchronized with ESP32 flash memory.
class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen> {
  int _filterIndex = 0; // 0: ALL, 1: TURN ON, 2: TURN OFF
  bool _isSyncing = false;

  Future<void> _syncLogs() async {
    setState(() => _isSyncing = true);
    await AppHaptics.selection();
    await ref.read(schedulesProvider.notifier).syncTimeWithDevice();
    await Future.delayed(const Duration(milliseconds: 50));
    await ref.read(logsProvider.notifier).requestLogsFromDevice();
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) {
      setState(() => _isSyncing = false);
    }
  }

  void _confirmClearLogs(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppTheme.borderBright),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.delete_sweep_rounded, color: AppTheme.red, size: 24),
            ),
            const SizedBox(width: 12),
            Text(
              'CLEAR LOGS',
              style: AppTheme.heading(size: 16, color: AppTheme.red, letterSpacing: 1.5),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to erase all 20 activity logs from both ESP32 flash storage and local app memory?',
          style: AppTheme.body(size: 13.5, color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('CANCEL', style: AppTheme.heading(size: 12, color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await AppHaptics.warn();
              await ref.read(logsProvider.notifier).clearLogs();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: AppTheme.surfaceRaised,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: AppTheme.red.withValues(alpha: 0.5)),
                    ),
                    content: Text(
                      'All logs cleared from ESP32 storage',
                      style: AppTheme.body(size: 13, color: AppTheme.textPrimary),
                    ),
                  ),
                );
              }
            },
            child: Text('CLEAR ALL', style: AppTheme.heading(size: 12, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _copyLogsToClipboard(List<LightLogEntry> logs) {
    if (logs.isEmpty) return;
    final buffer = StringBuffer();
    buffer.writeln('=== MOTOR TOGGLE ACTIVITY LOGS (ESP32 SYNC) ===');
    for (final l in logs) {
      final stateStr = l.isOn ? 'TURNED ON' : 'TURNED OFF';
      final durStr = (!l.isOn && l.durationSeconds > 0) ? ' [Duration: ${l.formattedDuration}]' : '';
      buffer.writeln('${l.formattedDateTime} | $stateStr | Source: ${l.source}$durStr');
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    AppHaptics.impact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.surfaceRaised,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppTheme.cyan),
        ),
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: AppTheme.cyan, size: 18),
            const SizedBox(width: 10),
            Text(
              'Logs copied to clipboard',
              style: AppTheme.body(size: 13, color: AppTheme.textPrimary),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allLogs = ref.watch(logsProvider);
    final conn = ref.watch(relaySessionProvider);

    // Apply Filter
    final filteredLogs = allLogs.where((l) {
      if (_filterIndex == 1) return l.isOn;
      if (_filterIndex == 2) return !l.isOn;
      return true;
    }).toList();

    // Compute Telemetry Stats
    final onCount = allLogs.where((l) => l.isOn).length;
    final offCount = allLogs.where((l) => !l.isOn).length;
    final totalRunSeconds = allLogs
        .where((l) => !l.isOn)
        .fold<int>(0, (sum, item) => sum + item.durationSeconds);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Top Telemetry & Flash Status Banner
              _buildHeaderBanner(
                totalCount: allLogs.length,
                onCount: onCount,
                offCount: offCount,
                totalRunSeconds: totalRunSeconds,
                isConnected: conn.isConnected,
                onSync: _syncLogs,
                onClear: allLogs.isNotEmpty ? () => _confirmClearLogs(context) : null,
                onCopy: allLogs.isNotEmpty ? () => _copyLogsToClipboard(allLogs) : null,
              ),
              const SizedBox(height: 12),

              // 2. Filter Tab Selector Chips
              _buildFilterChips(allCount: allLogs.length, onCount: onCount, offCount: offCount),
              const SizedBox(height: 12),

              // 3. Scrollable Logs Timeline List with Pull-to-Refresh
              Expanded(
                child: filteredLogs.isEmpty
                    ? RefreshIndicator(
                        color: AppTheme.cyan,
                        backgroundColor: AppTheme.surfaceRaised,
                        onRefresh: _syncLogs,
                        child: ListView(
                          children: [
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.5,
                              child: _buildEmptyState(context, conn.isConnected),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        color: AppTheme.cyan,
                        backgroundColor: AppTheme.surfaceRaised,
                        onRefresh: _syncLogs,
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: filteredLogs.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final entry = filteredLogs[index];
                            return _buildLogCard(entry, index)
                                .animate()
                                .fadeIn(duration: 180.ms, delay: (index * 40).ms)
                                .slideY(begin: 0.08, end: 0, duration: 180.ms);
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderBanner({
    required int totalCount,
    required int onCount,
    required int offCount,
    required int totalRunSeconds,
    required bool isConnected,
    required VoidCallback onSync,
    required VoidCallback? onClear,
    required VoidCallback? onCopy,
  }) {
    final hasLogs = totalCount > 0;
    final bannerColor = hasLogs ? AppTheme.cyan : AppTheme.textMuted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: bannerColor.withValues(alpha: hasLogs ? 0.4 : 0.2),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: bannerColor.withValues(alpha: hasLogs ? 0.08 : 0.01),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: bannerColor.withValues(alpha: hasLogs ? 0.15 : 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.receipt_long_rounded,
                  color: bannerColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'ON-OFF ACTIVITY LOGS',
                          style: AppTheme.heading(size: 12, color: bannerColor, letterSpacing: 1.2),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceRaised,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: hasLogs ? AppTheme.cyan.withValues(alpha: 0.3) : AppTheme.border,
                            ),
                          ),
                          child: Text(
                            '$totalCount / 20 IN FLASH',
                            style: AppTheme.heading(
                              size: 10,
                              color: hasLogs ? AppTheme.cyan : AppTheme.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isConnected
                          ? 'Synchronized with ESP32 persistent NVS flash'
                          : 'Showing local cached logs (Connect ESP32 to sync)',
                      style: AppTheme.body(size: 11.5, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Secondary Telemetry Row: Runtime Duration & Actions
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.surfaceRaised,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.timer_outlined, size: 16, color: AppTheme.gold),
                const SizedBox(width: 6),
                Text(
                  'Runtime: ',
                  style: AppTheme.heading(size: 11, color: AppTheme.textMuted),
                ),
                Text(
                  LightLogEntry(
                    id: '0',
                    isOn: false,
                    timestamp: DateTime.now(),
                    durationSeconds: totalRunSeconds,
                  ).formattedDuration,
                  style: AppTheme.heading(size: 12, color: AppTheme.gold),
                ),
                const Spacer(),

                // Copy Action
                if (onCopy != null)
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18, color: AppTheme.textSecondary),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Copy logs to clipboard',
                    onPressed: onCopy,
                  ),

                // Clear Action
                if (onClear != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.crimson),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Clear all logs',
                    onPressed: onClear,
                  ),

                // Sync Action
                IconButton(
                  icon: AnimatedRotation(
                    turns: _isSyncing ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 600),
                    child: const Icon(Icons.sync_rounded, size: 20, color: AppTheme.cyan),
                  ),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Sync logs from ESP32 memory',
                  onPressed: onSync,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips({
    required int allCount,
    required int onCount,
    required int offCount,
  }) {
    return Row(
      children: [
        _buildChipItem(0, 'ALL ($allCount)'),
        const SizedBox(width: 8),
        _buildChipItem(1, 'ON ($onCount)', activeColor: AppTheme.green),
        const SizedBox(width: 8),
        _buildChipItem(2, 'OFF ($offCount)', activeColor: AppTheme.orange),
      ],
    );
  }

  Widget _buildChipItem(int index, String label, {Color activeColor = AppTheme.cyan}) {
    final isSelected = _filterIndex == index;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          AppHaptics.selection();
          setState(() => _filterIndex = index);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? activeColor.withValues(alpha: 0.15) : AppTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? activeColor : AppTheme.border,
              width: isSelected ? 1.4 : 1.0,
            ),
          ),
          child: Text(
            label,
            style: AppTheme.heading(
              size: 11,
              color: isSelected ? activeColor : AppTheme.textMuted,
              letterSpacing: 1.0,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogCard(LightLogEntry entry, int index) {
    final isOn = entry.isOn;
    final accentColor = isOn ? AppTheme.green : AppTheme.orange;

    IconData sourceIcon = Icons.power_rounded;
    final src = entry.source.toLowerCase();
    if (src.contains('schedule') || src.contains('alarm')) {
      sourceIcon = Icons.alarm_rounded;
    } else if (src.contains('timer')) {
      sourceIcon = Icons.timer_rounded;
    } else if (src.contains('cutoff') || src.contains('stop')) {
      sourceIcon = Icons.power_settings_new_rounded;
    } else if (src.contains('ble') || src.contains('app')) {
      sourceIcon = Icons.bluetooth_connected_rounded;
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.35),
          width: 1.1,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: State Pill, Source Badge, and Relative Time
          Row(
            children: [
              // Glowing State Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: accentColor.withValues(alpha: 0.6)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accentColor,
                        boxShadow: [
                          BoxShadow(
                            color: accentColor.withValues(alpha: 0.9),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isOn ? 'TURNED ON' : 'TURNED OFF',
                      style: AppTheme.heading(
                        size: 11,
                        color: accentColor,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Source Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceRaised,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(sourceIcon, size: 13, color: AppTheme.textSecondary),
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 120),
                      child: Text(
                        entry.source,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(size: 11, color: AppTheme.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Relative Time Tag
              Text(
                entry.relativeTime,
                style: AppTheme.mono(size: 10.5, color: AppTheme.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Bottom Row: Exact Timestamp and Runtime Duration Pill
          Row(
            children: [
              const Icon(Icons.access_time_rounded, size: 14, color: AppTheme.textSecondary),
              const SizedBox(width: 6),
              Text(
                entry.formattedDateTime,
                style: AppTheme.heading(size: 13, color: AppTheme.textPrimary, letterSpacing: 0.8),
              ),
              const Spacer(),

              // If Turn OFF event and duration recorded, show duration pill
              if (!isOn && entry.durationSeconds > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.gold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.gold.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.bolt_rounded, size: 13, color: AppTheme.gold),
                      const SizedBox(width: 3),
                      Text(
                        'Ran ${entry.formattedDuration}',
                        style: AppTheme.heading(size: 10.5, color: AppTheme.gold),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool isConnected) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.surfaceRaised,
              border: Border.all(color: AppTheme.border),
            ),
            child: const Icon(
              Icons.history_toggle_off_rounded,
              size: 42,
              color: AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'NO ACTIVITY LOGS YET',
            style: AppTheme.heading(size: 15, color: AppTheme.textSecondary, letterSpacing: 1.5),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              isConnected
                  ? 'Turn the lights ON and OFF or let scheduled routines trigger to view up to last 20 rolling activity logs from ESP32 storage.'
                  : 'Connect to your Temple Lights to synchronize and retrieve the last 20 on-off activity logs from on-chip flash memory.',
              textAlign: TextAlign.center,
              style: AppTheme.body(size: 12.5, color: AppTheme.textMuted),
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            icon: const Icon(Icons.sync_rounded, size: 18, color: Colors.white),
            label: Text('Sync from ESP32', style: AppTheme.heading(size: 12, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.amber,
              foregroundColor: Colors.white,
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
            onPressed: _syncLogs,
          ),
        ],
      ).animate().fadeIn(duration: 250.ms),
    );
  }
}
