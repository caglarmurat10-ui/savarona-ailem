// App Store ekran goruntulerini GERCEK uygulamayi surerek uretir.
//
// Apple, Guideline 2.3.3 kapsaminda ekran goruntulerinin uygulamanin gercek
// kullanimini gostermesini istiyor; onceki gorseller yalniz karsilama ekraniydi.
// Bu test uygulamayi veri dolu bir demo aileye baglayip canli harita, uye
// detayi ve rota gecmisi ekranlarini yakalar.
//
// Calistirma (CI):
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/app_store_screens_test.dart -d <simulator-id> \
//     --dart-define=API_BASE_URL=... --dart-define=DEMO_INVITE_CODE=...
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:savarona_ailem/app.dart';

const inviteCode = String.fromEnvironment('DEMO_INVITE_CODE');

Future<void> settle(WidgetTester tester, {int seconds = 3}) async {
  final deadline = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<bool> tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  if (finder.evaluate().isEmpty) return false;
  await tester.tap(finder.first);
  await settle(tester, seconds: 2);
  return true;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App Store ekran goruntuleri', (tester) async {
    await binding.convertFlutterSurfaceToImage();

    await tester.pumpWidget(SavaronaAilemApp());
    await settle(tester, seconds: 4);

    // 1) Davet koduyla katil -> veri dolu demo aile
    if (inviteCode.isNotEmpty) {
      if (await tapText(tester, 'Davet koduyla aileye katıl')) {
        await settle(tester, seconds: 2);
        final fields = find.byType(TextFormField);
        if (fields.evaluate().length >= 3) {
          await tester.enterText(fields.at(0), inviteCode);
          await tester.enterText(fields.at(1), 'Demo Kullanıcı');
          await tester.enterText(fields.at(2), 'Demo iPhone');
          await settle(tester, seconds: 1);
          await tapText(tester, 'Katıl');
          // Sunucu cevabi + ana ekran yuklemesi
          await settle(tester, seconds: 10);
        }
      }
    }

    // 2) Canli aile haritasi - harita karolari icin ekstra bekleme
    await settle(tester, seconds: 8);
    await binding.takeScreenshot('01-canli-harita');

    // 3) Uye detayi: alt listedeki ilk uye kartina dokun
    final memberCards = find.byType(InkWell);
    if (memberCards.evaluate().isNotEmpty) {
      await tester.tap(memberCards.first, warnIfMissed: false);
      await settle(tester, seconds: 8);
      await binding.takeScreenshot('02-uye-detayi');

      // 4) Rota gecmisi
      if (await tapText(tester, 'Rota geçmişi')) {
        await settle(tester, seconds: 8);
        await binding.takeScreenshot('03-rota-gecmisi');
        // Geri don
        final back = find.byTooltip('Back');
        if (back.evaluate().isNotEmpty) {
          await tester.tap(back.first);
          await settle(tester, seconds: 3);
        }
      }
      final back2 = find.byTooltip('Back');
      if (back2.evaluate().isNotEmpty) {
        await tester.tap(back2.first);
        await settle(tester, seconds: 4);
      }
    }

    // 5) Ana ekran + SOS: alt sayfayi yukari suruklemeden once bekle
    await settle(tester, seconds: 4);
    await binding.takeScreenshot('04-ana-ekran-sos');
  }, timeout: const Timeout(Duration(minutes: 8)));
}
