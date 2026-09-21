import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../contract/light_contract.dart';
import '../../core/kv_store.dart';
import '../../domain/providers.dart';
import '../../transport/scanner.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/radar_sweep.dart';
import '../../ui/widgets/signal_bars.dart';

/// Modal bottom sheet displaying real-time discovered BLE devices with 1-tap connection.
class DevicePickerSheet extends ConsumerStatefulWidget {
  const DevicePickerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => const DevicePickerSheet(),
    );
  }

  @override
  ConsumerState<DevicePickerSheet> createState() => _DevicePickerSheetState();
}

class _DevicePickerSheetState extends ConsumerState<DevicePickerSheet> {
  String? _connectingId;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    final conn = ref.read(lightSessionProvider);
    if (conn.isConnected) {
      ref.read(scannerProvider).stop();
    }
    super.dispose();
  }

  void _startScan() {
    final scanner = ref.read(scannerProvider);
    scanner.start();
  }

  Future<void> _connectRaw(String id, String name) async {
    setState(() => _connectingId = id);
    final session = ref.read(lightSessionProvider.notifier);
    await session.connect(id, name: name);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _connect(ScannedDevice device) async {
    await _connectRaw(device.id, device.name);
  }

  @override
  Widget build(BuildContext context) {
    final scanner = ref.watch(scannerProvider);
    final paired = ref.watch(pairedDevicesProvider);
    final kv = ref.watch(kvStoreProvider);
    final lastConnectedId = kv.getString(KvKeys.lastConnectedId);
    final connState = ref.watch(lightSessionProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.80,
      minChildSize: 0.40,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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

              // Title and Refresh Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Device Manager',
                        style: AppTheme.heading(size: 20),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Pair multiple relays and manage auto-connect',
                        style: AppTheme.body(size: 13, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: AppTheme.cyan),
                    tooltip: 'Rescan',
                    onPressed: () {
                      final s = ref.read(scannerProvider);
                      s.stop().then((_) => s.start());
                    },
                  ),
                ],
              ),
              const SizedBox(height: 14),

              Expanded(
                child: StreamBuilder<List<ScannedDevice>>(
                  stream: scanner.stream,
                  initialData: const [],
                  builder: (context, snapshot) {
                    final scannedDevices = snapshot.data ?? const [];

                    return ListView(
                      controller: scrollController,
                      children: [
                        // Section 1: Paired Devices
                        if (paired.isNotEmpty) ...[
                          Text(
                            'PAIRED DEVICES (${paired.length})',
                            style: AppTheme.heading(size: 12, color: AppTheme.textSecondary, letterSpacing: 1.2),
                          ),
                          const SizedBox(height: 8),
                          ...paired.map((p) {
                            final isLastConnected = p.id == lastConnectedId;
                            final scannedDev = scannedDevices.where((d) => d.id == p.id).firstOrNull;
                            final isCurrentlyConnected = connState.isConnected && connState.deviceId == p.id;
                            final isConnecting = _connectingId == p.id || (connState.isConnecting && connState.deviceId == p.id);

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceRaised,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isCurrentlyConnected
                                      ? AppTheme.green.withValues(alpha: 0.7)
                                      : isLastConnected
                                          ? AppTheme.cyan.withValues(alpha: 0.6)
                                          : AppTheme.border,
                                  width: 1.2,
                                ),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                                leading: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: AppTheme.surface,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: AppTheme.border),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(9),
                                    child: Image.asset(
                                      'assets/icons/temple_icon.png',
                                      width: 44,
                                      height: 44,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        p.name,
                                        style: AppTheme.heading(size: 15),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isCurrentlyConnected)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTheme.green.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'ACTIVE',
                                          style: AppTheme.heading(size: 9, color: AppTheme.green),
                                        ),
                                      )
                                    else if (isLastConnected)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTheme.cyan.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'AUTO-TARGET',
                                          style: AppTheme.heading(size: 9, color: AppTheme.cyan),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Row(
                                    children: [
                                      if (isCurrentlyConnected && connState.rssi != null) ...[
                                        SignalBars(rssi: connState.rssi!, color: AppTheme.green),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${connState.rssi} dBm • Connected',
                                          style: AppTheme.body(size: 11, color: AppTheme.green),
                                        ),
                                      ] else if (scannedDev != null) ...[
                                        SignalBars(rssi: scannedDev.rssi),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${scannedDev.rssi} dBm • In Range',
                                          style: AppTheme.body(size: 11, color: AppTheme.textSecondary),
                                        ),
                                      ] else ...[
                                        Icon(Icons.portable_wifi_off_rounded, size: 14, color: AppTheme.textMuted),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Offline / Not in range',
                                          style: AppTheme.body(size: 11, color: AppTheme.textMuted),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isConnecting)
                                      const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          valueColor: AlwaysStoppedAnimation(AppTheme.cyan),
                                        ),
                                      )
                                    else if (!isCurrentlyConnected)
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.amber,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 12),
                                          minimumSize: const Size(58, 32),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ),
                                        onPressed: _connectingId == null ? () => _connectRaw(p.id, p.name) : null,
                                        child: Text(
                                          'Connect',
                                          style: AppTheme.heading(size: 11, color: Colors.white),
                                        ),
                                      ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.textMuted, size: 20),
                                      tooltip: 'Unpair',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                      onPressed: () async {
                                        await ref.read(pairedDevicesProvider.notifier).remove(p.id);
                                        if (isCurrentlyConnected) {
                                          await ref.read(lightSessionProvider.notifier).disconnect();
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                          const SizedBox(height: 16),
                        ],

                        // Section 2: Discovered BLE Devices
                        Text(
                          'DISCOVER NEW DEVICES',
                          style: AppTheme.heading(size: 12, color: AppTheme.textSecondary, letterSpacing: 1.2),
                        ),
                        const SizedBox(height: 8),

                        if (scannedDevices.isEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const RadarSweep(size: 120),
                                const SizedBox(height: 14),
                                Text(
                                  'Scanning for nearby BLE devices...',
                                  style: AppTheme.body(size: 13, color: AppTheme.textSecondary),
                                ),
                              ],
                            ),
                          )
                        else
                          ...scannedDevices.map((dev) {
                            final isConnecting = _connectingId == dev.id;
                            final isPaired = paired.any((p) => p.id == dev.id);
                            final isTarget = LightBleUuids.isTargetRelayDevice(
                              name: dev.name,
                              serviceUuids: dev.serviceUuids.map((u) => u.toString()).toList(),
                            );

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceRaised,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isPaired
                                      ? AppTheme.gold.withValues(alpha: 0.6)
                                      : isTarget
                                          ? AppTheme.cyan.withValues(alpha: 0.6)
                                          : AppTheme.border,
                                  width: 1,
                                ),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                                leading: Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: AppTheme.surface,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: AppTheme.border),
                                  ),
                                  child: isTarget
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(9),
                                          child: Image.asset(
                                            'assets/icons/temple_icon.png',
                                            width: 44,
                                            height: 44,
                                            fit: BoxFit.cover,
                                          ),
                                        )
                                      : Icon(
                                          Icons.bluetooth_searching_rounded,
                                          color: isPaired
                                              ? AppTheme.gold
                                              : AppTheme.textSecondary,
                                          size: 24,
                                        ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        dev.name,
                                        style: AppTheme.heading(size: 15),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isPaired)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTheme.gold.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'PAIRED',
                                          style: AppTheme.heading(size: 9, color: AppTheme.gold),
                                        ),
                                      )
                                    else if (isTarget)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTheme.cyan.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'TARGET',
                                          style: AppTheme.heading(size: 9, color: AppTheme.cyan),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Row(
                                    children: [
                                      SignalBars(rssi: dev.rssi),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${dev.rssi} dBm  •  ${dev.id.substring(0, dev.id.length > 12 ? 12 : dev.id.length)}',
                                        style: AppTheme.body(size: 11, color: AppTheme.textMuted),
                                      ),
                                    ],
                                  ),
                                ),
                                trailing: isConnecting
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          valueColor: AlwaysStoppedAnimation(AppTheme.cyan),
                                        ),
                                      )
                                    : ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppTheme.amber,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 14),
                                          minimumSize: const Size(64, 34),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ),
                                        onPressed: _connectingId == null ? () => _connect(dev) : null,
                                        child: Text(
                                          'Connect',
                                          style: AppTheme.heading(size: 12, color: Colors.white),
                                        ),
                                      ),
                              ),
                            )
                                .animate()
                                .fadeIn(duration: 200.ms)
                                .slideY(begin: 0.1, end: 0, duration: 200.ms);
                          }),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
