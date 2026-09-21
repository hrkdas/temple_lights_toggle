import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/kv_store.dart';
import 'core/log.dart';
import 'domain/providers.dart';
import 'ui/theme.dart';

final _log = AppLog.tag('main');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Edge-to-edge serene light system overlay
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: AppTheme.background,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  final kv = await KvStore.instance();
  _log.i('KvStore bootstrap initialized');

  runApp(
    ProviderScope(
      overrides: [
        kvStoreProvider.overrideWithValue(kv),
      ],
      child: const TempleLightsApp(),
    ),
  );
}
