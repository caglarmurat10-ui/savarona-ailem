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
          baseUrl: AppConfig.apiBaseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
        ));

  final Dio _dio;
  static const _channel = MethodChannel('savarona_ailem/updater');

  Future<AppRelease?> check() async {
    if (!Platform.isAndroid) return null;
    final r = await _dio.get('/v1/app-update/android');
    final data = Map<String, dynamic>.from(r.data as Map);
    if (data['available'] != true) return null;
    final release = AppRelease.fromJson(data);
    if (release.versionCode <= AppConfig.buildCode ||
        release.downloadUrl.isEmpty ||
        release.sha256.length != 64) {
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
