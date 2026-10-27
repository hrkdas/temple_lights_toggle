import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/providers.dart';
import '../../ui/theme.dart';
import '../home/lights_screen.dart';
import '../logs/logs_screen.dart';
import '../modes/modes_screen.dart';
import '../scanner/device_sheet.dart';
import '../schedule/schedule_screen.dart';
import '../settings/settings_sheet.dart';
import '../wifi/wifi_setup_sheet.dart';

/// Main navigation shell hosting Lights (Control), Schedule, and Logs tabs.
class MainNavShell extends ConsumerStatefulWidget {
  const MainNavShell({super.key});

  @override
  ConsumerState<MainNavShell> createState() => _MainNavShellState();
}

class _MainNavShellState extends ConsumerState<MainNavShell> with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  late final PageController _pageController = PageController();

  late final AnimationController _barsVisibilityController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: 1.0,
  );

  late final Animation<Offset> _appBarSlide = Tween<Offset>(
    begin: const Offset(0, -1.15),
    end: Offset.zero,
  ).animate(CurvedAnimation(
    parent: _barsVisibilityController,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  ));

  late final Animation<Offset> _bottomBarSlide = Tween<Offset>(
    begin: const Offset(0, 1.25),
    end: Offset.zero,
  ).animate(CurvedAnimation(
    parent: _barsVisibilityController,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  ));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(lightSessionProvider.notifier).startAutoDiscovery();
    });
  }

  @override
  void dispose() {
    _barsVisibilityController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  bool _barsVisible = true;

  void _showBars() {
    if (!_barsVisible || _barsVisibilityController.value < 1.0) {
      _barsVisible = true;
      _barsVisibilityController.animateTo(
        1.0,
        duration: const Duration(milliseconds: 450), // Smooth and slow return
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _hideBars() {
    if (_barsVisible || _barsVisibilityController.value > 0.0) {
      _barsVisible = false;
      _barsVisibilityController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 280), // Responsive exit
        curve: Curves.easeInCubic,
      );
    }
  }

  Color _signalColor(int rssi) {
    if (rssi >= -70) return AppTheme.green;
    if (rssi >= -85) return AppTheme.amber;
    return AppTheme.red;
  }

  void _openDevicePicker() {
    DevicePickerSheet.show(context);
  }

  void _openSettings() {
    SettingsSheet.show(context);
  }

  void _onTabSelected(int index) {
    _showBars();
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

    final activeDevice = ref.watch(activeDeviceProvider);

    final statusColor = conn.isConnected
        ? (light.isOn && light.brightness > 0 ? AppTheme.amber : AppTheme.cyan)
        : (conn.isReconnecting ? AppTheme.gold : AppTheme.red);

    return Scaffold(
      backgroundColor: AppTheme.background,
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: SlideTransition(
          position: _appBarSlide,
          child: FadeTransition(
            opacity: _barsVisibilityController,
            child: AnimatedBuilder(
              animation: _barsVisibilityController,
              builder: (context, child) => IgnorePointer(
                ignoring: _barsVisibilityController.value < 0.1,
                child: child,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.background.withValues(alpha: 0.92),
                  border: Border(
                    bottom: BorderSide(
                      color: AppTheme.border.withValues(alpha: 0.5),
                      width: 0.8,
                    ),
                  ),
                ),
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: AppBar(
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      scrolledUnderElevation: 0,
                      titleSpacing: 10,
                      title: InkWell(
                        onTap: _openDevicePicker,
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 28,
                                height: 28,
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
                                    width: 28,
                                    height: 28,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(Icons.temple_hindu_rounded, color: AppTheme.amber, size: 18),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  _currentIndex == 0 ? (activeDevice?.displayName ?? _appBarTitle) : _appBarTitle,
                                  style: AppTheme.heading(size: 13.5, letterSpacing: 0.8),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (_currentIndex == 0) ...[
                                const SizedBox(width: 2),
                                const Icon(Icons.arrow_drop_down_rounded, color: AppTheme.amber, size: 18),
                              ],
                              const SizedBox(width: 6),
                              // Live Status Indicator Dot
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: statusColor,
                                  boxShadow: [
                                    BoxShadow(
                                      color: statusColor.withValues(alpha: 0.8),
                                      blurRadius: 4,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                              ),
                              if (conn.isConnected && conn.rssi != null) ...[
                                const SizedBox(width: 5),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.surfaceRaised,
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(color: _signalColor(conn.rssi!).withValues(alpha: 0.4)),
                                  ),
                                  child: Text(
                                    '${conn.rssi} dBm',
                                    style: AppTheme.heading(size: 9.5, color: _signalColor(conn.rssi!)),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      actions: [
                        Consumer(
                          builder: (context, ref, _) {
                            final wifi = ref.watch(wifiProvider);
                            final isConnected = wifi.isConnected;
                            final isConnecting = wifi.isConnecting;
                            final iconColor = isConnected
                                ? AppTheme.green
                                : (isConnecting ? AppTheme.amber : AppTheme.textSecondary);
                            return IconButton(
                              iconSize: 20,
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                              icon: Icon(
                                isConnected ? Icons.wifi_rounded : (isConnecting ? Icons.wifi_find_rounded : Icons.wifi_rounded),
                                color: iconColor,
                              ),
                              tooltip: isConnected
                                  ? 'WiFi: ${wifi.currentSsid} (Tap to manage)'
                                  : (isConnecting ? 'Connecting to WiFi...' : 'Configure WiFi & Clock'),
                              onPressed: () => WifiSetupSheet.show(context),
                            );
                          },
                        ),
                        Consumer(
                          builder: (context, ref, _) {
                            final conn = ref.watch(lightSessionProvider);
                            final IconData bIcon;
                            final Color bColor;
                            final String bTooltip;

                            if (conn.isConnected) {
                              bIcon = Icons.bluetooth_connected_rounded;
                              bColor = AppTheme.amber;
                              bTooltip = 'Connected to ${conn.deviceName ?? "Temple Lights"}';
                            } else if (conn.isScanning || conn.isConnecting || conn.isReconnecting) {
                              bIcon = Icons.bluetooth_searching_rounded;
                              bColor = AppTheme.gold;
                              bTooltip = conn.isScanning ? 'Searching for lights...' : 'Reconnecting...';
                            } else {
                              bIcon = Icons.bluetooth_disabled_rounded;
                              bColor = AppTheme.textSecondary;
                              bTooltip = 'Disconnected (Tap to scan)';
                            }

                            return IconButton(
                              iconSize: 20,
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                              icon: Icon(bIcon, color: bColor),
                              tooltip: bTooltip,
                              onPressed: _openDevicePicker,
                            );
                          },
                        ),
                        IconButton(
                          iconSize: 20,
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                          constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                          icon: const Icon(Icons.tune_rounded, color: AppTheme.textSecondary),
                          tooltip: 'Settings',
                          onPressed: _openSettings,
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.axis == Axis.vertical) {
            if (notification.metrics.pixels <= 15.0) {
              _showBars();
            } else if (notification is ScrollUpdateNotification && notification.scrollDelta != null) {
              final delta = notification.scrollDelta!;
              if (delta > 3.0) {
                _hideBars();
              } else if (delta < -3.0) {
                _showBars();
              }
            } else if (notification is UserScrollNotification) {
              if (notification.direction == ScrollDirection.forward) {
                _showBars();
              } else if (notification.direction == ScrollDirection.reverse && notification.metrics.pixels > 20.0) {
                _hideBars();
              }
            }
          }
          return false;
        },
        child: PageView(
          controller: _pageController,
          physics: const BouncingScrollPhysics(),
          onPageChanged: (index) {
            _showBars();
            setState(() => _currentIndex = index);
          },
          children: const [
            LightsScreen(),
            ModesScreen(),
            ScheduleScreen(),
            LogsScreen(),
          ],
        ),
      ),
      bottomNavigationBar: SlideTransition(
        position: _bottomBarSlide,
        child: FadeTransition(
          opacity: _barsVisibilityController,
          child: AnimatedBuilder(
            animation: _barsVisibilityController,
            builder: (context, child) => IgnorePointer(
              ignoring: _barsVisibilityController.value < 0.1,
              child: child,
            ),
            child: _buildBottomNavBar(),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.94),
        border: const Border(
          top: BorderSide(color: AppTheme.border, width: 1.0),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B2E1E).withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Padding(
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
          ),
        ),
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
