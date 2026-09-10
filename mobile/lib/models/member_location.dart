class MemberLocation {
  const MemberLocation({
    required this.memberId,
    required this.name,
    this.deviceId,
    this.lat,
    this.lng,
    this.speedMps,
    this.headingDeg,
    this.accuracyM,
    this.batteryPct,
    this.lastSeenAt,
    this.locationAt,
    this.permissionState,
    this.appState,
    this.activity,
  });

  final String memberId;
  final String name;
  final String? deviceId;
  final double? lat;
  final double? lng;
  final double? speedMps;
  final double? headingDeg;
  final double? accuracyM;
  final int? batteryPct;
  final DateTime? lastSeenAt;
  final DateTime? locationAt;
  final String? permissionState;
  final String? appState;
  final String? activity;

  double? get speedKmh => speedMps == null ? null : speedMps! * 3.6;

  double? get liveSpeedKmh {
    if (permissionState == 'permission_lost') return null;
    final t = locationAt;
    if (t == null) return null;
    final age = DateTime.now().difference(t);
    if (age > const Duration(seconds: 45) || age < const Duration(seconds: -5)) return null;
    return speedKmh;
  }

  MemberLocation copyWithLive(Map<String, dynamic> j) {
    final type = j['type'] as String?;
    final isLocation = type == 'location';
    final heartbeatAt = (j['received_at'] as num?)?.toInt() ?? (j['ts'] as num?)?.toInt();
    final staleAt = (j['last_seen_at'] as num?)?.toInt();
    return MemberLocation(
      memberId: memberId,
      name: (j['member_name'] as String?) ?? name,
      deviceId: (j['device_id'] as String?) ?? deviceId,
      lat: isLocation ? ((j['lat'] as num?)?.toDouble() ?? lat) : lat,
      lng: isLocation ? ((j['lng'] as num?)?.toDouble() ?? lng) : lng,
      speedMps: isLocation ? (j['speed_mps'] as num?)?.toDouble() : speedMps,
      headingDeg: isLocation ? (j['heading_deg'] as num?)?.toDouble() : headingDeg,
      accuracyM: isLocation ? (j['accuracy_m'] as num?)?.toDouble() : accuracyM,
      batteryPct: (j['battery_pct'] as num?)?.toInt() ?? batteryPct,
      lastSeenAt: type == 'device_stale'
          ? (staleAt == null ? lastSeenAt : DateTime.fromMillisecondsSinceEpoch(staleAt))
          : (heartbeatAt == null ? lastSeenAt : DateTime.fromMillisecondsSinceEpoch(heartbeatAt)),
      locationAt: isLocation && j['captured_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch((j['captured_at'] as num).toInt())
          : locationAt,
      permissionState: (j['permission_state'] as String?) ?? permissionState,
      appState: (j['app_state'] as String?) ?? appState,
      activity: isLocation ? ((j['activity'] as String?) ?? activity) : activity,
    );
  }

  factory MemberLocation.fromSnapshot(Map<String, dynamic> j) => MemberLocation(
    memberId: j['member_id'] as String,
    name: (j['display_name'] as String?) ?? 'Aile Üyesi',
    deviceId: j['device_id'] as String?,
    lat: (j['lat'] as num?)?.toDouble(),
    lng: (j['lng'] as num?)?.toDouble(),
    speedMps: (j['speed_mps'] as num?)?.toDouble(),
    headingDeg: (j['heading_deg'] as num?)?.toDouble(),
    accuracyM: (j['accuracy_m'] as num?)?.toDouble(),
    batteryPct: (j['battery_pct'] as num?)?.toInt(),
    lastSeenAt: j['last_seen_at'] == null ? null : DateTime.fromMillisecondsSinceEpoch((j['last_seen_at'] as num).toInt()),
    locationAt: j['captured_at'] == null ? null : DateTime.fromMillisecondsSinceEpoch((j['captured_at'] as num).toInt()),
    permissionState: j['permission_state'] as String?,
    appState: j['app_state'] as String?,
    activity: j['activity'] as String?,
  );
}
