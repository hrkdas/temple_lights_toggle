import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:temple_lights_toggle/core/backup_service.dart';
import 'package:temple_lights_toggle/core/kv_store.dart';
import 'package:temple_lights_toggle/domain/models.dart';
import 'package:temple_lights_toggle/domain/providers.dart';
import 'package:temple_lights_toggle/features/scanner/device_sheet.dart';
import 'package:temple_lights_toggle/features/scanner/light_detail_sheet.dart';
import 'package:temple_lights_toggle/features/scanner/widgets/glow_test_panel.dart';
import 'package:temple_lights_toggle/features/scanner/widgets/inline_device_rename_panel.dart';
import 'package:temple_lights_toggle/features/scanner/widgets/led_range_calibration_card.dart';
import 'package:temple_lights_toggle/features/scanner/widgets/unpair_confirm_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late KvStore testKv;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    testKv = await KvStore.instance();
  });

  group('UnpairConfirmDialog Tests', () {
    testWidgets('Renders device name, warning badge, cancel and unpair buttons', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UnpairConfirmDialog(deviceName: 'Mandir Altar'),
          ),
        ),
      );

      expect(find.text('Unpair Temple Light?'), findsOneWidget);
      expect(find.textContaining('Mandir Altar'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Unpair'), findsOneWidget);
      expect(find.byIcon(Icons.link_off_rounded), findsNWidgets(2));
    });

    testWidgets('Tapping Cancel pops dialog with false', (tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await UnpairConfirmDialog.show(context, deviceName: 'Puja Shrine');
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(UnpairConfirmDialog), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(UnpairConfirmDialog), findsNothing);
      expect(result, isFalse);
    });

    testWidgets('Tapping Unpair pops dialog with true', (tester) async {
      bool? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await UnpairConfirmDialog.show(context, deviceName: 'Puja Shrine');
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(UnpairConfirmDialog), findsOneWidget);

      await tester.tap(find.text('Unpair'));
      await tester.pumpAndSettle();

      expect(find.byType(UnpairConfirmDialog), findsNothing);
      expect(result, isTrue);
    });
  });

  group('GlowTestPanel Tests', () {
    final testDev = PairedDevice(
      id: 'AA:BB:CC:DD:EE:FF',
      name: 'Temple Light 1',
      lastSeen: DateTime.now(),
      ledCount: 105,
    );

    testWidgets('Renders all 4 glow test modes and disabled state when offline', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            kvStoreProvider.overrideWithValue(testKv),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: GlowTestPanel(
                device: testDev,
                isConnected: false,
              ),
            ),
          ),
        ),
      );

      expect(find.text('TEST LIGHT GLOW'), findsOneWidget);
      expect(find.text('Diya Flutter'), findsOneWidget);
      expect(find.text('Aarti Breathe'), findsOneWidget);
      expect(find.text('Strip Alignment'), findsOneWidget);
      expect(find.text('3-Blink Locate'), findsOneWidget);
      expect(find.textContaining('Connect via Bluetooth'), findsOneWidget);

      // Main test button is disabled when not connected
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('Selects test mode and runs test with countdown when connected', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            kvStoreProvider.overrideWithValue(testKv),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: GlowTestPanel(
                device: testDev,
                isConnected: true,
              ),
            ),
          ),
        ),
      );

      // Select Aarti mode
      await tester.tap(find.text('Aarti Breathe'));
      await tester.pump();

      expect(find.text('Run Aarti Breathe'), findsOneWidget);

      // Tap run test
      await tester.tap(find.text('Run Aarti Breathe'));
      await tester.pump();

      // Countdown started
      expect(find.textContaining('Cancel Test (5s remaining)'), findsOneWidget);
      expect(find.byType(PulsingStatusDot), findsOneWidget);

      // Advance 1 second
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('Cancel Test (4s remaining)'), findsOneWidget);

      // Tap to cancel
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();

      expect(find.text('Run Aarti Breathe'), findsOneWidget);
      expect(find.byType(PulsingStatusDot), findsNothing);
    });
  });

  group('InlineDeviceRenamePanel Tests', () {
    testWidgets('Renders text field with initial name, live preview chip, and saves', (tester) async {
      String? savedName;
      bool cancelled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => InlineDeviceRenamePanel(
                initialName: 'Puja Shrine',
                isExpanded: true,
                onSave: (newName) async {
                  savedName = newName;
                },
                onCancel: () => cancelled = true,
                onToggleExpand: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('RENAME LIGHT'), findsOneWidget);
      expect(find.text('Puja Shrine'), findsNWidgets(2)); // field and preview chip

      // Enter new name
      await tester.enterText(find.byType(TextField), 'Mandir Golden Altar');
      await tester.pump();

      // Live preview chip should update
      expect(find.text('Mandir Golden Altar'), findsNWidgets(2));

      // Save
      await tester.tap(find.text('Save Name'));
      await tester.pump();

      expect(savedName, 'Mandir Golden Altar');

      // Test Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(cancelled, isTrue);
    });

    testWidgets('Rejects empty or whitespace-only name with error validation', (tester) async {
      String? savedName;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InlineDeviceRenamePanel(
              initialName: 'Puja Shrine',
              isExpanded: true,
              onSave: (newName) async => savedName = newName,
              onCancel: () {},
              onToggleExpand: () {},
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('Save Name'));
      await tester.pump();

      expect(find.text('Name cannot be empty'), findsOneWidget);
      expect(savedName, isNull);
    });
  });

  group('LedRangeCalibrationCard Tests', () {
    testWidgets('Renders LED count, strip length, steppers, presets, and power budget', (tester) async {
      final testDev = PairedDevice(
        id: 'DEV_CALIB_1',
        name: 'Mandir Strip',
        lastSeen: DateTime.now(),
        ledCount: 105,
        maxCurrentMa: 3000,
        colorOrder: 0,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            kvStoreProvider.overrideWithValue(testKv),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: LedRangeCalibrationCard(
                  device: testDev,
                  isConnected: true,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('LED RANGE & HARDWARE CALIBRATION'), findsOneWidget);
      expect(find.text('1.8m length'), findsOneWidget); // 105 / 60 = 1.75m -> 1.8m
      expect(find.textContaining('Range: LED #1 (0.0m) ➔ LED #105 (1.75m)'), findsOneWidget);
      expect(find.text('105'), findsWidgets); // in TextField

      // Tap Preset 180 (3.0m)
      await tester.tap(find.text('180 (3.0 m)'));
      await tester.pump();

      expect(find.text('3.0m length'), findsOneWidget);
      expect(find.textContaining('Range: LED #1 (0.0m) ➔ LED #180 (3.00m)'), findsOneWidget);

      // Tap +5 Stepper
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();

      expect(find.textContaining('Range: LED #1 (0.0m) ➔ LED #185 (3.08m)'), findsOneWidget);

      // Verify power budget chips
      expect(find.text('3000mA (15.0W)'), findsOneWidget);

      // Save Hardware Calibration
      await tester.tap(find.text('Save Hardware Calibration'));
      await tester.pump();

      expect(find.textContaining('Calibrated: 185 LEDs'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
    });
  });

  group('LightDetailSheet & DevicePickerSheet Integration Tests', () {
    testWidgets('LightDetailSheet opens and renders complete detail parameters', (tester) async {
      final dev = PairedDevice(
        id: 'DEV_FULL_1',
        name: 'Puja Mandir Sanctum',
        lastSeen: DateTime.now(),
        ledCount: 120,
        maxCurrentMa: 3000,
        roomId: 'room_temple',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            kvStoreProvider.overrideWithValue(testKv),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => LightDetailSheet.show(context, dev),
                  child: const Text('Open Details'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Details'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(LightDetailSheet), findsOneWidget);
      expect(find.text('Puja Mandir Sanctum'), findsWidgets);
      expect(find.text('TEST LIGHT GLOW'), findsOneWidget);
      expect(find.text('RF SIGNAL & PROXIMITY TELEMETRY'), findsOneWidget);
      expect(find.text('LED RANGE & HARDWARE CALIBRATION'), findsOneWidget);
      expect(find.text('ROOM ASSIGNMENT'), findsOneWidget);
      final unpairFinder = find.textContaining('Unpair "Puja Mandir Sanctum"');
      await tester.scrollUntilVisible(unpairFinder, 200, scrollable: find.byType(Scrollable).last);
      expect(unpairFinder, findsOneWidget);

      // Tap Unpair opens UnpairConfirmDialog
      await tester.tap(unpairFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(UnpairConfirmDialog), findsOneWidget);
    });

    testWidgets('Tapping Paired Device card in DevicePickerSheet opens LightDetailSheet', (tester) async {
      final dev = PairedDevice(
        id: 'DEV_PICKER_1',
        name: 'Mandir Pillar',
        lastSeen: DateTime.now(),
        ledCount: 105,
      );

      await testKv.putJson(KvKeys.savedDevices, [dev.toJson()]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            kvStoreProvider.overrideWithValue(testKv),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => DevicePickerSheet.show(context),
                  child: const Text('Open Picker'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Picker'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(DevicePickerSheet), findsOneWidget);
      expect(find.text('Mandir Pillar'), findsOneWidget);

      // Tap card body
      await tester.tap(find.text('Mandir Pillar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // LightDetailSheet is presented
      expect(find.byType(LightDetailSheet), findsOneWidget);
      expect(find.text('TEST LIGHT GLOW'), findsOneWidget);
    });
  });

  group('Hardware Metrology & Database Backward Compatibility Tests', () {
    test('PairedDevice defaults hardware calibration when omitted in legacy JSON', () {
      final legacyJson = {
        'id': 'LEGACY_001',
        'name': 'Old Altar Light',
        'lastSeen': '2025-01-01T00:00:00.000Z',
      };

      final device = PairedDevice.fromJson(legacyJson);

      expect(device.id, 'LEGACY_001');
      expect(device.name, 'Old Altar Light');
      expect(device.ledCount, isNull);
      expect(device.maxCurrentMa, isNull);
      expect(device.colorOrder, isNull);

      // Effective fallback values
      expect(device.effectiveLedCount, 150);
      expect(device.effectiveMaxCurrentMa, 3000);
      expect(device.effectiveColorOrder, 0);
    });

    test('PairedDevice preserves custom hardware calibration in modern JSON', () {
      final modernJson = {
        'id': 'MODERN_001',
        'name': 'Sanctum Strip',
        'lastSeen': '2026-10-27T12:00:00.000Z',
        'ledCount': 180,
        'maxCurrentMa': 2500,
        'colorOrder': 1,
        'roomId': 'room_garbhagriha',
      };

      final device = PairedDevice.fromJson(modernJson);

      expect(device.id, 'MODERN_001');
      expect(device.name, 'Sanctum Strip');
      expect(device.ledCount, 180);
      expect(device.maxCurrentMa, 2500);
      expect(device.colorOrder, 1);
      expect(device.effectiveLedCount, 180);
      expect(device.effectiveMaxCurrentMa, 2500);
      expect(device.effectiveColorOrder, 1);

      final serialized = device.toJson();
      expect(serialized['ledCount'], 180);
      expect(serialized['maxCurrentMa'], 2500);
      expect(serialized['colorOrder'], 1);
    });

    test('BackupService restores legacy snapshot without crashing and populates effective hardware defaults', () async {
      final legacyBackupJson = jsonEncode({
        'version': 1,
        'devices': [
          {
            'id': 'BACKUP_DEV_OLD',
            'name': 'Pradakshina Pathway',
            'lastSeen': '2025-05-01T09:00:00.000',
          }
        ],
        'modes': [],
      });

      final backupService = BackupService(testKv);
      final container = ProviderContainer(
        overrides: [
          kvStoreProvider.overrideWithValue(testKv),
        ],
      );

      final report = await backupService.restoreBackupJson(
        legacyBackupJson,
        ref: _TestMockWidgetRef(container),
      );

      expect(report.isSuccess, isTrue);
      expect(report.devicesRestored, 1);

      final rawList = testKv.getJsonList(KvKeys.savedDevices);
      expect(rawList, isNotNull);
      expect(rawList!.length, 1);

      final restoredDevice = PairedDevice.fromJson(rawList.first);
      expect(restoredDevice.id, 'BACKUP_DEV_OLD');
      expect(restoredDevice.displayName, 'Pradakshina Pathway');
      expect(restoredDevice.effectiveLedCount, 150);
      expect(restoredDevice.effectiveMaxCurrentMa, 3000);
      expect(restoredDevice.effectiveColorOrder, 0);
    });

    test('BackupService creates and restores v2 snapshot with complete hardware metrology', () async {
      final backupService = BackupService(testKv);

      final dev = PairedDevice(
        id: 'DEV_HW_1',
        name: 'Garbhagriha Arch',
        lastSeen: DateTime.now(),
        ledCount: 120,
        maxCurrentMa: 1500,
        colorOrder: 2,
        roomId: 'room_garbhagriha',
      );

      await testKv.putJson(KvKeys.savedDevices, [dev.toJson()]);

      final jsonBackup = backupService.createBackupJson();
      expect(jsonBackup, isNotEmpty);

      // Wipe store key
      await testKv.remove(KvKeys.savedDevices);
      expect(testKv.getJsonList(KvKeys.savedDevices), isNull);

      final container = ProviderContainer(
        overrides: [
          kvStoreProvider.overrideWithValue(testKv),
        ],
      );

      // Restore snapshot
      final restoreReport = await backupService.restoreBackupJson(
        jsonBackup,
        ref: _TestMockWidgetRef(container),
      );
      expect(restoreReport.isSuccess, isTrue);
      expect(restoreReport.devicesRestored, 1);

      final restoredList = testKv.getJsonList(KvKeys.savedDevices);
      expect(restoredList, isNotNull);
      final restored = PairedDevice.fromJson(restoredList!.first);

      expect(restored.id, 'DEV_HW_1');
      expect(restored.name, 'Garbhagriha Arch');
      expect(restored.ledCount, 120);
      expect(restored.maxCurrentMa, 1500);
      expect(restored.colorOrder, 2);
      expect(restored.roomId, 'room_garbhagriha');
    });
  });
}

class _TestMockWidgetRef implements WidgetRef {
  _TestMockWidgetRef(this._container);
  final ProviderContainer _container;

  @override
  BuildContext get context => throw UnimplementedError();

  @override
  T read<T>(ProviderListenable<T> provider) => _container.read(provider);

  @override
  T watch<T>(ProviderListenable<T> provider) => _container.read(provider);

  @override
  void listen<T>(ProviderListenable<T> provider, void Function(T? previous, T next) listener, {void Function(Object error, StackTrace stackTrace)? onError}) {}

  @override
  ProviderSubscription<T> listenManual<T>(ProviderListenable<T> provider, void Function(T? previous, T next) listener, {void Function(Object error, StackTrace stackTrace)? onError, bool fireImmediately = false}) =>
      throw UnimplementedError();

  @override
  T refresh<T>(Refreshable<T> provider) => _container.refresh(provider);

  @override
  void invalidate(ProviderOrFamily provider) => _container.invalidate(provider);

  @override
  bool exists(ProviderBase<Object?> provider) => _container.exists(provider);
}
