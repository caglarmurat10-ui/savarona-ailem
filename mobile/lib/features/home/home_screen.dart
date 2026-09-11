import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/config.dart';
import '../../models/member_location.dart';
import '../../models/permission_health.dart';
import '../../services/api_client.dart';
import '../../services/live_socket.dart';
import '../../services/native_tracking_service.dart';
import '../map/live_map.dart';
import '../member/member_detail_screen.dart';
import '../permission/permission_health_screen.dart';
import '../sos/sos_button.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api});
  final ApiClient api;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final LiveSocket _live = LiveSocket(widget.api);
  final NativeTrackingService _native = NativeTrackingService();
  StreamSubscription? _liveSub;
  StreamSubscription? _connectionSub;
  List<MemberLocation> _members = const [];
  bool _loading = true;
  bool _trackingBusy = false;
  PermissionHealth? _trackingHealth;
  LiveConnectionState _connection = LiveConnectionState.connecting;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshTrackingStatus();
  }

  Future<void> _load() async {
    try {
      _members = await widget.api.snapshot();
      _liveSub = _live.events.listen(_onLive);
      _connectionSub = _live.connectionState.listen((s) {
        if (mounted) setState(() => _connection = s);
      });
      await Future.wait([_live.start(), _refreshTrackingStatus()]);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshTrackingStatus() async {
    try {
      final h = await _native.status();
      if (mounted) setState(() => _trackingHealth = h);
    } catch (_) {}
  }

  Future<void> _startTracking() async {
    if (_trackingBusy) return;
    setState(() => _trackingBusy = true);
    try {
      final granted = await _native.requestPermissions();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Arka plan konum izni gerekli. İzin ekranından “Her zaman” erişimini açın.')),
          );
        }
        await _native.openAppSettings();
        await _refreshTrackingStatus();
        return;
      }
      final token = await widget.api.deviceToken();
      if (token == null) throw StateError('Cihaz tokenı yok');
      await _native.start(apiBaseUrl: AppConfig.apiBaseUrl, deviceToken: token);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await _refreshTrackingStatus();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Takip başlatılamadı: $e')));
    } finally {
      if (mounted) setState(() => _trackingBusy = false);
    }
  }

  void _onLive(Map<String, dynamic> e) {
    if (e['type'] != 'location' && e['type'] != 'heartbeat' && e['type'] != 'device_stale') return;
    final id = e['member_id'] as String?;
    if (id == null) return;
    final i = _members.indexWhere((m) => m.memberId == id);
    if (i < 0) return;
    final copy = [..._members];
    copy[i] = copy[i].copyWithLive(e);
    if (mounted) setState(() => _members = copy);
  }

  String age(MemberLocation m) {
    final t = m.lastSeenAt;
    if (t == null) return 'Henüz veri yok';
    final s = DateTime.now().difference(t).inSeconds;
    if (s < 10) return 'Canlı';
    if (s < 90) return '$s sn önce';
    if (s < 180) return 'Gecikmeli';
    return 'Çevrimdışı';
  }

  void _openMember(MemberLocation member) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MemberDetailScreen(
          member: member,
          api: widget.api,
          connectionAge: age(member),
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _liveSub?.cancel();
    _connectionSub?.cancel();
    _live.stop();
    super.dispose();
  }

  Widget? _connectionBanner() {
    if (_connection == LiveConnectionState.live) return null;
    final label = _connection == LiveConnectionState.connecting ? 'Bağlanıyor…' : 'Bağlantı kesildi, yeniden deneniyor…';
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.tertiaryContainer,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(child: Text(label, style: Theme.of(context).textTheme.labelMedium)),
    );
  }

  Widget? _trackingBanner() {
    final h = _trackingHealth;
    if (h == null || h.healthy) return null;
    final permissionLost = h.permissionState == TrackingPermissionState.permissionLost ||
        h.permissionState == TrackingPermissionState.denied;
    final text = !h.trackingRequested
        ? 'Bu telefon henüz canlı konum paylaşmıyor.'
        : permissionLost
            ? 'Konum izni kapalı. Aileniz bu telefonun yeni konumunu göremez.'
            : h.permissionState == TrackingPermissionState.grantedWhenInUse
                ? 'Arka planda sürekli takip için “Her zaman” konum izni gerekli.'
                : 'Konum paylaşımı şu anda aktif değil.';
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          const Icon(Icons.location_off_outlined),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
          TextButton(
            onPressed: _trackingBusy ? null : _startTracking,
            child: Text(_trackingBusy ? 'Başlatılıyor…' : 'Başlat'),
          ),
        ]),
      ),
    );
  }

  Future<void> _showInvite() async {
    try {
      final code = await widget.api.createInvite();
      if (!mounted) return;
      showDialog(context: context, builder: (_) => AlertDialog(
        title: const Text('Davet kodu'),
        content: SelectableText(code, style: const TextStyle(fontSize: 28, letterSpacing: 2)),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Kapat'))],
      ));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Davet oluşturulamadı (${e.code})')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final connectionBanner = _connectionBanner();
    final trackingBanner = _trackingBanner();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Savarona Ailem'),
        actions: [
          IconButton(icon: const Icon(Icons.person_add_alt), tooltip: 'Davet oluştur', onPressed: _showInvite),
          IconButton(
            icon: const Icon(Icons.health_and_safety_outlined),
            tooltip: 'İzin durumu',
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PermissionHealthScreen(api: widget.api)));
              await _refreshTrackingStatus();
            },
          ),
        ],
      ),
      body: Column(children: [
        if (connectionBanner != null) connectionBanner,
        if (trackingBanner != null) trackingBanner,
        Expanded(
          flex: 5,
          child: LiveFamilyMap(
            members: _members,
            onMemberTap: _openMember,
          ),
        ),
        Expanded(flex: 4, child: ListView.builder(
          itemCount: _members.length,
          itemBuilder: (context, i) {
            final m = _members[i];
            final permissionText = m.permissionState == 'permission_lost' ? ' • Konum izni kapalı' : '';
            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(m.name),
              subtitle: Text('${m.liveSpeedKmh?.toStringAsFixed(0) ?? '—'} km/sa • 🔋 ${m.batteryPct ?? '—'}% • ${age(m)}$permissionText'),
              trailing: m.headingDeg == null ? null : Text('${m.headingDeg!.round()}°'),
              onTap: () => _openMember(m),
            );
          },
        )),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SosButton(onSos: widget.api.sendSos),
        ),
      ]),
    );
  }
}
