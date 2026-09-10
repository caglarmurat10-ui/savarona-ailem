import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../models/member_location.dart';

class LiveFamilyMap extends StatelessWidget {
  const LiveFamilyMap({super.key, required this.members});
  final List<MemberLocation> members;

  @override
  Widget build(BuildContext context) {
    final located = members.where((m) => m.lat != null && m.lng != null).toList();
    final center = located.isEmpty ? const LatLng(36.2, 29.65) : LatLng(located.first.lat!, located.first.lng!);
    return FlutterMap(
      options: MapOptions(initialCenter: center, initialZoom: located.isEmpty ? 8 : 14),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.savarona.ailem',
        ),
        MarkerLayer(markers: [
          for (final m in located)
            Marker(
              point: LatLng(m.lat!, m.lng!),
              width: 120,
              height: 70,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.location_on, size: 34),
                DecoratedBox(
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    child: Text('${m.name}  ${m.liveSpeedKmh?.toStringAsFixed(0) ?? '—'} km/sa', maxLines: 1),
                  ),
                ),
              ]),
            ),
        ]),
      ],
    );
  }
}
