import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStore {
  static const _key = 'device_token';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<String?> read() => _storage.read(key: _key);
  Future<void> write(String token) => _storage.write(key: _key, value: token);
  Future<void> clear() => _storage.delete(key: _key);
}
