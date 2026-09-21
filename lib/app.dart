import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/shell/main_nav_shell.dart';
import 'ui/theme.dart';

class TempleLightsApp extends ConsumerWidget {
  const TempleLightsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Temple Lights',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.buildLight(),
      themeMode: ThemeMode.light,
      home: const MainNavShell(),
    );
  }
}
