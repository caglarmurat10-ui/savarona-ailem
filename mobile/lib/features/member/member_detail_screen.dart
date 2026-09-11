import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../models/member_location.dart';
import '../../services/api_client.dart';
import '../../services/live_socket.dart';
import '../history/route_history_screen.dart';

class MemberDetailScreen extends StatefulWidget {
  const MemberDetailScreen({
    super.key,
    required this.member,
    required this.api,
    required this.connectionAge,
  });

  final MemberLocation member;
  final ApiClient api;
  final String connectionAge;

  @override
  State<MemberDetailScreen> createState() => _MemberDetailScreenState();
}

class _MemberDetailScreenState extends State<MemberDetailScreen>
    with SingleTickerProviderStateMixin {
  late MemberLocation _member;
  late final LiveSocket _live;
  final MapController _mapController = MapController();
  StreamSubscription? _liveSub;
  StreamSubscription? _connectionSub;
  Timer? _ageTimer;
  late final AnimationController _moveAnimation;
  LiveConnectionState _connection = LiveConnectionState.connecting;
  LatLng? _displayPosition;
  LatLng? _moveFrom;
  LatLng? _moveTo;
  bool _follow = true;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _member = widget.member;
    _displayPosition = _pointFor(_member);
    _live = LiveSocket(widget.api);
    _moveAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..addListener(_animatePosition);

    _liveSub = _live.events.listen(_onLive);
    _connectionSub = _live.connectionState.listen((state) {
      if (mounted) setState(() => _connection = state);
    });
    _ageTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _live.start();
  }

  LatLng? _pointFor(MemberLocation m) {
    if (m.lat == null || m.lng == null) return null;
    return LatLng(m.lat!, m.lng!);
  }

  void _onLive(Map<String, dynamic> event) {
    final type = event['type'];
    if (type != 'location' && type != 'heartbeat' && type != 'device_stale') return;
    if (event['member_id'] != _member.memberId) return;

    final next = _member.copyWithLive(event);
    final nextPoint = _pointFor(next);
    final currentPoint = _displayPosition ?? _pointFor(_member);

    if (type == 'location' && nextPoint != null && currentPoint != null &&
        (nextPoint.latitude != currentPoint.latitude || nextPoint.longitude != currentPoint.longitude)) {
      _moveFrom = currentPoint;
      _moveTo = nextPoint;
      _member = next;
      _moveAnimation.forward(from: 0);
      return;
    }

    if (mounted) {
      setState(() {
        _member = next;
        _displayPosition ??= nextPoint;
      });
    }
  }

  void _animatePosition() {
    final from = _moveFrom;
    final to = _moveTo;
    if (!mounted || from == null || to == null) return;
    final t = Curves.easeOutCubic.transform(_moveAnimation.value);
    final p = LatLng(
      from.latitude + (to.latitude - from.latitude) * t,
      from.longitude + (to.longitude - from.longitude) * t,
    );
    setState(() => _displayPosition = p);
    if (_follow && _mapReady) {
      _mapController.move(p, 16.5);
    }
  }

  String _age() {
    final t = _member.lastSeenAt;
    if (t == null) return 'Henüz veri yok';
    final seconds = DateTime.now().difference(t).inSeconds;
    if (seconds < 10) return 'Canlı';
    if (seconds < 90) return '$seconds sn önce';
    if (seconds < 180) return 'Gecikmeli';
    return 'Çevrimdışı';
  }

  Color _statusColor(BuildContext context) {
    final age = _age();
    if (age == 'Canlı' && _connection == LiveConnectionState.live) {
      return Colors.green;
    }
    if (age == 'Çevrimdışı') return Theme.of(context).colorScheme.error;
    return Colors.orange;
  }

  String _connectionText() {
    if (_connection == LiveConnectionState.live) return _age();
    if (_connection == LiveConnectionState.connecting) return 'Bağlanıyor…';
    return 'Yeniden bağlanıyor…';
  }

  void _centerOnMember() {
    final p = _displayPosition;
    if (p == null || !_mapReady) return;
    setState(() => _follow = true);
    _mapController.move(p, 16.5);
  }

  @override
  void dispose() {
    _ageTimer?.cancel();
    _liveSub?.cancel();
    _connectionSub?.cancel();
    _live.stop();
    _moveAnimation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final position = _displayPosition;
    final speed = _member.liveSpeedKmh;
    final heading = _member.headingDeg;

    return Scaffold(
      appBar: AppBar(
        title: Text(_member.name),
        actions: [
          IconButton(
            tooltip: _follow ? 'Canlı takip açık' : 'Canlı takibi aç',
            icon: Icon(_follow ? Icons.gps_fixed : Icons.gps_not_fixed),
            onPressed: () {
              if (_follow) {
                setState(() => _follow = false);
              } else {
                _centerOnMember();
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: position == null
                ? const Center(child: Text('Bu kişi için henüz konum verisi yok.'))
                : FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: position,
                      initialZoom: 16.5,
                      onMapReady: () => _mapReady = true,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.savarona.ailem',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: position,
                            width: 130,
                            height: 92,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Container(
                                      width: 52,
                                      height: 52,
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.primary,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Theme.of(context).colorScheme.surface,
                                          width: 4,
                                        ),
                                        boxShadow: const [
                                          BoxShadow(blurRadius: 8, color: Colors.black26),
                                        ],
                                      ),
                                      child: Icon(
                                        Icons.person,
                                        color: Theme.of(context).colorScheme.onPrimary,
                                        size: 30,
                                      ),
                                    ),
                                    if (heading != null)
                                      Transform.translate(
                                        offset: const Offset(0, -34),
                                        child: Transform.rotate(
                                          angle: heading * math.pi / 180,
                                          child: Icon(
                                            Icons.navigation,
                                            size: 22,
                                            color: Theme.of(context).colorScheme.primary,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.surface,
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: const [BoxShadow(blurRadius: 5, color: Colors.black12)],
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                    child: Text(
                                      speed == null ? _member.name : '${_member.name}  ${speed.toStringAsFixed(0)} km/sa',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
          Positioned(
            top: 12,
            left: 12,
            child: Material(
              elevation: 2,
              borderRadius: BorderRadius.circular(18),
              color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.94),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(color: _statusColor(context), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 7),
                    Text(_connectionText(), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
          if (position != null)
            Positioned(
              right: 14,
              bottom: 238,
              child: FloatingActionButton.small(
                heroTag: 'center-member-${_member.memberId}',
                tooltip: 'Kişiyi takip et',
                onPressed: _centerOnMember,
                child: Icon(_follow ? Icons.gps_fixed : Icons.my_location),
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Card(
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                elevation: 6,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            child: Text(
                              _member.name.isEmpty ? '?' : _member.name.characters.first.toUpperCase(),
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_member.name, style: Theme.of(context).textTheme.titleLarge),
                                Text(_connectionText(), style: Theme.of(context).textTheme.bodyMedium),
                              ],
                            ),
                          ),
                          Text(
                            speed == null ? '— km/sa' : '${speed.toStringAsFixed(0)} km/sa',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _metric(context, Icons.battery_full, 'Pil', _member.batteryPct == null ? '—' : '${_member.batteryPct}%')),
                          Expanded(child: _metric(context, Icons.gps_fixed, 'Doğruluk', _member.accuracyM == null ? '—' : '±${_member.accuracyM!.round()} m')),
                          Expanded(child: _metric(context, Icons.directions_walk, 'Durum', _member.activity ?? '—')),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.route),
                          label: const Text('Rota geçmişi'),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => RouteHistoryScreen(
                                api: widget.api,
                                memberId: _member.memberId,
                                memberName: _member.name,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(BuildContext context, IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, size: 20),
        const SizedBox(height: 3),
        Text(value, style: Theme.of(context).textTheme.labelLarge, maxLines: 1),
        Text(label, style: Theme.of(context).textTheme.labelSmall, maxLines: 1),
      ],
    );
  }
}
