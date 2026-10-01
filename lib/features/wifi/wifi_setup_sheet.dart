import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/haptics.dart';
import '../../domain/models.dart';
import '../../domain/providers.dart';
import '../../ui/theme.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final wifiState = ref.read(wifiProvider);
      ref.read(wifiProvider.notifier).requestStatus();
      if (!wifiState.isConnected && wifiState.scannedNetworks.isEmpty) {
        ref.read(wifiProvider.notifier).scanNetworks();
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
    setState(() {
      _selectedNetwork = network;
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
          save: true,
        );
  }

  Future<void> _confirmForget() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Forget Wi-Fi Network?', style: AppTheme.heading(size: 18)),
        content: Text(
          'The ESP32 will disconnect from this network and erase saved credentials. Autonomous NTP clock sync will be disabled until reconnected.',
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
      await ref.read(wifiProvider.notifier).forget();
    }
  }

  @override
  Widget build(BuildContext context) {
    final wifiState = ref.watch(wifiProvider);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
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
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceGlow,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.amber.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.wifi_rounded, color: AppTheme.amber, size: 20),
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
                        'Autonomous 2.4 GHz SNTP Synchronizer',
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
                // 1. Current Network Status Card
                _buildActiveConnectionCard(wifiState),
                const SizedBox(height: 16),

                // 2. Connection Progress Stepper
                if (wifiState.isConnecting) ...[
                  _buildConnectingStepper(wifiState),
                  const SizedBox(height: 16),
                ],

                // 3. Failure Error Banner
                if (wifiState.hasFailed) ...[
                  _buildFailureBanner(wifiState),
                  const SizedBox(height: 16),
                ],

                // 4. Password Input Sheet (if a network is tapped)
                if (_selectedNetwork != null && !wifiState.isConnecting) ...[
                  _buildPasswordCard(),
                  const SizedBox(height: 16),
                ],

                // 5. Available Networks List
                _buildScannerSection(wifiState),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveConnectionCard(WifiConnectionState wifi) {
    final isConn = wifi.isConnected;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isConn ? AppTheme.green.withValues(alpha: 0.35) : AppTheme.border,
          width: 1.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A3B2E1E),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isConn ? AppTheme.green.withValues(alpha: 0.12) : AppTheme.surfaceRaised,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isConn ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                  color: isConn ? AppTheme.green : AppTheme.textMuted,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isConn ? wifi.currentSsid : 'No Active Wi-Fi Connection',
                      style: AppTheme.heading(size: 15),
                    ),
                    Text(
                      isConn ? 'IP: ${wifi.ipAddress} • RSSI: ${wifi.rssi} dBm' : 'ESP32 clock running on offline BLE time',
                      style: AppTheme.body(size: 12, color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isConn ? AppTheme.green : AppTheme.textMuted).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: (isConn ? AppTheme.green : AppTheme.textMuted).withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  isConn ? 'ONLINE' : 'OFFLINE',
                  style: AppTheme.heading(
                    size: 10,
                    color: isConn ? AppTheme.green : AppTheme.textMuted,
                  ),
                ),
              ),
            ],
          ),
          if (isConn) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.surfaceGlow,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.amber.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.access_time_rounded, size: 16, color: AppTheme.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Autonomous NTP clock sync active. Schedules run accurately without phone.',
                      style: AppTheme.body(size: 11, color: AppTheme.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.amber,
                      side: const BorderSide(color: AppTheme.amber),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.sync_rounded, size: 16),
                    label: const Text('Sync NTP Now', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      AppHaptics.light();
                      ref.read(wifiProvider.notifier).triggerNtpSync();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.red,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onPressed: _confirmForget,
                  child: const Text('Forget', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConnectingStepper(WifiConnectionState wifi) {
    int currentStep = 1;
    if (wifi.phase == WifiPhase.gotIp) currentStep = 2;
    if (wifi.phase == WifiPhase.internetOk) currentStep = 3;
    if (wifi.phase == WifiPhase.saved || wifi.phase == WifiPhase.connected) currentStep = 4;

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
                'Connecting to ${wifi.currentSsid}…',
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

  Widget _buildPasswordCard() {
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
              const Icon(Icons.lock_outline_rounded, size: 18, color: AppTheme.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Connect to ${net.ssid}',
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
              child: const Text('Connect & Verify', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

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

                  return InkWell(
                    onTap: () => _onSelectNetwork(net),
                    child: Container(
                      color: isSelected ? AppTheme.surfaceGlow : Colors.transparent,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.wifi_rounded,
                            size: 20,
                            color: isSelected ? AppTheme.amber : AppTheme.textPrimary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  net.ssid,
                                  style: AppTheme.heading(
                                    size: 14,
                                    color: isSelected ? AppTheme.amber : AppTheme.textPrimary,
                                  ),
                                ),
                                Text(
                                  '${net.auth} • ${net.rssi} dBm',
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
