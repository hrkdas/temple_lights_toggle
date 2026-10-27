import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/haptics.dart';
import '../../domain/models.dart';
import '../../domain/providers.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/wifi_signal_icon.dart';

class WifiSetupSheet extends ConsumerStatefulWidget {
  const WifiSetupSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const WifiSetupSheet(),
    );
  }

  @override
  ConsumerState<WifiSetupSheet> createState() => _WifiSetupSheetState();
}

class _WifiSetupSheetState extends ConsumerState<WifiSetupSheet> {
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  WifiNetworkItem? _selectedNetwork;
  int _targetSlot = 1; // 1 = Primary, 2 = Backup

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Query status first without dropping connection
      ref.read(wifiProvider.notifier).requestStatus();

      // If user has no scan results cached, trigger a non-destructive scan
      final wifiState = ref.read(wifiProvider);
      if (wifiState.scannedNetworks.isEmpty && !wifiState.isScanning) {
        Future.delayed(const Duration(milliseconds: 250), () {
          if (mounted) {
            ref.read(wifiProvider.notifier).scanNetworks();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _onSelectNetwork(WifiNetworkItem network) {
    AppHaptics.light();
    final wifiState = ref.read(wifiProvider);

    // Auto-suggest optimal slot:
    // If Slot 1 is empty, default to Slot 1.
    // If Slot 1 is already configured, default to Slot 2 (Backup).
    int suggestedSlot = 1;
    if (wifiState.hasSlot1 && !wifiState.hasSlot2) {
      suggestedSlot = 2;
    } else if (wifiState.slot1?.ssid == network.ssid) {
      suggestedSlot = 1;
    } else if (wifiState.slot2?.ssid == network.ssid) {
      suggestedSlot = 2;
    }

    setState(() {
      _selectedNetwork = network;
      _targetSlot = suggestedSlot;
      _passwordController.clear();
    });
  }

  Future<void> _connect() async {
    final net = _selectedNetwork;
    if (net == null) return;

    final psk = _passwordController.text.trim();
    if (net.isSecured && psk.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter Wi-Fi password')),
      );
      return;
    }

    AppHaptics.medium();
    FocusScope.of(context).unfocus();
    await ref.read(wifiProvider.notifier).connect(
          ssid: net.ssid,
          psk: psk,
          slot: _targetSlot,
          save: true,
        );
  }

  Future<void> _confirmForgetSlot(int slot, String ssid) async {
    final slotName = (slot == 1) ? 'Primary (Slot 1)' : 'Backup (Slot 2)';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Forget $slotName?', style: AppTheme.heading(size: 18)),
        content: Text(
          'Remove "$ssid" from ESP32 memory? If an alternate network is configured, the device will seamlessly switch to it.',
          style: AppTheme.body(size: 14, color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: AppTheme.body(size: 14, color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Forget'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      AppHaptics.warn();
      await ref.read(wifiProvider.notifier).forget(slot: slot);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wifiState = ref.watch(wifiProvider);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 24,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.borderBright,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceGlow,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.amber.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.wifi_rounded, color: AppTheme.amber, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Temple Wi-Fi & Clock',
                        style: AppTheme.heading(size: 18),
                      ),
                      Text(
                        'Dual-Slot Auto-Failover & NTP Engine',
                        style: AppTheme.body(size: 12, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppTheme.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: AppTheme.border),

          // Scrollable Content
          Flexible(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              children: [
                // 1. Dual Saved Networks Dashboard (Slot 1 & Slot 2)
                _buildDualSlotsSection(wifiState),
                const SizedBox(height: 16),

                // 2. Active NTP Sync Banner (when connected to any slot)
                if (wifiState.isConnected) ...[
                  _buildNtpSyncBanner(wifiState),
                  const SizedBox(height: 16),
                ],

                // 3. In-flight Connection Progress Stepper
                if (wifiState.isConnecting) ...[
                  _buildConnectingStepper(wifiState),
                  const SizedBox(height: 16),
                ],

                // 4. Failure Error Banner
                if (wifiState.hasFailed) ...[
                  _buildFailureBanner(wifiState),
                  const SizedBox(height: 16),
                ],

                // 5. Password & Slot Assignment Card (if network selected)
                if (_selectedNetwork != null && !wifiState.isConnecting) ...[
                  _buildPasswordCard(wifiState),
                  const SizedBox(height: 16),
                ],

                // 6. Available Networks List (with Live Signal Range)
                _buildScannerSection(wifiState),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // DUAL SLOTS CARDS (SLOT 1 PRIMARY & SLOT 2 BACKUP AUTO-FAILOVER)
  // ==========================================================================

  Widget _buildDualSlotsSection(WifiConnectionState wifi) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Saved Wi-Fi Networks (Dual Auto-Failover)',
              style: AppTheme.heading(size: 14),
            ),
            if (wifi.hasAnySavedSlot)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${(wifi.hasSlot1 ? 1 : 0) + (wifi.hasSlot2 ? 1 : 0)} / 2 SAVED',
                  style: AppTheme.heading(size: 10, color: AppTheme.amber),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),

        // Slot 1: Primary
        _buildSlotCard(
          slotNumber: 1,
          slotTitle: 'SLOT 1 • PRIMARY NETWORK',
          slotItem: wifi.slot1,
          isActive: wifi.activeSlot == 1 && wifi.isConnected,
          wifi: wifi,
        ),
        const SizedBox(height: 10),

        // Slot 2: Backup Auto-Failover
        _buildSlotCard(
          slotNumber: 2,
          slotTitle: 'SLOT 2 • BACKUP (AUTO-FAILOVER)',
          slotItem: wifi.slot2,
          isActive: wifi.activeSlot == 2 && wifi.isConnected,
          wifi: wifi,
        ),
      ],
    );
  }

  Widget _buildSlotCard({
    required int slotNumber,
    required String slotTitle,
    required WifiSlotItem? slotItem,
    required bool isActive,
    required WifiConnectionState wifi,
  }) {
    final hasConfig = slotItem != null && slotItem.isConfigured && slotItem.ssid.isNotEmpty;
    final isConnected = wifi.isConnected;
    final effectiveRssi = isActive ? wifi.rssi : (slotItem?.rssi ?? 0);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive
              ? AppTheme.green.withValues(alpha: 0.4)
              : (hasConfig ? AppTheme.amber.withValues(alpha: 0.25) : AppTheme.border),
          width: isActive ? 1.5 : 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x083B2E1E),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isActive
                      ? AppTheme.green.withValues(alpha: 0.12)
                      : (hasConfig ? AppTheme.amber.withValues(alpha: 0.12) : AppTheme.surfaceRaised),
                  shape: BoxShape.circle,
                ),
                child: hasConfig
                    ? Center(
                        child: WifiSignalIcon(
                          rssi: effectiveRssi,
                          size: 18,
                          showQualityColor: isActive,
                          color: isActive ? AppTheme.green : (hasConfig ? AppTheme.amber : AppTheme.textMuted),
                        ),
                      )
                    : const Icon(Icons.wifi_off_rounded, size: 16, color: AppTheme.textMuted),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      slotTitle,
                      style: AppTheme.heading(
                        size: 10,
                        color: isActive ? AppTheme.green : (hasConfig ? AppTheme.amber : AppTheme.textMuted),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasConfig ? slotItem.ssid : 'Empty — Tap network below to assign',
                      style: AppTheme.heading(
                        size: 14,
                        color: hasConfig ? AppTheme.textPrimary : AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),

              // Status Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isActive
                          ? AppTheme.green
                          : (hasConfig ? AppTheme.amber : AppTheme.border))
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: (isActive
                            ? AppTheme.green
                            : (hasConfig ? AppTheme.amber : AppTheme.border))
                        .withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  isActive
                      ? 'ONLINE • ACTIVE'
                      : (hasConfig ? 'STANDBY' : 'EMPTY'),
                  style: AppTheme.heading(
                    size: 9,
                    color: isActive
                        ? AppTheme.green
                        : (hasConfig ? AppTheme.amber : AppTheme.textMuted),
                  ),
                ),
              ),
            ],
          ),

          // Subtitle / Telemetry
          if (hasConfig) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    isActive
                        ? 'IP: ${wifi.ipAddress} • Signal: ${wifi.rssi} dBm (${WifiSignalIcon.qualityLabelForRssi(wifi.rssi)})'
                        : (slotNumber == 1
                            ? 'Primary AP • Connected automatically on boot'
                            : 'Backup AP • Auto-connects if Slot 1 becomes unreachable'),
                    style: AppTheme.body(size: 11, color: AppTheme.textMuted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Slot Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!isActive && isConnected)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.amber,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                    label: Text(
                      'Switch to Slot $slotNumber',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      AppHaptics.light();
                      ref.read(wifiProvider.notifier).switchSlot(slotNumber);
                    },
                  ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.red,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 15),
                  label: const Text('Forget', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  onPressed: () => _confirmForgetSlot(slotNumber, slotItem.ssid),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ==========================================================================
  // NTP CLOCK SYNC BANNER
  // ==========================================================================

  Widget _buildNtpSyncBanner(WifiConnectionState wifi) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceGlow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.amber.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.access_time_rounded, size: 18, color: AppTheme.amber),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Autonomous Clock Active (SNTP)',
                  style: AppTheme.heading(size: 12, color: AppTheme.amber),
                ),
                Text(
                  'Schedules trigger accurately without phone connection.',
                  style: AppTheme.body(size: 11, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.amber,
              side: const BorderSide(color: AppTheme.amber),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              AppHaptics.light();
              ref.read(wifiProvider.notifier).triggerNtpSync();
            },
            child: const Text('Sync NTP', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // CONNECTING STEPPER
  // ==========================================================================

  Widget _buildConnectingStepper(WifiConnectionState wifi) {
    int currentStep = 1;
    if (wifi.phase == WifiPhase.gotIp) currentStep = 2;
    if (wifi.phase == WifiPhase.internetOk) currentStep = 3;
    if (wifi.phase == WifiPhase.saved || wifi.phase == WifiPhase.connected) currentStep = 4;

    final targetSlotText = wifi.activeSlot > 0 ? ' [Slot ${wifi.activeSlot}]' : '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceGlow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.amber.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.amber),
              ),
              const SizedBox(width: 10),
              Text(
                'Connecting to ${wifi.currentSsid}$targetSlotText…',
                style: AppTheme.heading(size: 14, color: AppTheme.amber),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildStepRow(1, 'Associating with 2.4 GHz Access Point', currentStep),
          _buildStepRow(2, 'Acquiring Local IP (DHCP Lease)', currentStep),
          _buildStepRow(3, 'Verifying Internet Access (HTTP 204 Probe)', currentStep),
          _buildStepRow(4, 'Synchronizing Clock with NTP Pool', currentStep),
        ],
      ),
    );
  }

  Widget _buildStepRow(int step, String label, int activeStep) {
    final isDone = activeStep > step;
    final isCurrent = activeStep == step;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            isDone
                ? Icons.check_circle_rounded
                : (isCurrent ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded),
            size: 16,
            color: isDone ? AppTheme.green : (isCurrent ? AppTheme.amber : AppTheme.textMuted),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: AppTheme.body(
                size: 12,
                color: isDone ? AppTheme.textPrimary : (isCurrent ? AppTheme.amber : AppTheme.textMuted),
                weight: isCurrent ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFailureBanner(WifiConnectionState wifi) {
    String msg = 'Failed to connect.';
    switch (wifi.failureReason) {
      case 'auth':
        msg = 'Incorrect Wi-Fi password. Please verify and try again.';
        break;
      case 'no_ap':
        msg = 'Wi-Fi network not found. Ensure router 2.4 GHz band is active.';
        break;
      case 'timeout':
        msg = 'Connection timed out. Router took too long to grant IP address.';
        break;
      case 'no_internet':
        msg = 'Connected to router, but HTTP 204 internet verification probe failed.';
        break;
      default:
        msg = 'Connection failed: ${wifi.failureReason}';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppTheme.red, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              msg,
              style: AppTheme.body(size: 12, color: AppTheme.red),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // PASSWORD INPUT & SLOT ASSIGNMENT CARD
  // ==========================================================================

  Widget _buildPasswordCard(WifiConnectionState wifi) {
    final net = _selectedNetwork!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.amber.withValues(alpha: 0.5)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12D97706),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              WifiSignalIcon(rssi: net.rssi, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Configure ${net.ssid}',
                  style: AppTheme.heading(size: 14),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18, color: AppTheme.textMuted),
                onPressed: () => setState(() => _selectedNetwork = null),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Slot Assignment Selector
          Text(
            'Assign To Slot:',
            style: AppTheme.body(size: 12, color: AppTheme.textSecondary, weight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: Text('Slot 1 (Primary)', style: TextStyle(fontSize: 12, fontWeight: _targetSlot == 1 ? FontWeight.bold : FontWeight.normal)),
                  selected: _targetSlot == 1,
                  selectedColor: AppTheme.amber.withValues(alpha: 0.25),
                  checkmarkColor: AppTheme.amber,
                  onSelected: (val) {
                    if (val) setState(() => _targetSlot = 1);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  label: Text('Slot 2 (Backup)', style: TextStyle(fontSize: 12, fontWeight: _targetSlot == 2 ? FontWeight.bold : FontWeight.normal)),
                  selected: _targetSlot == 2,
                  selectedColor: AppTheme.amber.withValues(alpha: 0.25),
                  checkmarkColor: AppTheme.amber,
                  onSelected: (val) {
                    if (val) setState(() => _targetSlot = 2);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (net.isSecured)
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              autofocus: true,
              style: AppTheme.body(size: 14),
              decoration: InputDecoration(
                hintText: 'Enter Wi-Fi Password',
                hintStyle: AppTheme.body(size: 14, color: AppTheme.textMuted),
                filled: true,
                fillColor: AppTheme.background,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppTheme.amber, width: 1.5),
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    color: AppTheme.textMuted,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            )
          else
            Text(
              'This is an Open network. No password required.',
              style: AppTheme.body(size: 13, color: AppTheme.textSecondary),
            ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.amber,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              onPressed: _connect,
              child: Text(
                'Connect & Save to Slot $_targetSlot',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // AVAILABLE NETWORKS SCANNER LIST (WITH LIVE SIGNAL RANGE)
  // ==========================================================================

  Widget _buildScannerSection(WifiConnectionState wifi) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Available 2.4 GHz Networks',
              style: AppTheme.heading(size: 14),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.amber,
                padding: EdgeInsets.zero,
              ),
              icon: wifi.isScanning
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.amber),
                    )
                  : const Icon(Icons.refresh_rounded, size: 16),
              label: Text(wifi.isScanning ? 'Scanning…' : 'Scan', style: const TextStyle(fontSize: 12)),
              onPressed: wifi.isScanning
                  ? null
                  : () {
                      AppHaptics.light();
                      ref.read(wifiProvider.notifier).scanNetworks();
                    },
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (wifi.isScanning && wifi.scannedNetworks.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 36),
            alignment: Alignment.center,
            child: Column(
              children: [
                const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.amber),
                ),
                const SizedBox(height: 12),
                Text(
                  'Scanning for nearby 2.4 GHz Wi-Fi…',
                  style: AppTheme.body(size: 13, color: AppTheme.textMuted),
                ),
              ],
            ),
          )
        else if (wifi.scannedNetworks.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              children: [
                const Icon(Icons.wifi_find_rounded, size: 36, color: AppTheme.textMuted),
                const SizedBox(height: 8),
                Text(
                  'No 2.4 GHz networks found',
                  style: AppTheme.heading(size: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap Scan above to search for nearby Wi-Fi APs.',
                  style: AppTheme.body(size: 12, color: AppTheme.textMuted),
                ),
              ],
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: wifi.scannedNetworks.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.border),
                itemBuilder: (ctx, i) {
                  final net = wifi.scannedNetworks[i];
                  final isSelected = _selectedNetwork?.ssid == net.ssid;
                  final isSlot1 = wifi.slot1?.ssid == net.ssid;
                  final isSlot2 = wifi.slot2?.ssid == net.ssid;

                  return InkWell(
                    onTap: () => _onSelectNetwork(net),
                    child: Container(
                      color: isSelected ? AppTheme.surfaceGlow : Colors.transparent,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          WifiSignalIcon(
                            rssi: net.rssi,
                            size: 20,
                            showQualityColor: true,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        net.ssid,
                                        style: AppTheme.heading(
                                          size: 14,
                                          color: isSelected ? AppTheme.amber : AppTheme.textPrimary,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isSlot1)
                                      Container(
                                        margin: const EdgeInsets.only(left: 6),
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: AppTheme.amber.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text('SLOT 1', style: AppTheme.heading(size: 9, color: AppTheme.amber)),
                                      ),
                                    if (isSlot2)
                                      Container(
                                        margin: const EdgeInsets.only(left: 6),
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: AppTheme.cyan.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text('SLOT 2', style: AppTheme.heading(size: 9, color: AppTheme.cyan)),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${net.auth} • ${net.rssi} dBm • ${net.signalQualityLabel}',
                                  style: AppTheme.body(size: 11, color: AppTheme.textMuted),
                                ),
                              ],
                            ),
                          ),
                          if (net.isSecured)
                            const Icon(Icons.lock_rounded, size: 16, color: AppTheme.textMuted),
                          const SizedBox(width: 6),
                          const Icon(Icons.chevron_right_rounded, size: 20, color: AppTheme.borderBright),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
