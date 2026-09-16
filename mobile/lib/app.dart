import 'package:flutter/material.dart';
import 'core/status_colors.dart';
import 'features/home/home_screen.dart';
import 'features/onboarding/welcome_screen.dart';
import 'services/api_client.dart';
import 'services/token_store.dart';

class SavaronaAilemApp extends StatefulWidget {
  SavaronaAilemApp({super.key});

  @override
  State<SavaronaAilemApp> createState() => _SavaronaAilemAppState();
}

class _SavaronaAilemAppState extends State<SavaronaAilemApp> {
  final TokenStore _tokens = TokenStore();
  late final ApiClient _api = ApiClient(_tokens);
  bool? _hasToken;

  @override
  void initState() {
    super.initState();
    _checkToken();
  }

  Future<void> _checkToken() async {
    final has = await _api.hasToken();
    if (mounted) setState(() => _hasToken = has);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Savarona Ailem',
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: switch (_hasToken) {
        null => const Scaffold(body: Center(child: CircularProgressIndicator())),
        false => WelcomeScreen(api: _api, onReady: () => setState(() => _hasToken = true)),
        true => HomeScreen(api: _api),
      },
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF0F766E),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF0E1513) : const Color(0xFFF5F7F6),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        scrolledUnderElevation: 1,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        elevation: isDark ? 0 : 1,
        color: isDark ? const Color(0xFF16201D) : Colors.white,
        surfaceTintColor: isDark ? const Color(0xFF16201D) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minVerticalPadding: 8,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF16201D) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      extensions: [isDark ? StatusColors.dark : StatusColors.light],
    );
  }
}
