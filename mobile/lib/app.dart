import 'package:flutter/material.dart';
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
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: switch (_hasToken) {
        null => const Scaffold(body: Center(child: CircularProgressIndicator())),
        false => WelcomeScreen(api: _api, onReady: () => setState(() => _hasToken = true)),
        true => HomeScreen(api: _api),
      },
    );
  }
}
