import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../core/status_colors.dart';
import '../../models/member_location.dart';

class LiveFamilyMap extends StatefulWidget {
  const LiveFamilyMap({super.key, required this.members, this.onMemberTap});
  final List<MemberLocation> members;
  final ValueChanged<MemberLocation>? onMemberTap;

  @override
  State<LiveFamilyMap> createState() => _LiveFamilyMapState();
}

class _LiveFamilyMapState extends State<LiveFamilyMap>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  late final AnimationController _moveController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..addListener(_onMoveTick);
  final Map<String, LatLng> _fromPositions = {};
  final Map<String, LatLng> _toPositions = {};
  final Map<String, LatLng> _displayPositions = {};
  bool _mapReady = false;
  bool _hasFitted = false;

  List<MemberLocation> get _located => widget.members
      .where((member) => member.lat != null && member.lng != null)
      .toList(growable: false);

  LatLng _pointFor(MemberLocation member) => LatLng(member.lat!, member.lng!);

  LatLng _displayedPointFor(MemberLocation member) =>
      _displayPositions[member.memberId] ?? _pointFor(member);

  @override
  void initState() {
    super.initState();
    for (final member in _located) {
      final point = _pointFor(member);
      _toPositions[member.memberId] = point;
      _displayPositions[member.memberId] = point;
    }
  }

  void _syncTargets() {
    var changed = false;
    for (final member in _located) {
      final point = _pointFor(member);
      final previousTarget = _toPositions[member.memberId];
      if (previousTarget == null) {
        _toPositions[member.memberId] = point;
        _displayPositions[member.memberId] = point;
        continue;
      }
      if (previousTarget.latitude == point.latitude &&
          previousTarget.longitude == point.longitude) {
        continue;
      }
      _fromPositions[member.memberId] =
          _displayPositions[member.memberId] ?? previousTarget;
      _toPositions[member.memberId] = point;
      changed = true;
    }
    if (changed) {
      _moveController.forward(from: 0);
    }
  }

  void _onMoveTick() {
    final t = Curves.easeOutCubic.transform(_moveController.value);
    for (final entry in _toPositions.entries) {
      final from = _fromPositions[entry.key];
      if (from == null) {
        _displayPositions[entry.key] = entry.value;
        continue;
      }
      _displayPositions[entry.key] = LatLng(
        from.latitude + (entry.value.latitude - from.latitude) * t,
        from.longitude + (entry.value.longitude - from.longitude) * t,
      );
    }
    if (mounted) setState(() {});
  }

  void _fitMembers() {
    if (!_mapReady || _located.isEmpty) return;
    final points = _located.map(_pointFor).toList(growable: false);
    if (points.length == 1) {
      _mapController.move(points.single, 15.5);
      return;
    }
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(points),
        padding: const EdgeInsets.all(56),
        maxZoom: 15.5,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant LiveFamilyMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTargets();
    if (!_hasFitted && _located.isNotEmpty && _mapReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _hasFitted = true;
        _fitMembers();
      });
    }
  }

  @override
  void dispose() {
    _moveController.dispose();
    super.dispose();
  }

  LiveStatus _statusFor(MemberLocation member) {
    final age = member.lastSeenAt == null
        ? const Duration(days: 1)
        : DateTime.now().difference(member.lastSeenAt!);
    if (age <= const Duration(seconds: 45)) return LiveStatus.live;
    if (age <= const Duration(minutes: 3)) return LiveStatus.delayed;
    return LiveStatus.offline;
  }

  @override
  Widget build(BuildContext context) {
    final located = _located;
    final center = located.isEmpty ? const LatLng(36.2, 29.65) : _pointFor(located.first);
    final colors = Theme.of(context).colorScheme;

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: located.isEmpty ? 8 : 14,
            onMapReady: () {
              _mapReady = true;
              if (!_hasFitted && located.isNotEmpty) {
                _hasFitted = true;
                WidgetsBinding.instance.addPostFrameCallback((_) => _fitMembers());
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.savarona.ailem',
            ),
            CircleLayer(
              circles: [
                for (final member in located)
                  CircleMarker(
                    point: _displayedPointFor(member),
                    radius: (member.accuracyM ?? 35).clamp(12, 1200),
                    useRadiusInMeter: true,
                    color: context.colorFor(_statusFor(member)).withValues(alpha: 0.14),
                    borderColor: context.colorFor(_statusFor(member)).withValues(alpha: 0.5),
                    borderStrokeWidth: 1.5,
                  ),
              ],
            ),
            MarkerLayer(
              markers: [for (final member in located) _marker(context, member)],
            ),
            SimpleAttributionWidget(source: const Text('OpenStreetMap contributors')),
          ],
        ),
        if (located.isNotEmpty)
          Positioned(
            right: 12,
            bottom: MediaQuery.sizeOf(context).height * 0.16 + 16,
            child: _MapIconButton(
              tooltip: 'Tüm aileyi göster',
              icon: Icons.fit_screen_outlined,
              onPressed: _fitMembers,
            ),
          ),
        if (located.isEmpty)
          Center(
            child: Card(
              margin: const EdgeInsets.all(24),
              color: colors.surface.withValues(alpha: 0.95),
              child: const Padding(
                padding: EdgeInsets.all(18),
                child: Text('Aile üyelerinden konum bekleniyor.'),
              ),
            ),
          ),
      ],
    );
  }

  Marker _marker(BuildContext context, MemberLocation member) {
    final statusColor = context.colorFor(_statusFor(member));
    final heading = member.headingDeg;
    return Marker(
      point: _displayedPointFor(member),
      width: 132,
      height: 92,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onMemberTap == null ? null : () => widget.onMemberTap!(member),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Theme.of(context).colorScheme.surface, width: 3),
                    boxShadow: const [BoxShadow(blurRadius: 7, color: Colors.black26)],
                  ),
                  child: Icon(Icons.person, color: Theme.of(context).colorScheme.onPrimary, size: 24),
                ),
                if (heading != null)
                  Transform.translate(
                    offset: const Offset(0, -29),
                    child: Transform.rotate(
                      angle: heading * math.pi / 180,
                      child: Icon(Icons.navigation, size: 19, color: statusColor),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(9),
                boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black12)],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                child: Text(
                  '${member.name}  ${member.liveSpeedKmh?.toStringAsFixed(0) ?? '—'} km/sa',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapIconButton extends StatelessWidget {
  const _MapIconButton({required this.tooltip, required this.icon, required this.onPressed});
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.94),
        shape: const CircleBorder(),
        elevation: 2,
        child: IconButton(tooltip: tooltip, icon: Icon(icon), onPressed: onPressed),
      );
}
