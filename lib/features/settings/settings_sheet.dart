import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../contract/light_contract.dart';
import '../../core/log.dart';
import '../../domain/providers.dart';
import '../../ui/theme.dart';
import '../ota/ota_update_screen.dart';

/// Settings modal sheet to adjust UUIDs, payload formats, auto-connect, and view logs.
class SettingsSheet extends ConsumerStatefulWidget {
  const SettingsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => const SettingsSheet(),
    );
  }

  @override
  ConsumerState<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends ConsumerState<SettingsSheet> {
  late final TextEditingController _serviceController;
  late final TextEditingController _charController;
  late final TextEditingController _nameFilterController;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _serviceController = TextEditingController(
      text: settings.customServiceUuid ?? LightBleUuids.defaultService,
    );
    _charController = TextEditingController(
      text: settings.customCharUuid ?? LightBleUuids.defaultControlChar,
    );
    _nameFilterController = TextEditingController(
      text: settings.nameFilter,
    );
  }

  @override
  void dispose() {
    _serviceController.dispose();
    _charController.dispose();
    _nameFilterController.dispose();
    super.dispose();
  }

  void _saveUuids() {
    final sText = _serviceController.text.trim();
    final cText = _charController.text.trim();
    ref.read(settingsProvider.notifier).setCustomUuids(
          serviceUuid: sText.isEmpty ? null : sText,
          charUuid: cText.isEmpty ? null : cText,
        );
  }

  void _showLogs() {
    final logs = AppLog.snapshot();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('BLE Debug Logs', style: AppTheme.heading(size: 18)),
        content: SizedBox(
          width: double.maxFinite,
          height: 360,
          child: logs.isEmpty
              ? Center(child: Text('No logs recorded yet', style: AppTheme.body(size: 14, color: AppTheme.textMuted)))
              : ListView.builder(
                  itemCount: logs.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      logs[i].formatted,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppTheme.textSecondary),
                    ),
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              AppLog.clear();
              Navigator.of(context).pop();
            },
            child: const Text('Clear', style: TextStyle(color: AppTheme.red)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close', style: TextStyle(color: AppTheme.cyan)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.40,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: ListView(
              controller: scrollController,
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

                // Title
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Configuration', style: AppTheme.heading(size: 20)),
                    IconButton(
                      icon: const Icon(Icons.receipt_long_rounded, color: AppTheme.gold),
                      tooltip: 'View Logs',
                      onPressed: _showLogs,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Auto-Connect Switch
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceRaised,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: SwitchListTile(
                    title: Text('Auto-Connect', style: AppTheme.heading(size: 15)),
                    subtitle: Text(
                      'Automatically connect to the nearest or last paired relay on startup',
                      style: AppTheme.body(size: 12, color: AppTheme.textSecondary),
                    ),
                    activeThumbColor: AppTheme.cyan,
                    value: settings.autoConnectEnabled,
                    onChanged: (val) {
                      ref.read(settingsProvider.notifier).setAutoConnect(val);
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // Communication Protocol Info Tile
                Text('BLE Protocol Mode', style: AppTheme.heading(size: 14, color: AppTheme.textSecondary)),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceRaised,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.border),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.flash_on_rounded, size: 20, color: AppTheme.amber),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'High-Speed JSON & 5-Byte Binary State Telemetry',
                          style: AppTheme.body(size: 12.5, color: AppTheme.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Name Filter Text Field
                Text('Device Name Filter', style: AppTheme.heading(size: 14, color: AppTheme.textSecondary)),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameFilterController,
                  style: AppTheme.body(size: 13),
                  decoration: InputDecoration(
                    hintText: 'e.g. Temple, Lights, ESP32 (Optional)',
                    hintStyle: AppTheme.body(size: 13, color: AppTheme.textMuted),
                    filled: true,
                    fillColor: AppTheme.surfaceRaised,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.cyan)),
                  ),
                  onChanged: (val) => ref.read(settingsProvider.notifier).setNameFilter(val.trim()),
                ),
                const SizedBox(height: 18),

                // GATT Custom Service UUID
                Text('GATT Service UUID', style: AppTheme.heading(size: 14, color: AppTheme.textSecondary)),
                const SizedBox(height: 8),
                TextField(
                  controller: _serviceController,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppTheme.surfaceRaised,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.cyan)),
                  ),
                  onChanged: (_) => _saveUuids(),
                ),
                const SizedBox(height: 14),

                // GATT Control Characteristic UUID
                Text('GATT Characteristic UUID', style: AppTheme.heading(size: 14, color: AppTheme.textSecondary)),
                const SizedBox(height: 8),
                TextField(
                  controller: _charController,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppTheme.surfaceRaised,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.cyan)),
                  ),
                  onChanged: (_) => _saveUuids(),
                ),
                const SizedBox(height: 12),

                // Reset to Default UUIDs Button
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.restore_rounded, size: 16, color: AppTheme.cyan),
                    label: Text('Reset to Default ESP32 UUIDs', style: AppTheme.heading(size: 12, color: AppTheme.cyan)),
                    onPressed: () {
                      _serviceController.text = LightBleUuids.defaultService;
                      _charController.text = LightBleUuids.defaultControlChar;
                      _saveUuids();
                    },
                  ),
                ),
                const SizedBox(height: 20),

                // Firmware & OTA Update Card
                Container(
                  padding: const EdgeInsets.all(16),
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
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.amber.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.system_update_rounded, size: 20, color: AppTheme.amber),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('ESP32 Firmware OTA', style: AppTheme.heading(size: 15)),
                                const SizedBox(height: 2),
                                Consumer(
                                  builder: (context, ref, _) {
                                    final light = ref.watch(lightControlProvider);
                                    final devVer = light.firmwareVersion != null ? 'v${light.firmwareVersion}' : 'v1.0.0';
                                    return Text(
                                      'Device: $devVer • Bundled: v${LightBleUuids.bundledFirmwareVersion}',
                                      style: AppTheme.mono(size: 11, color: AppTheme.textSecondary),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.download_rounded, size: 18, color: Colors.white),
                          label: Text('Open Firmware Updater', style: AppTheme.heading(size: 13, color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.amber,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 1,
                          ),
                          onPressed: () {
                            Navigator.of(context).pop();
                            OtaUpdateScreen.open(context);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // About Temple Lights Branding Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceRaised,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.amber.withValues(alpha: 0.5)),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.amber.withValues(alpha: 0.15),
                              blurRadius: 10,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(11),
                          child: Image.asset(
                            'assets/icons/temple_icon.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'TEMPLE LIGHTS TOGGLE',
                              style: AppTheme.heading(size: 15, letterSpacing: 1.5, color: AppTheme.amber),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Smart BLE RGB Light Strip Controller',
                              style: AppTheme.body(size: 11.5, color: AppTheme.textSecondary),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'v1.0.0 • Sacred Light Edition',
                              style: AppTheme.mono(size: 10.5, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
