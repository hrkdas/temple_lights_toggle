import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../contract/light_contract.dart';
import '../../core/haptics.dart';
import '../../domain/models.dart';
import '../../domain/providers.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/signal_bars.dart';
import 'widgets/glow_test_panel.dart';
import 'widgets/inline_device_rename_panel.dart';
import 'widgets/led_range_calibration_card.dart';
import 'widgets/unpair_confirm_dialog.dart';

/// Modal bottom sheet displaying deep hardware parameters, live telemetry,
/// test glow patterns, LED range metrology, rename panel, and unpair flow for a selected light.
class LightDetailSheet extends ConsumerStatefulWidget {
  const LightDetailSheet({
    super.key,
    required this.device,
  });

  final PairedDevice device;

  static Future<void> show(BuildContext context, PairedDevice device) {
    AppHaptics.selection();
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => LightDetailSheet(device: device),
    );
  }

  @override
  ConsumerState<LightDetailSheet> createState() => _LightDetailSheetState();
}

class _LightDetailSheetState extends ConsumerState<LightDetailSheet> {
  bool _isRenameExpanded = false;
  bool _isSwitching = false;

  String _formatLastSeen(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  String _estimateProximity(int rssi) {
    if (rssi >= -60) return '~0.5m • Immediate Proximity';
    if (rssi >= -72) return '~1.5m • Same Altar / Room';
    if (rssi >= -85) return '~4.0m • Across Mandir Room';
    return '~8.0m+ • Distant / Attenuated';
  }

  Color _signalColor(int? r) {
    if (r == null) return AppTheme.textMuted;
    if (r >= -72) return AppTheme.green;
    if (r >= -85) return AppTheme.amber;
    return AppTheme.red;
  }

  Future<void> _handleRename(PairedDevice currentDev, String newName) async {
    await ref.read(pairedDevicesProvider.notifier).updateCustomAlias(currentDev.id, newName);
    final conn = ref.read(lightSessionProvider);
    if (conn.isConnected && conn.deviceId == currentDev.id) {
      await ref.read(lightControlProvider.notifier).setDeviceName(newName);
    }
    setState(() => _isRenameExpanded = false);
  }

  Future<void> _handleUnpair(PairedDevice currentDev, bool isConnected) async {
    final confirmed = await UnpairConfirmDialog.show(
      context,
      deviceName: currentDev.displayName,
    );

    if (confirmed == true && mounted) {
      if (isConnected) {
        await ref.read(lightSessionProvider.notifier).disconnect();
      }
      await ref.read(pairedDevicesProvider.notifier).remove(currentDev.id);

      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.surfaceRaised,
            content: Text(
              'Unpaired "${currentDev.displayName}"',
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
            ),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Undo',
              textColor: AppTheme.amber,
              onPressed: () async {
                await ref.read(pairedDevicesProvider.notifier).upsertDevice(currentDev);
              },
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _switchConnection(PairedDevice currentDev) async {
    setState(() => _isSwitching = true);
    AppHaptics.medium();
    final session = ref.read(lightSessionProvider.notifier);
    await session.switchToDevice(currentDev.id, name: currentDev.displayName);
    if (mounted) {
      setState(() => _isSwitching = false);
    }
  }

  Future<void> _showCreateRoomDialog() async {
    final textController = TextEditingController();
    final createdName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Create New Room', style: AppTheme.heading(size: 16)),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'e.g. Balcony Mandir, Meditation Hall',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.amber),
            onPressed: () => Navigator.of(ctx).pop(textController.text.trim()),
            child: const Text('Create', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (createdName != null && createdName.isNotEmpty) {
      await ref.read(roomsProvider.notifier).addRoom(createdName);
      final updatedRooms = ref.read(roomsProvider);
      final newRoom = updatedRooms.last;
      await ref.read(roomsProvider.notifier).assignDeviceToRoom(widget.device.id, newRoom.id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final pairedList = ref.watch(pairedDevicesProvider);
    final connState = ref.watch(lightSessionProvider);
    final rooms = ref.watch(roomsProvider);

    // Read the most up-to-date representation of this device from paired list
    final device = pairedList.firstWhere(
      (d) => d.id == widget.device.id,
      orElse: () => widget.device,
    );

    final isCurrentlyConnected = connState.isConnected && connState.deviceId == device.id;
    final int? currentRssi = isCurrentlyConnected ? connState.rssi : null;
    final currentRoom = rooms.where((r) => r.id == device.effectiveRoomId).firstOrNull;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.92,
          ),
          decoration: BoxDecoration(
            color: AppTheme.surface.withValues(alpha: 0.98),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: AppTheme.border),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF3B2E1E).withValues(alpha: 0.12),
                blurRadius: 28,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Grab Handle
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4.5,
                decoration: BoxDecoration(
                  color: AppTheme.borderBright,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 12),

              // 2. Hero Header: Avatar, Name, Status Pill, Close
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    // Avatar with live status ring
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceRaised,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isCurrentlyConnected
                              ? AppTheme.green
                              : AppTheme.borderBright,
                          width: isCurrentlyConnected ? 2.0 : 1.2,
                        ),
                        boxShadow: isCurrentlyConnected
                            ? [
                                BoxShadow(
                                  color: AppTheme.green.withValues(alpha: 0.25),
                                  blurRadius: 10,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(
                          'assets/icons/temple_icon.png',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.temple_hindu_rounded,
                            color: AppTheme.amber,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Titles and IDs
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  device.displayName,
                                  style: AppTheme.heading(size: 16),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () {
                                  AppHaptics.selection();
                                  setState(() => _isRenameExpanded = !_isRenameExpanded);
                                },
                                borderRadius: BorderRadius.circular(6),
                                child: Padding(
                                  padding: const EdgeInsets.all(3.0),
                                  child: Icon(
                                    Icons.edit_rounded,
                                    size: 15,
                                    color: _isRenameExpanded ? AppTheme.amber : AppTheme.textMuted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${currentRoom?.iconEmoji ?? "🛕"} ${currentRoom?.name ?? "Puja Mandir"} • ${device.name} • ${device.id.length > 12 ? device.id.substring(0, 12) : device.id}',
                            style: AppTheme.body(size: 11, color: AppTheme.textMuted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Status Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isCurrentlyConnected
                            ? AppTheme.green.withValues(alpha: 0.15)
                            : AppTheme.surfaceRaised,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isCurrentlyConnected
                              ? AppTheme.green.withValues(alpha: 0.5)
                              : AppTheme.border,
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
                              color: isCurrentlyConnected ? AppTheme.green : AppTheme.textMuted,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isCurrentlyConnected ? 'ACTIVE' : 'STANDBY',
                            style: AppTheme.heading(
                              size: 10,
                              color: isCurrentlyConnected ? AppTheme.green : AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 22, color: AppTheme.textMuted),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Inline Rename Drawer
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: InlineDeviceRenamePanel(
                  initialName: device.displayName,
                  isExpanded: _isRenameExpanded,
                  onToggleExpand: () => setState(() => _isRenameExpanded = !_isRenameExpanded),
                  onCancel: () => setState(() => _isRenameExpanded = false),
                  onSave: (newName) => _handleRename(device, newName),
                ),
              ),

              const Divider(color: AppTheme.border, height: 16),

              // 3. Scrollable Parameter Sections
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Standby Connect Banner (if not currently connected)
                      if (!isCurrentlyConnected) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.amber.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppTheme.amber.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.bolt_rounded, size: 20, color: AppTheme.amber),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Target in Standby',
                                      style: AppTheme.heading(size: 12.5, color: AppTheme.textPrimary),
                                    ),
                                    Text(
                                      'Switch active Bluetooth link to control this light directly.',
                                      style: AppTheme.body(size: 10.5, color: AppTheme.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: _isSwitching ? null : () => _switchConnection(device),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.amber,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: _isSwitching
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : Text('Connect', style: AppTheme.heading(size: 11, color: Colors.white)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Section 1: Live Glow Test Studio
                      GlowTestPanel(
                        device: device,
                        isConnected: isCurrentlyConnected,
                        onConnectRequested: () => _switchConnection(device),
                      ),

                      const SizedBox(height: 14),

                      // Section 2: RF Signal Range & Telemetry Card
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceRaised,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.radar_rounded, size: 18, color: AppTheme.cyan),
                                const SizedBox(width: 8),
                                Text(
                                  'RF SIGNAL & PROXIMITY TELEMETRY',
                                  style: AppTheme.heading(size: 11, color: AppTheme.textMuted, letterSpacing: 1.1),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                SignalBars(
                                  rssi: currentRssi ?? -90,
                                  color: _signalColor(currentRssi),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      currentRssi != null ? '$currentRssi dBm' : 'Standby / Last Seen',
                                      style: AppTheme.heading(
                                        size: 13,
                                        color: _signalColor(currentRssi),
                                      ),
                                    ),
                                    Text(
                                      currentRssi != null
                                          ? _estimateProximity(currentRssi)
                                          : 'Last active ${_formatLastSeen(device.lastSeen)}',
                                      style: AppTheme.body(size: 10.5, color: AppTheme.textMuted),
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppTheme.surface,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: AppTheme.border),
                                  ),
                                  child: Text(
                                    device.firmwareVersion != null ? 'v${device.firmwareVersion}' : 'v${LightBleUuids.bundledFirmwareVersion}',
                                    style: AppTheme.mono(size: 10.5, color: AppTheme.textMuted),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Section 3: LED Range & Physical Calibration Card
                      LedRangeCalibrationCard(
                        device: device,
                        isConnected: isCurrentlyConnected,
                        onSaved: () => setState(() {}),
                      ),

                      const SizedBox(height: 14),

                      // Section 4: Spatial Room Assignment
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceRaised,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.meeting_room_rounded, size: 18, color: AppTheme.amber),
                                    const SizedBox(width: 8),
                                    Text(
                                      'ROOM ASSIGNMENT',
                                      style: AppTheme.heading(size: 11, color: AppTheme.textMuted, letterSpacing: 1.1),
                                    ),
                                  ],
                                ),
                                TextButton.icon(
                                  onPressed: _showCreateRoomDialog,
                                  icon: const Icon(Icons.add_rounded, size: 14, color: AppTheme.cyan),
                                  label: Text('New Room', style: AppTheme.heading(size: 11, color: AppTheme.cyan)),
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: rooms.map((room) {
                                final isSelected = room.id == device.effectiveRoomId;
                                return ChoiceChip(
                                  label: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(room.iconEmoji, style: const TextStyle(fontSize: 12)),
                                      const SizedBox(width: 6),
                                      Text(room.name),
                                    ],
                                  ),
                                  selected: isSelected,
                                  onSelected: (selected) async {
                                    if (selected) {
                                      AppHaptics.selection();
                                      await ref
                                          .read(roomsProvider.notifier)
                                          .assignDeviceToRoom(device.id, room.id);
                                      setState(() {});
                                    }
                                  },
                                  selectedColor: AppTheme.amber.withValues(alpha: 0.18),
                                  backgroundColor: AppTheme.surface,
                                  side: BorderSide(
                                    color: isSelected ? AppTheme.amber : AppTheme.border,
                                  ),
                                  labelStyle: AppTheme.heading(
                                    size: 11.5,
                                    color: isSelected ? AppTheme.amber : AppTheme.textSecondary,
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Section 5: Unpair Action Button
                      OutlinedButton.icon(
                        onPressed: () => _handleUnpair(device, isCurrentlyConnected),
                        icon: const Icon(Icons.link_off_rounded, size: 17, color: AppTheme.red),
                        label: Text(
                          'Unpair "${device.displayName}"',
                          style: AppTheme.heading(size: 12.5, color: AppTheme.red),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppTheme.red.withValues(alpha: 0.4), width: 1.2),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
