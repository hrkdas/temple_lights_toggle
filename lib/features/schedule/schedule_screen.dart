import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/models.dart';
import '../../domain/providers.dart';
import '../../ui/theme.dart';
import 'schedule_editor_sheet.dart';

/// Screen managing alarm-style schedules for automatic Temple Lights ON and OFF routines.
class ScheduleScreen extends ConsumerWidget {
  const ScheduleScreen({super.key});

  void _openEditor(BuildContext context, [LightSchedule? schedule]) {
    ScheduleEditorSheet.show(context, schedule: schedule);
  }

  Color _getModeColor(LightSchedule schedule) {
    switch (schedule.targetMode) {
      case 0:
        return const Color(0xFFFF9329); // Warm Amber
      case 1:
        return const Color(0xFFD97706); // Center Warm Amber
      case 2:
        return Colors.white;            // Pure White
      case 3:
        return Color.fromARGB(255, schedule.targetR, schedule.targetG, schedule.targetB);
      default:
        return AppTheme.amber;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedules = ref.watch(schedulesProvider);
    final notifier = ref.read(schedulesProvider.notifier);
    final activeCount = schedules.where((s) => s.isEnabled).length;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Status Telemetry Banner with sync button
              _buildHeaderBanner(activeCount, schedules.length, notifier),
              const SizedBox(height: 16),

              // 2. Main Alarm Cards List with Pull-to-Refresh from ESP32
              Expanded(
                child: schedules.isEmpty
                    ? RefreshIndicator(
                        color: AppTheme.amber,
                        backgroundColor: AppTheme.surfaceRaised,
                        onRefresh: () async {
                          await notifier.requestHydrationFromDevice();
                          await Future.delayed(const Duration(milliseconds: 400));
                        },
                        child: ListView(
                          children: [
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.55,
                              child: _buildEmptyState(context),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        color: AppTheme.amber,
                        backgroundColor: AppTheme.surfaceRaised,
                        onRefresh: () async {
                          await notifier.requestHydrationFromDevice();
                          await Future.delayed(const Duration(milliseconds: 400));
                        },
                        child: ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: schedules.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final schedule = schedules[index];
                            return _buildScheduleCard(context, schedule, notifier)
                                .animate()
                                .fadeIn(duration: 200.ms, delay: (index * 60).ms)
                                .slideY(begin: 0.1, end: 0, duration: 200.ms);
                          },
                        ),
                      ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.amber,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.add_alarm_rounded, size: 20, color: Colors.white),
        label: Text(
          'NEW ROUTINE',
          style: AppTheme.heading(size: 13, color: Colors.white, letterSpacing: 1.2),
        ),
        onPressed: () => _openEditor(context),
      ).animate().scale(delay: 200.ms, curve: Curves.easeOutBack),
    );
  }

  Widget _buildHeaderBanner(int activeCount, int totalCount, ScheduleNotifier notifier) {
    final hasActive = activeCount > 0;
    final bannerColor = hasActive ? AppTheme.amber : AppTheme.textMuted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: bannerColor.withValues(alpha: hasActive ? 0.4 : 0.2),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: bannerColor.withValues(alpha: hasActive ? 0.08 : 0.01),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: bannerColor.withValues(alpha: hasActive ? 0.15 : 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.schedule_rounded,
              color: bannerColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'ROUTINE SCHEDULER',
                      style: AppTheme.heading(size: 12, color: bannerColor, letterSpacing: 1.2),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceRaised,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$activeCount / $totalCount ACTIVE',
                        style: AppTheme.heading(size: 10, color: hasActive ? AppTheme.green : AppTheme.textMuted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  hasActive
                      ? 'Automatic clock triggers will activate lights per schedule'
                      : 'No active routines. Enable or create a schedule timer below',
                  style: AppTheme.body(size: 11.5, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.sync_rounded, size: 20, color: AppTheme.amber),
            tooltip: 'Sync routines from ESP32 memory',
            onPressed: () => notifier.requestHydrationFromDevice(),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleCard(
    BuildContext context,
    LightSchedule schedule,
    ScheduleNotifier notifier,
  ) {
    final isEnabled = schedule.isEnabled;
    final modeColor = _getModeColor(schedule);

    return Dismissible(
      key: Key(schedule.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppTheme.red.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.delete_forever_rounded, color: Colors.white, size: 28),
      ),
      onDismissed: (_) => notifier.deleteSchedule(schedule.id),
      child: GestureDetector(
        onTap: () => _openEditor(context, schedule),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isEnabled ? AppTheme.amber.withValues(alpha: 0.4) : AppTheme.border,
              width: 1.2,
            ),
            boxShadow: isEnabled
                ? [
                    BoxShadow(
                      color: AppTheme.amber.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Label & Enable Switch
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isEnabled ? AppTheme.amber : AppTheme.textMuted,
                      boxShadow: isEnabled
                          ? [
                              BoxShadow(
                                color: AppTheme.amber.withValues(alpha: 0.8),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      schedule.name,
                      style: AppTheme.heading(
                        size: 15,
                        color: isEnabled ? AppTheme.textPrimary : AppTheme.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Switch(
                    value: isEnabled,
                    activeThumbColor: AppTheme.amber,
                    onChanged: (val) => notifier.toggleSchedule(schedule.id, val),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Row 2: Digital Alarm Times (Turn ON and Turn OFF)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceRaised,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    // Turn ON Time
                    if (schedule.hasTurnOn) ...[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppTheme.green,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'ON',
                                style: AppTheme.heading(
                                  size: 10,
                                  color: isEnabled ? AppTheme.green : AppTheme.textMuted,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            schedule.formattedTurnOnTime,
                            style: AppTheme.heading(
                              size: 20,
                              color: isEnabled ? AppTheme.textPrimary : AppTheme.textMuted,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      Text('No ON action', style: AppTheme.body(size: 12, color: AppTheme.textMuted)),
                    ],

                    // Divider Arrow
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 16,
                      color: isEnabled ? AppTheme.textSecondary : AppTheme.textMuted,
                    ),

                    // Turn OFF Time
                    if (schedule.hasTurnOff) ...[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppTheme.orange,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'OFF',
                                style: AppTheme.heading(
                                  size: 10,
                                  color: isEnabled ? AppTheme.orange : AppTheme.textMuted,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            schedule.formattedTurnOffTime,
                            style: AppTheme.heading(
                              size: 20,
                              color: isEnabled ? AppTheme.textPrimary : AppTheme.textMuted,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      Text('No OFF action', style: AppTheme.body(size: 12, color: AppTheme.textMuted)),
                    ],
                  ],
                ),
              ),

              // Row 3: Activation Lighting Details (Mode, Color & Brightness)
              if (schedule.hasTurnOn) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceRaised,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: modeColor,
                          border: Border.all(
                            color: (modeColor == Colors.white) ? AppTheme.borderBright : Colors.transparent,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: modeColor.withValues(alpha: 0.5),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        schedule.targetModeName,
                        style: AppTheme.heading(
                          size: 11,
                          color: isEnabled ? AppTheme.textPrimary : AppTheme.textMuted,
                        ),
                      ),
                      const Spacer(),
                      Icon(Icons.brightness_medium_rounded, size: 13, color: isEnabled ? AppTheme.amber : AppTheme.textMuted),
                      const SizedBox(width: 4),
                      Text(
                        '${schedule.targetBrightnessPercent}%',
                        style: AppTheme.heading(
                          size: 11,
                          color: isEnabled ? AppTheme.amber : AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),

              // Row 4: Repeat Days Summary
              Row(
                children: [
                  Icon(Icons.repeat_rounded, size: 14, color: isEnabled ? AppTheme.amber : AppTheme.textMuted),
                  const SizedBox(width: 6),
                  Text(
                    schedule.repeatDaysSummary,
                    style: AppTheme.body(
                      size: 11.5,
                      color: isEnabled ? AppTheme.textSecondary : AppTheme.textMuted,
                      weight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppTheme.textMuted,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.surfaceRaised,
              border: Border.all(color: AppTheme.border),
            ),
            child: const Icon(
              Icons.alarm_off_rounded,
              size: 44,
              color: AppTheme.textMuted,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'NO ROUTINES CREATED',
            style: AppTheme.heading(size: 15, color: AppTheme.textSecondary, letterSpacing: 1.5),
          ),
          const SizedBox(height: 6),
          Text(
            'Create a schedule routine to automate when your\nTemple Lights turn ON and OFF automatically.',
            textAlign: TextAlign.center,
            style: AppTheme.body(size: 12.5, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            icon: const Icon(Icons.add_alarm_rounded, size: 18, color: Colors.white),
            label: Text('Create First Routine', style: AppTheme.heading(size: 12, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.amber,
              foregroundColor: Colors.white,
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
            onPressed: () => _openEditor(context),
          ),
        ],
      ),
    );
  }
}
