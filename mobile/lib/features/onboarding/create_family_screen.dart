import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import '../../services/api_client.dart';

class CreateFamilyScreen extends StatefulWidget {
  const CreateFamilyScreen({super.key, required this.api, required this.onReady});
  final ApiClient api;
  final VoidCallback onReady;
  @override
  State<CreateFamilyScreen> createState() => _CreateFamilyScreenState();
}

class _CreateFamilyScreenState extends State<CreateFamilyScreen> {
  final _form = GlobalKey<FormState>();
  final _family = TextEditingController();
  final _name = TextEditingController();
  final _device = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _family.dispose(); _name.dispose(); _device.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    try {
      await widget.api.createFamily(familyName: _family.text.trim(), ownerName: _name.text.trim(),
        deviceName: _device.text.trim(), platform: Platform.isIOS ? 'ios' : 'android');
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onReady();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.code == 'rate_limited'
        ? 'Çok fazla deneme yapıldı. Bir dakika sonra tekrar deneyin.'
        : 'Aile oluşturulamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Aile oluşturulamadı. Lütfen tekrar deneyin.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Yeni aile oluştur')),
    body: SafeArea(child: Form(key: _form, child: ListView(
      padding: const EdgeInsets.all(24), children: [
        const Text('Kendi özel aile grubunuzu oluşturun. Diğer kişiler yalnızca sizin paylaşacağınız tek kullanımlık davet koduyla katılabilir.'),
        const SizedBox(height: 16),
        const Text('Konum paylaşımı ayrıca izninizi gerektirir. Hesabınızı ana ekrandaki Hesabım menüsünden silebilirsiniz. Oturum bu cihazda saklanır; uygulamayı silmek hesabınızı silmez.'),
        const SizedBox(height: 24),
        for (final field in [(_family, 'Aile adı'), (_name, 'Adınız'), (_device, 'Cihaz adı')]) ...[
          TextFormField(controller: field.$1, enabled: !_busy, maxLength: 80,
            decoration: InputDecoration(labelText: field.$2),
            validator: (v) => v == null || v.trim().isEmpty ? 'Bu alan gerekli' : null),
          const SizedBox(height: 12),
        ],
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Oluşturuluyor…' : 'Aile oluştur')),
      ],
    ))),
  );
}
