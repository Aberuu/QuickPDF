import 'package:flutter/material.dart';
import 'screens/home_and_workspace_screen.dart';
import 'services/local_history_store.dart';
import 'theme/kertas_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KertasPdfApp());
}

class KertasPdfApp extends StatefulWidget {
  const KertasPdfApp({super.key});

  @override
  State<KertasPdfApp> createState() => _KertasPdfAppState();
}

class _KertasPdfAppState extends State<KertasPdfApp> {
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
      title: 'KertasPDF',
      debugShowCheckedModeBanner: false,
      theme: KertasTheme.light(),
      darkTheme: KertasTheme.dark(),
      themeMode: _themeMode,
      home: HomeAndWorkspaceScreen(
        currentThemeMode: _themeMode,
        onThemeModeChanged: _updateThemeMode,
      ),
    );
  }
}
