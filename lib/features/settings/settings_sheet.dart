import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../contract/light_contract.dart';
import '../../core/haptics.dart';
import '../../core/log.dart';
import '../../domain/providers.dart';
import '../../ui/theme.dart';
import '../ota/ota_update_screen.dart';
import '../wifi/wifi_setup_sheet.dart';
import '../../ui/widgets/wifi_signal_icon.dart';
import 'animation_picker_sheet.dart';
import 'hardware_setup_sheet.dart';

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

  Future<void> _launchUrlHelper(String urlStr) async {
    try {
      final uri = Uri.parse(urlStr);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Fallback to web if custom app scheme fails
        if (urlStr.startsWith('googlehome://')) {
          final fallback = Uri.parse('https://assistant.google.com/services/a/uid/0000009852277dbd');
          await launchUrl(fallback, mode: LaunchMode.externalApplication);
        }
      }
    } catch (_) {}
  }

  void _showRainmakerLoginDialog(BuildContext context) {
    final emailController = TextEditingController();
    final passController = TextEditingController();
    bool isSubmitting = false;
    String? localError;

    showDialog<void>(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.cloud_sync_rounded, color: AppTheme.amber, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Espressif Sign In', style: AppTheme.heading(size: 16)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sign in to link your Espressif RainMaker account with Google Home.',
                style: AppTheme.body(size: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),

              // Prominent Google Sign-In Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.g_mobiledata_rounded, size: 28, color: Colors.black),
                  label: Text('Continue with Google', style: AppTheme.heading(size: 13, color: Colors.black)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: AppTheme.borderBright),
                    ),
                  ),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setDlgState(() {
                            isSubmitting = true;
                            localError = null;
                          });
                          final ok = await ref.read(rainmakerAuthProvider.notifier).loginWithGoogle();
                          if (context.mounted) {
                            if (ok) {
                              Navigator.of(dlgCtx).pop();
                              AppHaptics.success();
                            } else {
                              final err = ref.read(rainmakerAuthProvider).errorMessage;
                              setDlgState(() {
                                isSubmitting = false;
                                localError = err;
                              });
                            }
                          }
                        },
                ),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  const Expanded(child: Divider(color: AppTheme.border)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text('OR WITH EMAIL', style: AppTheme.mono(size: 10, color: AppTheme.textMuted)),
                  ),
                  const Expanded(child: Divider(color: AppTheme.border)),
                ],
              ),
              const SizedBox(height: 16),

              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                style: AppTheme.body(size: 13),
                decoration: InputDecoration(
                  labelText: 'Email Address',
                  labelStyle: AppTheme.body(size: 12, color: AppTheme.textSecondary),
                  prefixIcon: const Icon(Icons.email_outlined, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passController,
                obscureText: true,
                style: AppTheme.body(size: 13),
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: AppTheme.body(size: 12, color: AppTheme.textSecondary),
                  prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              if (localError != null) ...[
                const SizedBox(height: 10),
                Text(localError!, style: AppTheme.body(size: 11, color: AppTheme.red)),
              ],
              const SizedBox(height: 10),
              Center(
                child: TextButton.icon(
                  icon: const Icon(Icons.link_rounded, size: 14),
                  label: const Text('Trouble redirecting? Enter code or URL manually'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.textMuted,
                    textStyle: AppTheme.body(size: 11),
                  ),
                  onPressed: () {
                    Navigator.of(dlgCtx).pop();
                    _showManualCodeEntryDialog(context);
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dlgCtx).pop(),
              child: Text('Cancel', style: AppTheme.body(size: 13, color: AppTheme.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.amber,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: isSubmitting
                  ? null
                  : () async {
                      final email = emailController.text.trim();
                      final pass = passController.text;
                      if (email.isEmpty || pass.isEmpty) {
                        setDlgState(() => localError = 'Please enter both email and password.');
                        return;
                      }
                      setDlgState(() {
                        isSubmitting = true;
                        localError = null;
                      });

                      final success = await ref.read(rainmakerAuthProvider.notifier).login(email, pass);
                      if (context.mounted) {
                        if (success) {
                          Navigator.of(dlgCtx).pop();
                          AppHaptics.success();
                        } else {
                          final err = ref.read(rainmakerAuthProvider).errorMessage ?? 'Login failed';
                          setDlgState(() {
                            isSubmitting = false;
                            localError = err;
                          });
                        }
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : Text('Sign In with Email', style: AppTheme.heading(size: 13, color: Colors.black)),
            ),
          ],
        ),
      ),
    );
  }

  void _showManualCodeEntryDialog(BuildContext context) {
    AppHaptics.light();
    final urlController = TextEditingController();
    bool isSubmitting = false;
    String? localError;

    showDialog<void>(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.cyan.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.link_rounded, color: AppTheme.cyan, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Paste Callback URL', style: AppTheme.heading(size: 16)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'If your browser did not return automatically after Google sign-in, copy the URL or code from the browser address bar and paste it below:',
                style: AppTheme.body(size: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: urlController,
                maxLines: 2,
                style: AppTheme.mono(size: 11),
                decoration: InputDecoration(
                  hintText: 'rainmaker://com.espressif.novahome/success?code=... or authorization code',
                  hintStyle: AppTheme.mono(size: 10, color: AppTheme.textMuted),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.paste_rounded, size: 18),
                    tooltip: 'Paste from clipboard',
                    onPressed: () async {
                      final data = await Clipboard.getData(Clipboard.kTextPlain);
                      if (data?.text != null && data!.text!.isNotEmpty) {
                        urlController.text = data.text!.trim();
                      }
                    },
                  ),
                ),
              ),
              if (localError != null) ...[
                const SizedBox(height: 10),
                Text(localError!, style: AppTheme.body(size: 11, color: AppTheme.red)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dlgCtx).pop(),
              child: Text('Cancel', style: AppTheme.body(size: 13, color: AppTheme.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.amber,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: isSubmitting
                  ? null
                  : () async {
                      final text = urlController.text.trim();
                      if (text.isEmpty) {
                        setDlgState(() => localError = 'Please paste the URL or authorization code.');
                        return;
                      }
                      setDlgState(() {
                        isSubmitting = true;
                        localError = null;
                      });

                      final ok = await ref.read(rainmakerAuthProvider.notifier).loginWithOAuthCode(text);
                      if (context.mounted) {
                        if (ok) {
                          Navigator.of(dlgCtx).pop();
                          AppHaptics.success();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Signed in with Google & linked to Espressif Cloud!'),
                              backgroundColor: AppTheme.green,
                            ),
                          );
                        } else {
                          final err = ref.read(rainmakerAuthProvider).errorMessage ?? 'Invalid code or exchange failed.';
                          setDlgState(() {
                            isSubmitting = false;
                            localError = err;
                          });
                        }
                      }
                    },
              child: isSubmitting
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : Text('Verify & Link', style: AppTheme.heading(size: 13, color: Colors.black)),
            ),
          ],
        ),
      ),
    );
  }

  void _showGoogleHomeGuide(BuildContext context) {
    AppHaptics.light();
    final client = ref.read(bleClientProvider);
    if (client.isConnected) {
      final settings = ref.read(settingsProvider);
      try {
        client.writeWithoutResponse(
          LightPacketEncoder.encodeGetRmakerInfo(),
          serviceUuid: settings.customServiceUuid,
          charUuid: settings.customCharUuid,
        );
      } catch (_) {}
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.cyan.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.home_outlined, size: 24, color: AppTheme.cyan),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Google Home Setup', style: AppTheme.heading(size: 18)),
                        const SizedBox(height: 2),
                        Text('Control via Google Assistant & Google Home App', style: AppTheme.body(size: 12, color: AppTheme.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // In-App Espressif Account Link Card
              Consumer(
                builder: (context, ref, _) {
                  final auth = ref.watch(rainmakerAuthProvider);
                  final activeDev = ref.watch(activeDeviceProvider);
                  final light = ref.watch(lightControlProvider);
                  final nodeId = light.rainmakerNodeId ?? activeDev?.rainmakerNodeId;

                  if (auth.isLoggedIn) {
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.green.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.green.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.check_circle_rounded, size: 16, color: AppTheme.green),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Linked: ${auth.email}',
                                  style: AppTheme.heading(size: 13, color: AppTheme.green),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              TextButton(
                                onPressed: () => ref.read(rainmakerAuthProvider.notifier).logout(),
                                child: Text('Sign Out', style: AppTheme.body(size: 11, color: AppTheme.red)),
                              ),
                            ],
                          ),
                          if (nodeId != null && nodeId.isNotEmpty) ...[
                            if (auth.nodes.contains(nodeId)) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AppTheme.green.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppTheme.green.withValues(alpha: 0.4)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.cloud_done_rounded, size: 16, color: AppTheme.green),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Google Home Ready ($nodeId)',
                                        style: AppTheme.heading(size: 11, color: AppTheme.green),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ] else ...[
                              const SizedBox(height: 8),
                              // Diagnostic health card for claiming & MQTT state
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: (light.rainmakerMqttConnected
                                          ? AppTheme.green
                                          : (light.rainmakerDeviceClaimed ? AppTheme.amber : AppTheme.red))
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: (light.rainmakerMqttConnected
                                            ? AppTheme.green
                                            : (light.rainmakerDeviceClaimed ? AppTheme.amber : AppTheme.red))
                                        .withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          light.rainmakerMqttConnected
                                              ? Icons.cloud_done_rounded
                                              : (light.rainmakerDeviceClaimed ? Icons.cloud_queue_rounded : Icons.vpn_key_off_rounded),
                                          size: 15,
                                          color: light.rainmakerMqttConnected
                                              ? AppTheme.green
                                              : (light.rainmakerDeviceClaimed ? AppTheme.amber : AppTheme.red),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            light.rainmakerMqttConnected
                                                ? 'Cloud Ready (MQTT Connected)'
                                                : (light.rainmakerDeviceClaimed
                                                    ? 'MQTT Offline (Check Wi-Fi)'
                                                    : 'Unclaimed (No Cloud Cert)'),
                                            style: AppTheme.heading(
                                              size: 11,
                                              color: light.rainmakerMqttConnected
                                                  ? AppTheme.green
                                                  : (light.rainmakerDeviceClaimed ? AppTheme.amber : AppTheme.red),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (!light.rainmakerDeviceClaimed) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        'ESP32 requires one-time certificate claiming before linking.',
                                        style: AppTheme.body(size: 10, color: AppTheme.textMuted),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text('Node: $nodeId', style: AppTheme.mono(size: 11, color: AppTheme.textSecondary)),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.green,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: () async {
                                      final ok = await ref.read(rainmakerAuthProvider.notifier).mapActiveDevice(nodeId: nodeId);
                                      if (context.mounted) {
                                        final isVerified = ref.read(rainmakerAuthProvider).nodes.contains(nodeId);
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              isVerified
                                                  ? 'Device linked and verified in Google Home!'
                                                  : (ok
                                                      ? 'Mapping request sent! Awaiting device MQTT sync.'
                                                      : (ref.read(rainmakerAuthProvider).errorMessage ?? 'Failed to link device.')),
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                    child: Text('Bind Light', style: AppTheme.heading(size: 11, color: Colors.white)),
                                  ),
                                ],
                              ),
                            ],
                          ] else ...[
                            const SizedBox(height: 6),
                            Text(
                              'Connect to your light over BLE to pair it with this Espressif account.',
                              style: AppTheme.body(size: 11, color: AppTheme.textMuted),
                            ),
                          ],
                        ],
                      ),
                    );
                  } else {
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceRaised,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.borderBright),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Direct Espressif Cloud Linking', style: AppTheme.heading(size: 13)),
                          const SizedBox(height: 4),
                          Text(
                            'Sign in to your Espressif RainMaker account so this device is bound to your email automatically.',
                            style: AppTheme.body(size: 11.5, color: AppTheme.textSecondary),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.g_mobiledata_rounded, size: 28, color: Colors.black),
                              label: Text('Sign In with Google', style: AppTheme.heading(size: 13, color: Colors.black)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: const BorderSide(color: AppTheme.borderBright),
                                ),
                              ),
                              onPressed: () async {
                                final ok = await ref.read(rainmakerAuthProvider.notifier).loginWithGoogle();
                                if (context.mounted) {
                                  if (ok) {
                                    AppHaptics.success();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Signed in with Google & linked to Espressif Cloud!'),
                                        backgroundColor: AppTheme.green,
                                      ),
                                    );
                                  } else {
                                    final err = ref.read(rainmakerAuthProvider).errorMessage;
                                    if (err != null) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(err),
                                          backgroundColor: AppTheme.red,
                                          action: SnackBarAction(
                                            label: 'Paste Link',
                                            textColor: Colors.white,
                                            onPressed: () => _showManualCodeEntryDialog(context),
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                }
                              },
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.email_outlined, size: 16),
                              label: const Text('Sign In with Email & Password'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.textSecondary,
                                side: const BorderSide(color: AppTheme.border),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: () => _showRainmakerLoginDialog(context),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Center(
                            child: TextButton.icon(
                              icon: const Icon(Icons.link_rounded, size: 14),
                              label: const Text('Trouble redirecting? Paste sign-in link'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppTheme.textMuted,
                                textStyle: AppTheme.body(size: 11),
                              ),
                              onPressed: () => _showManualCodeEntryDialog(context),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 16),

              _buildGuideStep(
                step: '1',
                title: 'One-Time Cloud Claim (Classic ESP32)',
                desc: 'Classic ESP32 boards need a 1-time certificate claim to bind with your account. Run "esp-rainmaker-cli claim" via USB, or add via the official ESP RainMaker app.',
              ),
              const SizedBox(height: 14),
              _buildGuideStep(
                step: '2',
                title: 'Connect 2.4 GHz Wi-Fi',
                desc: 'In this app, open the Wi-Fi setup sheet and connect your light to your home Wi-Fi network.',
              ),
              const SizedBox(height: 14),
              _buildGuideStep(
                step: '3',
                title: 'Check ESP RainMaker Mobile App',
                desc: 'Open the ESP RainMaker app on your phone. "Temple Lights" must appear here first before Google Home can discover it.',
              ),
              const SizedBox(height: 14),
              _buildGuideStep(
                step: '4',
                title: 'Link with Google Home ("Works with Google")',
                desc: 'In the Google Home app, tap "+" > "Works with Google" > search "ESP RainMaker" and sign in. Your Temple Lights will be imported instantly!',
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.cloud_sync_rounded, size: 16, color: Colors.white),
                      label: Text('1. Open RainMaker', style: AppTheme.heading(size: 12, color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.gold,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => _launchUrlHelper('https://rainmaker.espressif.com'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.home_rounded, size: 16, color: Colors.white),
                      label: Text('2. Open Google Home', style: AppTheme.heading(size: 12, color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.cyan,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => _launchUrlHelper('googlehome://'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.surfaceRaised,
                    foregroundColor: AppTheme.textPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text('Close', style: AppTheme.heading(size: 13, color: AppTheme.textPrimary)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGuideStep({required String step, required String title, required String desc}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppTheme.cyan,
            shape: BoxShape.circle,
          ),
          child: Text(step, style: AppTheme.heading(size: 12, color: Colors.black)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTheme.heading(size: 14)),
              const SizedBox(height: 2),
              Text(desc, style: AppTheme.body(size: 12, color: AppTheme.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _exportBackup() async {
    final backupService = ref.read(backupServiceProvider);
    final jsonStr = backupService.createBackupJson();
    await Clipboard.setData(ClipboardData(text: jsonStr));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Database backup copied to clipboard! (JSON snapshot)'),
        backgroundColor: AppTheme.green,
        duration: Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showRestoreDialog() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.settings_backup_restore_rounded, color: AppTheme.amber, size: 22),
            const SizedBox(width: 8),
            Text('Restore Database', style: AppTheme.heading(size: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Paste a valid backup JSON string below. Full backward compatibility is guaranteed for older schemas.',
              style: AppTheme.body(size: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              maxLines: 6,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: '{\n  "version": 2,\n  "devices": [...],\n  "presets": [...]\n}',
                hintStyle: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppTheme.textMuted),
                filled: true,
                fillColor: AppTheme.surfaceRaised,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.amber)),
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
            onPressed: () async {
              final jsonText = textController.text.trim();
              if (jsonText.isEmpty) return;
              try {
                final backupService = ref.read(backupServiceProvider);
                final result = await backupService.restoreBackupJson(jsonText, ref: ref);
                if (ctx.mounted) Navigator.of(ctx).pop();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Successfully restored ${result.devicesRestored} devices, ${result.presetsRestored} presets, ${result.roomsRestored} rooms!',
                        style: const TextStyle(color: Colors.white),
                      ),
                      backgroundColor: AppTheme.green,
                      duration: const Duration(seconds: 4),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to restore backup: $e'),
                      backgroundColor: AppTheme.red,
                      duration: const Duration(seconds: 4),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            child: Text('Restore Now', style: AppTheme.heading(size: 13, color: Colors.black)),
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

                // Temple WiFi & Network Clock Card
                Consumer(
                  builder: (context, ref, _) {
                    final wifi = ref.watch(wifiProvider);
                    final isConnected = wifi.isConnected;
                    final isConnecting = wifi.isConnecting;
                    final isScanning = wifi.isScanning;

                    final Color accentColor = isConnected
                        ? AppTheme.green
                        : (isConnecting ? AppTheme.amber : AppTheme.cyan);

                    final String activeSlotLabel = wifi.activeSlot > 0 ? 'Slot ${wifi.activeSlot}' : '';
                    final String statusText = isConnected
                        ? 'Connected • $activeSlotLabel ${wifi.currentSsid} (${wifi.rssi} dBm)'
                        : (isConnecting
                            ? 'Connecting to ${wifi.currentSsid}...'
                            : (wifi.hasAnySavedSlot
                                ? 'Offline • Dual-Slot Failover Ready'
                                : (wifi.currentSsid.isNotEmpty
                                    ? 'Offline • Saved: ${wifi.currentSsid}'
                                    : 'No WiFi configured')));

                    final String subText = isConnected && wifi.ipAddress.isNotEmpty
                        ? 'IP: ${wifi.ipAddress} • SNTP active • ${WifiSignalIcon.qualityLabelForRssi(wifi.rssi)} Signal'
                        : (isConnecting
                            ? 'Verifying network & NTP gateway'
                            : 'Synchronizes schedules & clock via NTP');

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceRaised,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isConnected
                              ? AppTheme.green.withValues(alpha: 0.3)
                              : AppTheme.border,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: accentColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: isConnected
                                    ? WifiSignalIcon(
                                        rssi: wifi.rssi,
                                        size: 20,
                                        color: accentColor,
                                      )
                                    : Icon(
                                        (isConnecting || isScanning
                                            ? Icons.wifi_find_rounded
                                            : Icons.wifi_off_rounded),
                                        size: 20,
                                        color: accentColor,
                                      ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text('Temple WiFi & Clock', style: AppTheme.heading(size: 15)),
                                        const Spacer(),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: accentColor.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                                          ),
                                          child: Text(
                                            isConnected
                                                ? 'ONLINE'
                                                : (isConnecting ? 'CONNECTING' : 'BLE ONLY'),
                                            style: AppTheme.heading(size: 9.5, color: accentColor),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      statusText,
                                      style: AppTheme.body(size: 12, color: AppTheme.textPrimary),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      subText,
                                      style: AppTheme.mono(size: 10.5, color: AppTheme.textMuted),
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
                              icon: const Icon(Icons.settings_ethernet_rounded, size: 18, color: Colors.white),
                              label: Text('Configure WiFi & Clock', style: AppTheme.heading(size: 13, color: Colors.white)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isConnected ? AppTheme.surface : AppTheme.cyan,
                                foregroundColor: isConnected ? AppTheme.cyan : Colors.white,
                                side: isConnected ? const BorderSide(color: AppTheme.cyan) : BorderSide.none,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: isConnected ? 0 : 1,
                              ),
                              onPressed: () {
                                Navigator.of(context).pop();
                                WifiSetupSheet.show(context);
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),

                // LED Strip Length & Power Card
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
                            child: const Icon(Icons.linear_scale_rounded, size: 20, color: AppTheme.amber),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('LED Strip & Power Safety', style: AppTheme.heading(size: 15)),
                                const SizedBox(height: 2),
                                Consumer(
                                  builder: (context, ref, _) {
                                    final light = ref.watch(lightControlProvider);
                                    final dirStr = light.stripOrientation == 1 ? 'RTL (Inverted)' : 'LTR (Standard)';
                                    return Text(
                                      '${light.ledCount} LEDs (${light.formattedLength}) • Safety: ${light.maxCurrentMa}mA • $dirStr',
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
                          icon: const Icon(Icons.tune_rounded, size: 18, color: Colors.white),
                          label: Text('Calibrate Strip & Power', style: AppTheme.heading(size: 13, color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.amber,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 1,
                          ),
                          onPressed: () {
                            Navigator.of(context).pop();
                            HardwareSetupSheet.show(context);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Devotional Animations & Living Aura Card
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
                              color: AppTheme.gold.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.auto_awesome_rounded, size: 20, color: AppTheme.gold),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Devotional Animations & Aura', style: AppTheme.heading(size: 15)),
                                const SizedBox(height: 2),
                                Consumer(
                                  builder: (context, ref, _) {
                                    final light = ref.watch(lightControlProvider);
                                    return Text(
                                      '${light.transitionStyleName} • ${light.ambientStyleName}',
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
                          icon: const Icon(Icons.palette_rounded, size: 18, color: Colors.black),
                          label: Text('Customize Motion & Living Aura', style: AppTheme.heading(size: 13, color: Colors.black)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.gold,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 1,
                          ),
                          onPressed: () {
                            Navigator.of(context).pop();
                            AnimationPickerSheet.show(context);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Google Home & Voice Assistant Card
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
                              color: AppTheme.cyan.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.home_outlined, size: 20, color: AppTheme.cyan),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Google Home & Voice Assistant', style: AppTheme.heading(size: 15)),
                                const SizedBox(height: 2),
                                Consumer(
                                  builder: (context, ref, _) {
                                    final activeDev = ref.watch(activeDeviceProvider);
                                    final auth = ref.watch(rainmakerAuthProvider);
                                    final isLinked = (activeDev?.isGoogleHomeLinked ?? false) || auth.isLoggedIn;
                                    final subtitle = auth.isLoggedIn
                                        ? 'Account: ${auth.email}'
                                        : (isLinked ? 'Status: Linked with Google Home' : 'Free Cloud Integration via ESP RainMaker');
                                    return Text(
                                      subtitle,
                                      style: AppTheme.mono(size: 11, color: isLinked ? AppTheme.green : AppTheme.textSecondary),
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
                          icon: const Icon(Icons.assistant_rounded, size: 18, color: Colors.white),
                          label: Text('Google Home Setup Guide', style: AppTheme.heading(size: 13, color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.cyan,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 1,
                          ),
                          onPressed: () => _showGoogleHomeGuide(context),
                        ),
                      ),
                    ],
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
                                    final activeDev = ref.watch(activeDeviceProvider);
                                    final devVer = light.firmwareVersion != null ? 'v${light.firmwareVersion}' : 'v1.0.0';
                                    final targetName = activeDev?.displayName ?? 'Active Light';
                                    return Text(
                                      '$targetName: $devVer • Bundled: v${LightBleUuids.bundledFirmwareVersion}',
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

                // Database Backup & Safe Restore Card
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
                              color: AppTheme.cyan.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.cloud_sync_rounded, size: 20, color: AppTheme.cyan),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Database Backup & Restore', style: AppTheme.heading(size: 15)),
                                const SizedBox(height: 2),
                                Text(
                                  'Export JSON snapshot or restore with 100% backward compatibility',
                                  style: AppTheme.body(size: 11.5, color: AppTheme.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.upload_rounded, size: 16),
                              label: Text('Export JSON', style: AppTheme.heading(size: 12)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppTheme.borderBright),
                                foregroundColor: AppTheme.textPrimary,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: _exportBackup,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.settings_backup_restore_rounded, size: 16, color: Colors.black),
                              label: Text('Restore Backup', style: AppTheme.heading(size: 12, color: Colors.black)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.amber,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 1,
                              ),
                              onPressed: _showRestoreDialog,
                            ),
                          ),
                        ],
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
