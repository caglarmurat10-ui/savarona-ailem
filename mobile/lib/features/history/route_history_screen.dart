import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../models/route_point.dart';
import '../../services/api_client.dart';

class RouteHistoryScreen extends StatefulWidget {
  const RouteHistoryScreen({super.key, required this.api, required this.memberId, required this.memberName});
  final ApiClient api;
  final String memberId;
  final String memberName;

  @override
  State<RouteHistoryScreen> createState() => _RouteHistoryScreenState();
}

class _RouteHistoryScreenState extends State<RouteHistoryScreen> {
  List<RoutePoint> _points = const [];
  bool _loading = true;
  String? _error;
  Duration _window = const Duration(hours: 24);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final points = await widget.api.history(
        memberId: widget.memberId,
        from: DateTime.now().subtract(_window),
      );
      if (mounted) setState(() => _points = points);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = 'Geçmiş alınamadı (${e.code}).');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final line = _points.map((p) => LatLng(p.lat, p.lng)).toList();
    final center = line.isEmpty ? const LatLng(36.2, 29.65) : line.last;
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.memberName} — Rota Geçmişi'),
        actions: [
          PopupMenuButton<Duration>(
            initialValue: _window,
            onSelected: (d) { _window = d; _load(); },
            itemBuilder: (_) => const [
              PopupMenuItem(value: Duration(hours: 6), child: Text('Son 6 saat')),
              PopupMenuItem(value: Duration(hours: 24), child: Text('Son 24 saat')),
              PopupMenuItem(value: Duration(days: 7), child: Text('Son 7 gün')),
            ],
          ),
        ],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
          ? Center(child: Text(_error!))
          : line.isEmpty
            ? const Center(child: Text('Bu aralıkta kayıtlı konum yok.'))
            : FlutterMap(
                options: MapOptions(initialCenter: center, initialZoom: 13),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.savarona.ailem',
                  ),
                  PolylineLayer(polylines: [
                    Polyline(points: line, strokeWidth: 4, color: Theme.of(context).colorScheme.primary),
                  ]),
                  MarkerLayer(markers: [
                    Marker(point: line.last, width: 32, height: 32, child: const Icon(Icons.flag, color: Colors.red)),
                  ]),
                ],
              ),
    );
  }
}
