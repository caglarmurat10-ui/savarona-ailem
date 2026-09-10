import 'package:dio/dio.dart';
import '../core/config.dart';
import '../models/member_location.dart';
import '../models/route_point.dart';
import 'token_store.dart';

class ApiException implements Exception {
  ApiException(this.code, this.status);
  final String code;
  final int status;

  @override
  String toString() => 'ApiException($status, $code)';
}

class ApiClient {
  ApiClient(this._tokens) : _dio = Dio(BaseOptions(
    baseUrl: AppConfig.apiBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
  ));

  final Dio _dio;
  final TokenStore _tokens;

  Future<Options> _auth() async {
    final token = await _tokens.read();
    if (token == null) throw StateError('Cihaz tokenı yok');
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      final code = (e.response?.data is Map) ? (e.response!.data['error'] as String? ?? 'unknown') : 'network_error';
      throw ApiException(code, status);
    }
  }

  Future<bool> hasToken() async => (await _tokens.read()) != null;
  Future<String?> deviceToken() => _tokens.read();

  Future<Map<String, dynamic>> bootstrap({
    required String bootstrapSecret,
    required String familyName,
    required String ownerName,
    required String deviceName,
    required String platform,
  }) => _guard(() async {
    final r = await _dio.post('/v1/admin/bootstrap',
      options: Options(headers: {'x-bootstrap-secret': bootstrapSecret}),
      data: {
        'family_name': familyName,
        'owner_name': ownerName,
        'device_name': deviceName,
        'platform': platform,
      },
    );
    final data = Map<String, dynamic>.from(r.data as Map);
    await _tokens.write(data['device_token'] as String);
    return data;
  });

  Future<Map<String, dynamic>> join({
    required String inviteCode,
    required String memberName,
    required String deviceName,
    required String platform,
  }) => _guard(() async {
    final r = await _dio.post('/v1/join', data: {
      'invite_code': inviteCode,
      'member_name': memberName,
      'device_name': deviceName,
      'platform': platform,
    });
    final data = Map<String, dynamic>.from(r.data as Map);
    await _tokens.write(data['device_token'] as String);
    return data;
  });

  Future<String> createInvite() => _guard(() async {
    final r = await _dio.post('/v1/invites', options: await _auth());
    return r.data['invite_code'] as String;
  });

  Future<List<MemberLocation>> snapshot() => _guard(() async {
    final r = await _dio.get('/v1/family/snapshot', options: await _auth());
    final list = (r.data['members'] as List? ?? const []);
    return list.map((e) => MemberLocation.fromSnapshot(Map<String,dynamic>.from(e as Map))).toList();
  });

  Future<List<RoutePoint>> history({
    required String memberId,
    DateTime? from,
    DateTime? to,
    int limit = 2000,
  }) => _guard(() async {
    final r = await _dio.get('/v1/history', options: await _auth(), queryParameters: {
      'member_id': memberId,
      if (from != null) 'from': from.millisecondsSinceEpoch,
      if (to != null) 'to': to.millisecondsSinceEpoch,
      'limit': limit,
    });
    final list = (r.data['points'] as List? ?? const []);
    return list.map((e) => RoutePoint.fromJson(Map<String,dynamic>.from(e as Map))).toList();
  });

  Future<String> createLiveTicket() => _guard(() async {
    final r = await _dio.post('/v1/live-ticket', options: await _auth());
    return r.data['ticket'] as String;
  });

  Future<void> sendSos() => _guard(() async {
    await _dio.post('/v1/sos', data: const {}, options: await _auth());
  });

  Future<void> registerPushToken({required String platform, required String token}) => _guard(() async {
    await _dio.post('/v1/push-token', options: await _auth(), data: {'platform': platform, 'token': token});
  });

  Future<List<Map<String, dynamic>>> listGeofences() => _guard(() async {
    final r = await _dio.get('/v1/geofences', options: await _auth());
    return (r.data['geofences'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  });

  Future<String> createGeofence({required String name, required double lat, required double lng, required double radiusM}) => _guard(() async {
    final r = await _dio.post('/v1/geofences', options: await _auth(), data: {
      'name': name, 'lat': lat, 'lng': lng, 'radius_m': radiusM,
    });
    return r.data['geofence_id'] as String;
  });

  Future<void> updateGeofence(String id, {String? name, double? lat, double? lng, double? radiusM, bool? enabled}) => _guard(() async {
    await _dio.patch('/v1/geofences/$id', options: await _auth(), data: {
      if (name != null) 'name': name,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (radiusM != null) 'radius_m': radiusM,
      if (enabled != null) 'enabled': enabled,
    });
  });

  Future<void> deleteGeofence(String id) => _guard(() async {
    await _dio.delete('/v1/geofences/$id', options: await _auth());
  });
}
