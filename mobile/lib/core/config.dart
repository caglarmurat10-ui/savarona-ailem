class AppConfig {
  static const appName = 'Savarona Ailem';
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://REPLACE_ME.workers.dev',
  );
  static const buildCode = int.fromEnvironment('APP_BUILD_CODE', defaultValue: 3);
  static const versionName = String.fromEnvironment('APP_VERSION_NAME', defaultValue: '0.3.0');

  static Uri wsUri(String ticket) {
    final base = Uri.parse(apiBaseUrl);
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '/v1/live',
      queryParameters: {'ticket': ticket},
    );
  }
}
