import 'package:flutter/material.dart';
import '../../core/config.dart';
import '../../models/permission_health.dart';
import '../../services/api_client.dart';
import '../../services/native_tracking_service.dart';

class PermissionHealthScreen extends StatefulWidget {
  const PermissionHealthScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<PermissionHealthScreen> createState() => _PermissionHealthScreenState();
}

class _PermissionHealthScreenState extends State<PermissionHealthScreen> {
  final _native = NativeTrackingService();
  PermissionHealth? _health;
  bool _loading = true;
  bool _actionBusy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (mounted) setState(() => _loading = true);
    try {
      final health = await _native.status();
      if (mounted) setState(() => _health = health);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _start() async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      final granted = await _native.requestPermissions();
      if (!granted) {
        await _native.openAppSettings();
      } else {
        final token = await widget.api.deviceToken();
        if (token == null) throw StateError('Cihaz tokenı yok');
        await _native.start(apiBaseUrl: AppConfig.apiBaseUrl, deviceToken: token);
      }
    } finally {
      if (mounted) setState(() => _actionBusy = false);
      await _refresh();
    }
  }

  Future<void> _stop() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Konum paylaşımını durdur'),
        content: const Text('Bu telefon yeni konum göndermeyi bırakacak ve aile ekranında paylaşımın durduğu görülecek.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Durdur')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _native.stop();
    await _refresh();
  }

  String _fmt(DateTime? t) {
    if (t == null) return 'hiç';
    final s = DateTime.now().difference(t).inSeconds;
    if (s < 60) return '$s sn önce';
    if (s < 3600) return '${s ~/ 60} dk önce';
    return '${s ~/ 3600} sa önce';
  }

  @override
  Widget build(BuildContext context) {
    final h = _health;
    return Scaffold(
      appBar: AppBar(title: const Text('İzin ve Takip Durumu'), actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh)]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : h == null
              ? const Center(child: Text('Durum okunamadı.'))
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        color: h.healthy ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.errorContainer,
                        child: ListTile(
                          leading: Icon(h.healthy ? Icons.check_circle : Icons.warning_amber_rounded),
                          title: Text(h.healthy ? 'Takip sağlıklı çalışıyor' : 'Takip dikkat istiyor'),
                          subtitle: Text(h.permissionState.label),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ListTile(leading: const Icon(Icons.share_location), title: const Text('Paylaşım tercihi'), trailing: Text(h.trackingRequested ? 'Açık' : 'Kapalı')),
                      ListTile(leading: const Icon(Icons.location_on), title: const Text('Aktif takip'), trailing: Text(h.trackingActive ? 'Evet' : 'Hayır')),
                      if (h.foregroundServiceRunning != null)
                        ListTile(leading: const Icon(Icons.notifications_active), title: const Text('Foreground servis (Android)'), trailing: Text(h.foregroundServiceRunning! ? 'Çalışıyor' : 'Kapalı')),
                      ListTile(leading: const Icon(Icons.pending_actions), title: const Text('Kuyrukta bekleyen kayıt'), trailing: Text('${h.queuedCount}')),
                      ListTile(leading: const Icon(Icons.upload), title: const Text('Son gönderim denemesi'), trailing: Text(_fmt(h.lastSendAttemptAt))),
                      ListTile(leading: const Icon(Icons.cloud_done), title: const Text('Son başarılı gönderim'), trailing: Text(_fmt(h.lastSendSuccessAt))),
                      if (h.lastError != null)
                        ListTile(leading: const Icon(Icons.error_outline, color: Colors.red), title: const Text('Son hata'), subtitle: Text(h.lastError!)),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _actionBusy ? null : _start,
                        icon: const Icon(Icons.play_arrow),
                        label: const Padding(padding: EdgeInsets.all(12), child: Text('Konum paylaşımını başlat / düzelt')),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _actionBusy ? null : _native.openAppSettings,
                        icon: const Icon(Icons.settings),
                        label: const Text('Sistem uygulama ayarlarını aç'),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: h.trackingRequested && !_actionBusy ? _stop : null,
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: const Text('Konum paylaşımını durdur'),
                      ),
                    ],
                  ),
                ),
    );
  }
}
