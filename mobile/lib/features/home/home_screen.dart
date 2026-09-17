import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/config.dart';
import '../../core/status_colors.dart';
import '../../models/member_location.dart';
import '../../models/permission_health.dart';
import '../../services/api_client.dart';
import '../../services/app_update_service.dart';
import '../../services/live_socket.dart';
import '../../services/native_tracking_service.dart';
import '../map/live_map.dart';
import '../member/member_detail_screen.dart';
import '../permission/permission_health_screen.dart';
import '../sos/sos_button.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api, required this.onAccountDeleted});
  final ApiClient api;
  final VoidCallback onAccountDeleted;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final LiveSocket _live = LiveSocket(widget.api);
  final NativeTrackingService _native = NativeTrackingService();
  final AppUpdateService _updater = AppUpdateService();
  StreamSubscription? _liveSub;
  StreamSubscription? _connectionSub;
  Timer? _snapshotTimer;
  Timer? _ageTicker;
  List<MemberLocation> _members = const [];
  bool _loading = true;
  bool _trackingBusy = false;
  bool _deleting = false;
  bool _updateDialogOpen = false;
  bool _snapshotRefreshing = false;
  PermissionHealth? _trackingHealth;
  LiveConnectionState _connection = LiveConnectionState.connecting;

  List<MemberLocation> get _visibleMembers {
    final byName = <String, MemberLocation>{};
    for (final member in _members) {
      final key = member.name.trim().toLowerCase();
      final current = byName[key];
      if (current == null || _memberFreshness(member) > _memberFreshness(current)) {
        byName[key] = member;
      }
    }
    return byName.values.toList(growable: false);
  }

  int _memberFreshness(MemberLocation member) {
    final seen = member.lastSeenAt?.millisecondsSinceEpoch ?? -1;
    final location = member.locationAt?.millisecondsSinceEpoch ?? -1;
    return seen > location ? seen : location;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _ageTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshTrackingStatus());
      unawaited(_refreshSnapshot());
      unawaited(_checkForUpdate());
    }
  }

  Future<void> _load() async {
    try {
      _members = await widget.api.snapshot();
      _liveSub = _live.events.listen(_onLive);
      _connectionSub = _live.connectionState.listen((s) {
        if (mounted) setState(() => _connection = s);
      });
      await Future.wait([_live.start(), _refreshTrackingStatus()]);
      _snapshotTimer ??= Timer.periodic(
        const Duration(seconds: 30),
        (_) => unawaited(_refreshSnapshot()),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        unawaited(_checkForUpdate());
      }
    }
  }

  Future<void> _refreshSnapshot() async {
    if (_snapshotRefreshing) return;
    _snapshotRefreshing = true;
    try {
      final members = await widget.api.snapshot();
      if (mounted) setState(() => _members = members);
    } catch (_) {
      // Keep the last good snapshot when the network is temporarily unavailable.
    } finally {
      _snapshotRefreshing = false;
    }
  }

  Future<void> _checkForUpdate() async {
    if (_updateDialogOpen) return;
    try {
      final release = await _updater.check();
      if (!mounted || release == null || _updateDialogOpen) return;
      _updateDialogOpen = true;
      var busy = false;
      String? error;
      await showDialog<void>(
        context: context,
        barrierDismissible: !release.mandatory,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Savarona Ailem güncellemesi'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Yeni sürüm: ${release.versionName} (${release.versionCode})'),
                const SizedBox(height: 8),
                if (release.notes.isNotEmpty) Text(release.notes),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
            actions: [
              if (!release.mandatory)
                TextButton(
                  onPressed: busy ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Sonra'),
                ),
              FilledButton.icon(
                icon: busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.system_update_alt),
                label: Text(busy ? 'İndiriliyor…' : 'Güncelle'),
                onPressed: busy
                    ? null
                    : () async {
                        setDialogState(() {
                          busy = true;
                          error = null;
                        });
                        try {
                          final result = await _updater.downloadAndInstall(release);
                          if (!context.mounted) return;
                          setDialogState(() {
                            busy = false;
                            if (result == 'permission_required') {
                              error = 'Android, bu uygulamaya yükleme izni istiyor. Açılan ayarda izin verip tekrar Güncelle’ye basın.';
                            } else if (result != 'install_started') {
                              error = 'Güncelleme başlatılamadı: $result';
                            }
                          });
                        } catch (e) {
                          if (!context.mounted) return;
                          setDialogState(() {
                            busy = false;
                            error = 'Güncelleme indirilemedi. İnternet bağlantısını kontrol edip tekrar deneyin.';
                          });
                        }
                      },
              ),
            ],
          ),
        ),
      );
    } catch (_) {
      // Güncelleme kontrolü uygulamanın normal kullanımını engellemez.
    } finally {
      _updateDialogOpen = false;
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
    if (e['type'] == 'member_deleted') {
      if (mounted) setState(() => _members = _members.where((m) => m.memberId != e['member_id']).toList());
      return;
    }
    if (e['type'] == 'member_joined') { unawaited(_refreshSnapshot()); return; }
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
    final t = m.locationAt ?? m.lastSeenAt;
    if (t == null) return 'Henüz konum yok';
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
    _snapshotTimer?.cancel();
    _ageTicker?.cancel();
    _live.stop();
    super.dispose();
  }

  Widget? _connectionBanner() {
    if (_connection == LiveConnectionState.live) return null;
    final label = _connection == LiveConnectionState.connecting ? 'Bağlanıyor…' : 'Bağlantı kesildi, yeniden deneniyor…';
    return _FloatingStatusBanner(
      icon: Icons.wifi_tethering_rounded,
      text: label,
      status: LiveStatus.delayed,
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
    return _FloatingStatusBanner(
      icon: Icons.location_off_outlined,
      text: text,
      status: LiveStatus.offline,
      action: TextButton(
        onPressed: _trackingBusy ? null : _startTracking,
        child: Text(_trackingBusy ? 'Başlatılıyor…' : 'Başlat'),
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

  Future<void> _deleteAccount() async {
    if (_deleting) return;
    final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Hesabımı kalıcı olarak sil'),
      content: const Text('Hesabınız, tüm cihaz erişimleriniz, konum geçmişiniz ve size ait olaylar kalıcı olarak silinir. Paylaşım durur. Diğer aile üyelerinin verileri silinmez; aile sahibiyseniz sahiplik kalan bir üyeye geçer. Tek üyeyseniz aile grubu da silinir. Bu işlem geri alınamaz.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Vazgeç')),
        TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Hesabımı sil')),
      ],
    ));
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await _native.stop();
      await widget.api.deleteAccount();
      await _live.stop();
      await _native.clearAccount();
      await widget.api.clearSession();
      if (mounted) widget.onAccountDeleted();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('İşlem tamamlanamadı. Konum paylaşımı durduruldu. Bağlantınızı kontrol edip yeniden deneyin.'),
      ));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final connectionBanner = _connectionBanner();
    final trackingBanner = _trackingBanner();
    final visibleMembers = _visibleMembers;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Savarona Ailem'),
        actions: [
          PopupMenuButton<String>(tooltip: 'Hesabım', enabled: !_deleting,
            onSelected: (_) => _deleteAccount(),
            itemBuilder: (_) => [const PopupMenuItem(value: 'delete', child: Text('Hesabımı sil'))],
            icon: const Icon(Icons.manage_accounts_outlined)),
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
      body: Stack(
        children: [
          Positioned.fill(
            child: LiveFamilyMap(
              members: visibleMembers,
              onMemberTap: _openMember,
            ),
          ),
          if (connectionBanner != null || trackingBanner != null)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Column(
                children: [
                  if (connectionBanner != null) connectionBanner,
                  if (connectionBanner != null && trackingBanner != null) const SizedBox(height: 8),
                  if (trackingBanner != null) trackingBanner,
                ],
              ),
            ),
          DraggableScrollableSheet(
            initialChildSize: 0.32,
            minChildSize: 0.16,
            maxChildSize: 0.86,
            snap: true,
            snapSizes: const [0.16, 0.32, 0.86],
            builder: (context, scrollController) => _MemberSheet(
              scrollController: scrollController,
              members: visibleMembers,
              ageText: age,
              onMemberTap: _openMember,
              onSos: widget.api.sendSos,
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingStatusBanner extends StatelessWidget {
  const _FloatingStatusBanner({
    required this.icon,
    required this.text,
    required this.status,
    this.action,
  });

  final IconData icon;
  final String text;
  final LiveStatus status;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final statusColor = context.colorFor(status);
    return Material(
      color: colors.surface.withValues(alpha: 0.96),
      elevation: 3,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.16), shape: BoxShape.circle),
              child: Icon(icon, size: 17, color: statusColor),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
            if (action != null) action!,
          ],
        ),
      ),
    );
  }
}

class _MemberSheet extends StatelessWidget {
  const _MemberSheet({
    required this.scrollController,
    required this.members,
    required this.ageText,
    required this.onMemberTap,
    required this.onSos,
  });

  final ScrollController scrollController;
  final List<MemberLocation> members;
  final String Function(MemberLocation) ageText;
  final ValueChanged<MemberLocation> onMemberTap;
  final Future<void> Function() onSos;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      elevation: 10,
      shadowColor: Colors.black38,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: ListView(
        controller: scrollController,
        padding: EdgeInsets.zero,
        children: [
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Row(
              children: [
                Icon(Icons.groups_2_rounded, size: 20, color: colors.primary),
                const SizedBox(width: 8),
                Text('${members.length} aile üyesi', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: SosButton(onSos: onSos),
          ),
          if (members.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text('Aile üyesi bulunamadı.', style: Theme.of(context).textTheme.bodyMedium),
              ),
            )
          else
            for (final member in members)
              _MemberCard(
                member: member,
                ageText: ageText(member),
                onTap: () => onMemberTap(member),
              ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.member, required this.ageText, required this.onTap});

  final MemberLocation member;
  final String ageText;
  final VoidCallback onTap;

  LiveStatus get _status {
    final seen = member.lastSeenAt;
    if (seen == null) return LiveStatus.offline;
    final age = DateTime.now().difference(seen);
    if (age <= const Duration(seconds: 45)) return LiveStatus.live;
    if (age <= const Duration(minutes: 3)) return LiveStatus.delayed;
    return LiveStatus.offline;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final statusColor = context.colorFor(_status);
    final permissionLost = member.permissionState == 'permission_lost';
    final initial = member.name.isEmpty ? '?' : member.name.characters.first.toUpperCase();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Material(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: colors.primaryContainer,
                      child: Text(
                        initial,
                        style: TextStyle(fontWeight: FontWeight.bold, color: colors.onPrimaryContainer),
                      ),
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: colors.surfaceContainerHigh, width: 2.5),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(member.name, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        '${member.liveSpeedKmh?.toStringAsFixed(0) ?? '—'} km/sa • 🔋 ${member.batteryPct ?? '—'}%'
                        '${permissionLost ? ' • Konum izni kapalı' : ''}',
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      ageText,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    if (member.headingDeg != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('${member.headingDeg!.round()}°', style: Theme.of(context).textTheme.labelSmall),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
