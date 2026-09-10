import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import '../../services/api_client.dart';

class BootstrapScreen extends StatefulWidget {
  const BootstrapScreen({super.key, required this.api, required this.onBootstrapped});
  final ApiClient api;
  final VoidCallback onBootstrapped;

  @override
  State<BootstrapScreen> createState() => _BootstrapScreenState();
}

class _BootstrapScreenState extends State<BootstrapScreen> {
  final _formKey = GlobalKey<FormState>();
  final _secret = TextEditingController();
  final _familyName = TextEditingController();
  final _ownerName = TextEditingController();
  final _deviceName = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _obscureSecret = true;

  @override
  void dispose() {
    _secret.dispose();
    _familyName.dispose();
    _ownerName.dispose();
    _deviceName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      await widget.api.bootstrap(
        bootstrapSecret: _secret.text.trim(),
        familyName: _familyName.text.trim(),
        ownerName: _ownerName.text.trim(),
        deviceName: _deviceName.text.trim(),
        platform: Platform.isIOS ? 'ios' : 'android',
      );
      widget.onBootstrapped();
    } on ApiException catch (e) {
      setState(() => _error = switch (e.code) {
        'forbidden' => 'Bootstrap secret hatalı.',
        'already_bootstrapped' => 'Bu backend zaten kurulmuş; davet kodu ile katılın.',
        'rate_limited' => 'Çok fazla deneme yapıldı, biraz sonra tekrar deneyin.',
        _ => 'Kurulum başarısız (${e.code}).',
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('İlk kurulum (owner)')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextFormField(
                controller: _secret,
                obscureText: _obscureSecret,
                decoration: InputDecoration(
                  labelText: 'Bootstrap secret',
                  suffixIcon: IconButton(
                    icon: Icon(_obscureSecret ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscureSecret = !_obscureSecret),
                  ),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Secret gerekli' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _familyName,
                decoration: const InputDecoration(labelText: 'Aile adı'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Aile adı gerekli' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ownerName,
                decoration: const InputDecoration(labelText: 'Adınız'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Ad gerekli' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _deviceName,
                decoration: const InputDecoration(labelText: 'Cihaz adı'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Cihaz adı gerekli' : null,
              ),
              const SizedBox(height: 24),
              if (_error != null) Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
              FilledButton(
                onPressed: _loading ? null : _submit,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _loading ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Kur'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
