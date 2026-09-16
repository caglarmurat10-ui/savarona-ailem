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

  static const _windowLabels = {
    Duration(hours: 6): 'Son 6 saat',
    Duration(hours: 24): 'Son 24 saat',
    Duration(days: 7): 'Son 7 gün',
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final line = _points.map((p) => LatLng(p.lat, p.lng)).toList();
    final center = line.isEmpty ? const LatLng(36.2, 29.65) : line.last;
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.memberName} — Rota Geçmişi'),
        actions: [
          PopupMenuButton<Duration>(
            initialValue: _window,
            onSelected: (d) { setState(() => _window = d); _load(); },
            icon: const Icon(Icons.filter_alt_outlined),
            itemBuilder: (_) => [
              for (final entry in _windowLabels.entries)
                PopupMenuItem(value: entry.key, child: Text(entry.value)),
            ],
          ),
        ],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 40, color: colors.error),
                    const SizedBox(height: 12),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton.tonal(onPressed: _load, child: const Text('Tekrar dene')),
                  ],
                ),
              ),
            )
          : line.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.route_outlined, size: 40, color: colors.onSurfaceVariant),
                      const SizedBox(height: 12),
                      Text(
                        '${_windowLabels[_window]} içinde kayıtlı konum yok.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              )
            : Stack(
                children: [
                  FlutterMap(
                    options: MapOptions(initialCenter: center, initialZoom: 13),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.savarona.ailem',
                      ),
                      PolylineLayer(polylines: [
                        Polyline(points: line, strokeWidth: 4, color: colors.primary),
                      ]),
                      MarkerLayer(markers: [
                        Marker(
                          point: line.first,
                          width: 22,
                          height: 22,
                          child: Container(
                            decoration: BoxDecoration(
                              color: colors.outline,
                              shape: BoxShape.circle,
                              border: Border.all(color: colors.surface, width: 2),
                            ),
                          ),
                        ),
                        Marker(
                          point: line.last,
                          width: 34,
                          height: 34,
                          child: Icon(Icons.flag_rounded, color: colors.error),
                        ),
                      ]),
                    ],
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Material(
                      color: colors.surface.withValues(alpha: 0.94),
                      elevation: 2,
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Text(
                          '${line.length} nokta • ${_windowLabels[_window]}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
    );
  }
}
