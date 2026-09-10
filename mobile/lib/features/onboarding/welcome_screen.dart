import 'package:flutter/material.dart';
import '../../core/config.dart';
import '../../services/api_client.dart';
import 'bootstrap_screen.dart';
import 'join_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.api, required this.onReady});
  final ApiClient api;
  final VoidCallback onReady;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.family_restroom, size: 72),
              const SizedBox(height: 16),
              Text(AppConfig.appName, style: Theme.of(context).textTheme.headlineMedium, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text(
                'Aileniz için açık rızaya dayalı, görünür konum paylaşımı.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              FilledButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => JoinScreen(api: api, onJoined: onReady),
                )),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Davet koduyla aileye katıl'),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => BootstrapScreen(api: api, onBootstrapped: onReady),
                )),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('İlk aile sahibi olarak kur (bootstrap)'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
