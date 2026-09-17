import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// App Store ekran goruntulerini diske yazan surucu.
/// `flutter drive` ile calistirilir; testteki her `takeScreenshot(name)` cagrisi
/// screenshots/<name>.png olarak kaydedilir.
Future<void> main() async {
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      final directory = Directory('screenshots');
      if (!directory.existsSync()) directory.createSync(recursive: true);
      final file = File('${directory.path}/$name.png');
      file.writeAsBytesSync(bytes);
      stdout.writeln('SCREENSHOT_SAVED=${file.path} (${bytes.length} bayt)');
      return true;
    },
  );
}
