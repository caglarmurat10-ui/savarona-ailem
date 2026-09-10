class AppConfig {
  static const appName = 'Savarona Ailem';
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://REPLACE_ME.workers.dev',
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
