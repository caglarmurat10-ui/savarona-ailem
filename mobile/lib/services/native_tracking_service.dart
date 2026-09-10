import 'package:flutter/services.dart';
import '../models/permission_health.dart';

class NativeTrackingService {
  static const _channel = MethodChannel('savarona_ailem/tracking');

  Future<PermissionHealth> status() async {
    final raw = Map<String, dynamic>.from(await _channel.invokeMethod('status') as Map? ?? const {});
    return PermissionHealth.fromMap(raw);
  }

  Future<bool> requestPermissions() async =>
      (await _channel.invokeMethod<bool>('requestPermissions')) ?? false;

  Future<void> openAppSettings() => _channel.invokeMethod('openAppSettings');

  Future<void> start({required String apiBaseUrl, required String deviceToken}) =>
      _channel.invokeMethod('start', {'apiBaseUrl': apiBaseUrl, 'deviceToken': deviceToken});

  Future<void> stop() => _channel.invokeMethod('stop');
}
