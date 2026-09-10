enum TrackingPermissionState {
  notRequested,
  grantedWhenInUse,
  grantedAlways,
  denied,
  permissionLost,
  unknown;

  static TrackingPermissionState fromWire(String? value) {
    switch (value) {
      case 'not_requested': return TrackingPermissionState.notRequested;
      case 'granted_when_in_use': return TrackingPermissionState.grantedWhenInUse;
      case 'granted_always': return TrackingPermissionState.grantedAlways;
      case 'denied': return TrackingPermissionState.denied;
      case 'permission_lost': return TrackingPermissionState.permissionLost;
      default: return TrackingPermissionState.unknown;
    }
  }

  String get label {
    switch (this) {
      case TrackingPermissionState.notRequested: return 'İzin henüz istenmedi';
      case TrackingPermissionState.grantedWhenInUse: return 'İzin: yalnızca uygulama açıkken';
      case TrackingPermissionState.grantedAlways: return 'İzin: her zaman (arka plan dahil)';
      case TrackingPermissionState.denied: return 'İzin reddedildi';
      case TrackingPermissionState.permissionLost: return 'İzin sonradan kapatıldı';
      case TrackingPermissionState.unknown: return 'Durum bilinmiyor';
    }
  }
}

class PermissionHealth {
  const PermissionHealth({
    required this.permissionState,
    required this.trackingActive,
    required this.trackingRequested,
    this.foregroundServiceRunning,
    required this.queuedCount,
    this.lastSendAttemptAt,
    this.lastSendSuccessAt,
    this.lastError,
  });

  final TrackingPermissionState permissionState;
  final bool trackingActive;
  final bool trackingRequested;
  final bool? foregroundServiceRunning;
  final int queuedCount;
  final DateTime? lastSendAttemptAt;
  final DateTime? lastSendSuccessAt;
  final String? lastError;

  bool get healthy =>
      trackingRequested &&
      trackingActive &&
      permissionState == TrackingPermissionState.grantedAlways &&
      lastError == null;

  factory PermissionHealth.fromMap(Map<String, dynamic> j) => PermissionHealth(
    permissionState: TrackingPermissionState.fromWire(j['permissionState'] as String?),
    trackingActive: j['trackingActive'] == true,
    trackingRequested: j['trackingRequested'] == true,
    foregroundServiceRunning: j['foregroundServiceRunning'] as bool?,
    queuedCount: (j['queuedCount'] as num?)?.toInt() ?? 0,
    lastSendAttemptAt: j['lastSendAttemptAt'] == null ? null : DateTime.fromMillisecondsSinceEpoch((j['lastSendAttemptAt'] as num).toInt()),
    lastSendSuccessAt: j['lastSendSuccessAt'] == null ? null : DateTime.fromMillisecondsSinceEpoch((j['lastSendSuccessAt'] as num).toInt()),
    lastError: j['lastError'] as String?,
  );
}
