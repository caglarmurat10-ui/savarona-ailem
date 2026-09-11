import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import '../core/config.dart';

class AppRelease {
  const AppRelease({
    required this.versionName,
    required this.versionCode,
    required this.downloadUrl,
    required this.sha256,
    required this.notes,
    required this.mandatory,
  });

  final String versionName;
  final int versionCode;
  final String downloadUrl;
  final String sha256;
  final String notes;
  final bool mandatory;

  factory AppRelease.fromJson(Map<String, dynamic> j) => AppRelease(
        versionName: (j['version_name'] as String?) ?? '',
        versionCode: (j['version_code'] as num?)?.toInt() ?? 0,
        downloadUrl: (j['download_url'] as String?) ?? '',
        sha256: ((j['sha256'] as String?) ?? '').toLowerCase(),
        notes: (j['notes'] as String?) ?? '',
        mandatory: j['mandatory'] == true,
      );
}

class AppUpdateService {
  AppUpdateService()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
        ));

  final Dio _dio;
  static const _channel = MethodChannel('savarona_ailem/updater');

  Future<AppRelease?> check() async {
    if (!Platform.isAndroid || AppConfig.updateManifestUrl.isEmpty) return null;
    final base = Uri.parse(AppConfig.updateManifestUrl);
    final uri = base.replace(queryParameters: {
      ...base.queryParameters,
      't': DateTime.now().millisecondsSinceEpoch.toString(),
    });
    final r = await _dio.getUri(uri);
    final raw = r.data;
    final data = raw is Map
        ? Map<String, dynamic>.from(raw)
        : throw const FormatException('invalid_update_manifest');
    if (data['available'] != true) return null;
    final release = AppRelease.fromJson(data);
    if (release.versionCode <= AppConfig.buildCode ||
        !release.downloadUrl.startsWith('https://') ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(release.sha256)) {
      return null;
    }
    return release;
  }

  Future<String> downloadAndInstall(AppRelease release) async {
    final value = await _channel.invokeMethod<String>('downloadAndInstall', {
      'url': release.downloadUrl,
      'sha256': release.sha256,
      'versionCode': release.versionCode,
    });
    return value ?? 'unknown';
  }
}
