import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../contract/light_contract.dart';
import '../../core/kv_store.dart';
import '../../domain/models.dart';
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

  Future<void> _switchTo(String id, String name) async {
    setState(() => _connectingId = id);
    final session = ref.read(lightSessionProvider.notifier);
    await session.switchToDevice(id, name: name);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _connect(ScannedDevice device) async {
    await _connectRaw(device.id, device.name);
  }

  Future<void> _showRenameDialog(BuildContext context, PairedDevice device) async {
    final textController = TextEditingController(text: device.displayName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Rename Temple Light', style: AppTheme.heading(size: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Assign a friendly room name (e.g. Puja Room, Mandir Altar, Living Room):',
              style: AppTheme.body(size: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              autofocus: true,
              maxLength: 32,
              decoration: InputDecoration(
                hintText: 'e.g. Puja Room Shrine',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.amber, width: 2),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: AppTheme.body(size: 13, color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.amber,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.of(ctx).pop(textController.text.trim()),
            child: Text('Save Name', style: AppTheme.heading(size: 13, color: Colors.white)),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty) {
      await ref.read(pairedDevicesProvider.notifier).updateCustomAlias(device.id, newName);
      final conn = ref.read(lightSessionProvider);
      if (conn.isConnected && conn.deviceId == device.id) {
        await ref.read(lightControlProvider.notifier).setDeviceName(newName);
      }
    }
  }

  Future<void> _showRoomAssignmentDialog(BuildContext context, PairedDevice device) async {
    final rooms = ref.read(roomsProvider);
    String selectedRoomId = device.effectiveRoomId;

    final newRoomId = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.meeting_room_rounded, color: AppTheme.amber, size: 22),
              const SizedBox(width: 8),
              Text('Assign Room', style: AppTheme.heading(size: 17)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Assign "${device.displayName}" to a room to control multiple devices together:',
                style: AppTheme.body(size: 13, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 12),
              ...rooms.map((room) {
                final isSelected = selectedRoomId == room.id;
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setDlgState(() => selectedRoomId = room.id),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.amber.withValues(alpha: 0.15) : AppTheme.surfaceRaised,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? AppTheme.amber : AppTheme.border,
                        width: isSelected ? 1.6 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(room.iconEmoji, style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(room.name, style: AppTheme.heading(size: 13.5)),
                        ),
                        if (isSelected)
                          const Icon(Icons.check_circle_rounded, color: AppTheme.amber, size: 20),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.add_rounded, size: 16, color: AppTheme.cyan),
                  label: Text('Create New Room', style: AppTheme.heading(size: 12, color: AppTheme.cyan)),
                  onPressed: () async {
                    final nameCtrl = TextEditingController();
                    final created = await showDialog<String>(
                      context: ctx,
                      builder: (c2) => AlertDialog(
                        backgroundColor: AppTheme.surface,
                        title: Text('New Room Name', style: AppTheme.heading(size: 16)),
                        content: TextField(
                          controller: nameCtrl,
                          autofocus: true,
                          decoration: const InputDecoration(hintText: 'e.g. Guest Room, Balcony'),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.of(c2).pop(), child: const Text('Cancel')),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.amber),
                            onPressed: () => Navigator.of(c2).pop(nameCtrl.text.trim()),
                            child: const Text('Create', style: TextStyle(color: Colors.black)),
                          ),
                        ],
                      ),
                    );
                    if (created != null && created.isNotEmpty) {
                      await ref.read(roomsProvider.notifier).addRoom(created);
                      setDlgState(() {
                        final updatedRooms = ref.read(roomsProvider);
                        selectedRoomId = updatedRooms.last.id;
                      });
                    }
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel', style: AppTheme.body(size: 13, color: AppTheme.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.amber,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.of(ctx).pop(selectedRoomId),
              child: Text('Assign', style: AppTheme.heading(size: 13, color: Colors.black)),
            ),
          ],
        ),
      ),
    );

    if (newRoomId != null) {
      await ref.read(roomsProvider.notifier).assignDeviceToRoom(device.id, newRoomId);
      if (context.mounted) {
        final room = ref.read(roomsProvider).where((r) => r.id == newRoomId).firstOrNull;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Assigned "${device.displayName}" to ${room?.name ?? newRoomId}'),
            backgroundColor: AppTheme.green,
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scanner = ref.watch(scannerProvider);
    final paired = ref.watch(pairedDevicesProvider);
    final rooms = ref.watch(roomsProvider);
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
                            final room = rooms.where((r) => r.id == p.effectiveRoomId).firstOrNull;

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
                                title: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            p.displayName,
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
                                        if (p.firmwareVersion != null && p.firmwareVersion != LightBleUuids.bundledFirmwareVersion) ...[
                                          const SizedBox(width: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppTheme.amber.withValues(alpha: 0.2),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: AppTheme.amber.withValues(alpha: 0.4)),
                                            ),
                                            child: Text(
                                              'UPDATE',
                                              style: AppTheme.heading(size: 8, color: AppTheme.amber),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    Wrap(
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      spacing: 6,
                                      children: [
                                        if (p.customAlias != null && p.customAlias!.isNotEmpty && p.customAlias != p.name)
                                          Text(
                                            '${p.name} • ${p.effectiveLedCount} LEDs (${p.formattedLength})',
                                            style: AppTheme.body(size: 10.5, color: AppTheme.textMuted),
                                          )
                                        else
                                          Text(
                                            '${p.effectiveLedCount} LEDs (${p.formattedLength})',
                                            style: AppTheme.body(size: 10.5, color: AppTheme.textMuted),
                                          ),
                                        InkWell(
                                          onTap: () => _showRoomAssignmentDialog(context, p),
                                          borderRadius: BorderRadius.circular(6),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                            decoration: BoxDecoration(
                                              color: AppTheme.surface,
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: AppTheme.amber.withValues(alpha: 0.35)),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(room?.iconEmoji ?? '🛕', style: const TextStyle(fontSize: 9.5)),
                                                const SizedBox(width: 4),
                                                Text(room?.name ?? 'Puja Mandir', style: AppTheme.heading(size: 9.5, color: AppTheme.amber)),
                                                const SizedBox(width: 2),
                                                const Icon(Icons.arrow_drop_down, size: 12, color: AppTheme.textMuted),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
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
                                        const Icon(Icons.portable_wifi_off_rounded, size: 14, color: AppTheme.textMuted),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Offline / Standby',
                                          style: AppTheme.body(size: 11, color: AppTheme.textMuted),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isCurrentlyConnected) ...[
                                      IconButton(
                                        icon: const Icon(Icons.lightbulb_outline_rounded, color: AppTheme.amber, size: 20),
                                        tooltip: 'Blink to Identify',
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                        onPressed: () async {
                                          await ref.read(lightControlProvider.notifier).identifyDevice();
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('Blinking "${p.displayName}" 3 times to identify...'),
                                                duration: const Duration(seconds: 2),
                                                behavior: SnackBarBehavior.floating,
                                              ),
                                            );
                                          }
                                        },
                                      ),
                                    ],
                                    IconButton(
                                      icon: const Icon(Icons.drive_file_rename_outline_rounded, color: AppTheme.textSecondary, size: 18),
                                      tooltip: 'Rename',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                      onPressed: () => _showRenameDialog(context, p),
                                    ),
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
                                          padding: const EdgeInsets.symmetric(horizontal: 10),
                                          minimumSize: const Size(54, 30),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ),
                                        onPressed: _connectingId == null ? () => _switchTo(p.id, p.displayName) : null,
                                        child: Text(
                                          'Switch',
                                          style: AppTheme.heading(size: 11, color: Colors.white),
                                        ),
                                      ),
                                    const SizedBox(width: 2),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.textMuted, size: 18),
                                      tooltip: 'Unpair',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
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
