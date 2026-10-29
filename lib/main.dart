import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'screens/home_and_workspace_screen.dart';
import 'services/local_history_store.dart';
import 'theme/kertas_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const QuickPdfApp());
}

class QuickPdfApp extends StatefulWidget {
  const QuickPdfApp({super.key});

  @override
  State<QuickPdfApp> createState() => _QuickPdfAppState();
}

typedef KertasPdfApp = QuickPdfApp;

class _QuickPdfAppState extends State<QuickPdfApp> {
  ThemeMode _themeMode = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    _loadSavedTheme();
  }

  Future<void> _loadSavedTheme() async {
    final saved = await LocalHistoryStore.loadThemeMode();
    if (!mounted) return;
    setState(() => _themeMode = saved);
  }

  Future<void> _updateThemeMode(ThemeMode nextMode) async {
    setState(() => _themeMode = nextMode);
    await LocalHistoryStore.saveThemeMode(nextMode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QuickPDF',
      debugShowCheckedModeBanner: false,
      theme: KertasTheme.light(),
      darkTheme: KertasTheme.dark(),
      themeMode: _themeMode,
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
        },
      ),
      home: HomeAndWorkspaceScreen(
        currentThemeMode: _themeMode,
        onThemeModeChanged: _updateThemeMode,
      ),
    );
  }
}
