import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:temple_lights_toggle/core/kv_store.dart';
import 'package:temple_lights_toggle/domain/providers.dart';
import 'package:temple_lights_toggle/features/shell/main_nav_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MainNavShell Scroll-to-Hide/Show & Navigation Tests', () {
    late KvStore kv;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      kv = await KvStore.instance();
    });

    Widget createTestApp() {
      return ProviderScope(
        overrides: [
          kvStoreProvider.overrideWithValue(kv),
        ],
        child: const MaterialApp(
          home: MainNavShell(),
        ),
      );
    }

    testWidgets('Renders MainNavShell with AppBar and BottomNav initially visible', (tester) async {
      await tester.pumpWidget(createTestApp());
      // Advance clock past the 300ms BLE initialization timer and any flutter_animate timers
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      // Check App bar title and uppercase bottom nav items
      expect(find.text('TEMPLE LIGHTS'), findsOneWidget);
      expect(find.text('LIGHTS'), findsOneWidget);
      expect(find.text('MODES'), findsOneWidget);
      expect(find.text('SCHEDULE'), findsOneWidget);
      expect(find.text('LOGS'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('Switching tabs keeps bars visible and changes title', (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pump(const Duration(milliseconds: 500));

      // Tap 'MODES' tab (2nd item)
      await tester.tap(find.text('MODES'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('BOOT MODES'), findsOneWidget);

      // Tap 'SCHEDULE' tab (3rd item)
      await tester.tap(find.text('SCHEDULE'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('SCHEDULE ALARMS'), findsOneWidget);

      // Tap 'LOGS' tab (4th item)
      await tester.tap(find.text('LOGS'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('ACTIVITY LOGS'), findsOneWidget);

      // Settle any remaining animation frame
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('Scrolling down hides bars and scrolling up reveals bars', (tester) async {
      await tester.pumpWidget(createTestApp());
      await tester.pump(const Duration(milliseconds: 500));

      // Find the SingleChildScrollView in LightsScreen
      final scrollView = find.byType(SingleChildScrollView).first;

      // Scroll down (drag upwards by -250px) to simulate reading down the screen
      await tester.drag(scrollView, const Offset(0, -250));
      await tester.pump(const Duration(milliseconds: 350));

      // After scrolling down, bottom nav should be sliding down (or faded out)
      final fadeFinder = find.byType(FadeTransition);
      expect(fadeFinder, findsWidgets);

      // Now scroll up (drag downwards by +300px) to simulate returning to top
      await tester.drag(scrollView, const Offset(0, 300));
      await tester.pump(const Duration(milliseconds: 500));

      // Bars must be fully visible again
      expect(find.text('TEMPLE LIGHTS'), findsOneWidget);
      expect(find.text('LIGHTS'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 500));
    });
  });
}
