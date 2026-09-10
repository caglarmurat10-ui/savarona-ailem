class RoutePoint {
  const RoutePoint({
    required this.capturedAt,
    required this.lat,
    required this.lng,
    this.accuracyM,
    this.speedMps,
    this.headingDeg,
    this.batteryPct,
    this.activity,
  });

  final DateTime capturedAt;
  final double lat;
  final double lng;
  final double? accuracyM;
  final double? speedMps;
  final double? headingDeg;
  final int? batteryPct;
  final String? activity;

  factory RoutePoint.fromJson(Map<String, dynamic> j) => RoutePoint(
    capturedAt: DateTime.fromMillisecondsSinceEpoch((j['captured_at'] as num).toInt()),
    lat: (j['lat'] as num).toDouble(),
    lng: (j['lng'] as num).toDouble(),
    accuracyM: (j['accuracy_m'] as num?)?.toDouble(),
    speedMps: (j['speed_mps'] as num?)?.toDouble(),
    headingDeg: (j['heading_deg'] as num?)?.toDouble(),
    batteryPct: (j['battery_pct'] as num?)?.toInt(),
    activity: j['activity'] as String?,
  );
}
