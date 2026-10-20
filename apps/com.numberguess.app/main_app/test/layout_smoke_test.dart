import 'package:main_app_package/src/core/app_scope.dart';
import 'package:main_app_package/src/core/theme.dart';
import 'package:main_app_package/src/data/settings_controller.dart';
import 'package:main_app_package/src/data/stats_repository.dart';
import 'package:main_app_package/src/l10n/strings.dart';
import 'package:main_app_package/src/services/sound_service.dart';
import 'package:main_app_package/src/ui/screens/menu_screen.dart';
import 'package:main_app_package/src/ui/screens/tutorial_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dựng màn hình trên một kích thước máy cụ thể. Tràn layout (RenderFlex
/// overflow) sẽ làm test fail ngay.
Future<void> _pumpAt(
  WidgetTester tester,
  Widget screen, {
  required Size size,
  required Locale locale,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    AppScope(
      settings: SettingsController(),
      stats: StatsRepository(),
      sound: SoundService(),
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: locale,
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: screen,
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  const sizes = <Size>[Size(320, 568), Size(390, 844)];
  const locales = <Locale>[Locale('vi'), Locale('en')];

  for (final size in sizes) {
    for (final locale in locales) {
      final tag = '${size.width.toInt()}x${size.height.toInt()} $locale';

      testWidgets('Trang chủ không tràn layout ($tag)', (tester) async {
        await _pumpAt(tester, const MenuScreen(), size: size, locale: locale);
        expect(find.byType(MenuScreen), findsOneWidget);
        // Gỡ cây để Timer của khối số quay được huỷ.
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('Hướng dẫn đi hết được 4 bước, không tràn ($tag)',
          (tester) async {
        await _pumpAt(tester, const TutorialScreen(),
            size: size, locale: locale);
        final s = AppStrings(locale.languageCode);
        for (var i = 0; i < 3; i++) {
          await tester.tap(find.text(s.next));
          await tester.pumpAndSettle();
        }
        expect(find.text(s.tutorial4Title), findsOneWidget);
        expect(find.text(s.startPlaying), findsOneWidget);
      });
    }
  }
}
