import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/providers.dart';
import '../../ui/theme.dart';
import '../home/lights_screen.dart';
import '../logs/logs_screen.dart';
import '../modes/modes_screen.dart';
import '../scanner/device_sheet.dart';
import '../schedule/schedule_screen.dart';
import '../settings/settings_sheet.dart';

/// Main navigation shell hosting Lights (Control), Schedule, and Logs tabs.
class MainNavShell extends ConsumerStatefulWidget {
  const MainNavShell({super.key});

  @override
  ConsumerState<MainNavShell> createState() => _MainNavShellState();
}

class _MainNavShellState extends ConsumerState<MainNavShell> {
  int _currentIndex = 0;
  late final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(lightSessionProvider.notifier).startAutoDiscovery();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _openDevicePicker() {
    DevicePickerSheet.show(context);
  }

  void _openSettings() {
    SettingsSheet.show(context);
  }

  void _onTabSelected(int index) {
    setState(() => _currentIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOutCubic,
    );
  }

  String get _appBarTitle {
    switch (_currentIndex) {
      case 0:
        return 'TEMPLE LIGHTS';
      case 1:
        return 'BOOT MODES';
      case 2:
        return 'SCHEDULE ALARMS';
      case 3:
        return 'ACTIVITY LOGS';
      default:
        return 'TEMPLE LIGHTS';
    }
  }

  @override
  Widget build(BuildContext context) {
    final conn = ref.watch(lightSessionProvider);
    final light = ref.watch(lightControlProvider);

    final statusColor = conn.isConnected
        ? (light.isOn && light.brightness > 0 ? AppTheme.amber : AppTheme.cyan)
        : (conn.isReconnecting ? AppTheme.gold : AppTheme.red);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTheme.surfaceRaised,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.amber.withValues(alpha: 0.4)),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.amber.withValues(alpha: 0.15),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: Image.asset(
                  'assets/icons/temple_icon.png',
                  width: 32,
                  height: 32,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.temple_hindu_rounded, color: AppTheme.amber, size: 20),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _appBarTitle,
              style: AppTheme.heading(size: 15, letterSpacing: 1.8),
            ),
            const SizedBox(width: 8),
            // Live Status Indicator Dot
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: statusColor,
                boxShadow: [
                  BoxShadow(
                    color: statusColor.withValues(alpha: 0.8),
                    blurRadius: 5,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            if (conn.isConnected && conn.rssi != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceRaised,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  '${conn.rssi} dBm',
                  style: AppTheme.heading(size: 10, color: statusColor),
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.bluetooth_searching_rounded, color: AppTheme.amber),
            tooltip: 'Devices',
            onPressed: _openDevicePicker,
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded, color: AppTheme.textSecondary),
            tooltip: 'Settings',
            onPressed: _openSettings,
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: PageView(
        controller: _pageController,
        physics: const BouncingScrollPhysics(),
        onPageChanged: (index) => setState(() => _currentIndex = index),
        children: const [
          LightsScreen(),
          ModesScreen(),
          ScheduleScreen(),
          LogsScreen(),
        ],
      ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  Widget _buildBottomNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: const Border(
          top: BorderSide(color: AppTheme.border, width: 1.0),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B2E1E).withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
        left: 8,
        right: 8,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(
            index: 0,
            icon: Icons.lightbulb_rounded,
            label: 'LIGHTS',
          ),
          _buildNavItem(
            index: 1,
            icon: Icons.auto_awesome_rounded,
            label: 'MODES',
          ),
          _buildNavItem(
            index: 2,
            icon: Icons.alarm_rounded,
            label: 'SCHEDULE',
          ),
          _buildNavItem(
            index: 3,
            icon: Icons.receipt_long_rounded,
            label: 'LOGS',
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _currentIndex == index;

    return GestureDetector(
      onTap: () => _onTabSelected(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.surfaceRaised : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppTheme.amber.withValues(alpha: 0.5) : Colors.transparent,
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.amber.withValues(alpha: 0.12),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? AppTheme.amber : AppTheme.textMuted,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: AppTheme.heading(
                size: 11,
                color: isSelected ? AppTheme.amber : AppTheme.textMuted,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
