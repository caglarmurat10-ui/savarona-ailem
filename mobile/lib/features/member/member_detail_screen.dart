import 'package:flutter/material.dart';
import '../../models/member_location.dart';
import '../../services/api_client.dart';
import '../history/route_history_screen.dart';

class MemberDetailScreen extends StatelessWidget {
  const MemberDetailScreen({super.key, required this.member, required this.api, required this.connectionAge});
  final MemberLocation member;
  final ApiClient api;
  final String connectionAge;

  Widget _row(BuildContext context, IconData icon, String label, String value) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: Text(value, style: Theme.of(context).textTheme.titleMedium),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(member.name)),
      body: ListView(
        children: [
          _row(context, Icons.wifi_tethering, 'Bağlantı', connectionAge),
          _row(context, Icons.speed, 'Hız', '${member.liveSpeedKmh?.toStringAsFixed(0) ?? '—'} km/sa'),
          _row(context, Icons.explore, 'Yön', member.headingDeg == null ? '—' : '${member.headingDeg!.round()}°'),
          _row(context, Icons.gps_fixed, 'Doğruluk', member.accuracyM == null ? '—' : '±${member.accuracyM!.round()} m'),
          _row(context, Icons.battery_full, 'Pil', member.batteryPct == null ? '—' : '${member.batteryPct}%'),
          _row(context, Icons.directions_walk, 'Aktivite', member.activity ?? '—'),
          if (member.permissionState != null)
            _row(context, Icons.privacy_tip_outlined, 'İzin durumu', member.permissionState!),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              icon: const Icon(Icons.route),
              label: const Text('Rota geçmişini göster'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => RouteHistoryScreen(api: api, memberId: member.memberId, memberName: member.name),
              )),
            ),
          ),
        ],
      ),
    );
  }
}
