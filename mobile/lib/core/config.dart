class AppConfig {
  static const appName = 'Savarona Ailem';
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://REPLACE_ME.workers.dev',
  );
  static const buildCode = int.fromEnvironment('APP_BUILD_CODE', defaultValue: 4);
  static const versionName = String.fromEnvironment('APP_VERSION_NAME', defaultValue: '0.3.1');
  static const updateManifestUrl = String.fromEnvironment(
    'UPDATE_MANIFEST_URL',
    defaultValue: 'https://raw.githubusercontent.com/caglarmurat10-ui/savarona-ailem/main/updates/android-latest.json',
  );

  static Uri wsUri(String ticket) {
    final base = Uri.parse(apiBaseUrl);
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '/v1/live',
      queryParameters: {'ticket': ticket},
    );
  }
}
