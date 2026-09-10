import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import '../../services/api_client.dart';

class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key, required this.api, required this.onJoined});
  final ApiClient api;
  final VoidCallback onJoined;

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _formKey = GlobalKey<FormState>();
  final _inviteCode = TextEditingController();
  final _memberName = TextEditingController();
  final _deviceName = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _inviteCode.dispose();
    _memberName.dispose();
    _deviceName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      await widget.api.join(
        inviteCode: _inviteCode.text.trim(),
        memberName: _memberName.text.trim(),
        deviceName: _deviceName.text.trim(),
        platform: Platform.isIOS ? 'ios' : 'android',
      );
      widget.onJoined();
    } on ApiException catch (e) {
      setState(() => _error = switch (e.code) {
        'invite_invalid_or_expired' => 'Davet kodu geçersiz ya da süresi dolmuş.',
        'rate_limited' => 'Çok fazla deneme yapıldı, biraz sonra tekrar deneyin.',
        _ => 'Katılım başarısız (${e.code}).',
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Aileye katıl')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextFormField(
                controller: _inviteCode,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Davet kodu'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Davet kodu gerekli' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _memberName,
                decoration: const InputDecoration(labelText: 'Adınız'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Ad gerekli' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _deviceName,
                decoration: const InputDecoration(labelText: 'Cihaz adı (ör. Ayşe iPhone)'),
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
                    : const Text('Katıl'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
