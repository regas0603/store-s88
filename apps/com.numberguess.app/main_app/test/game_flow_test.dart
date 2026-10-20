import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:main_app_package/src/core/app_scope.dart';
import 'package:main_app_package/src/core/theme.dart';
import 'package:main_app_package/src/data/settings_controller.dart';
import 'package:main_app_package/src/data/stats_repository.dart';
import 'package:main_app_package/src/l10n/strings.dart';
import 'package:main_app_package/src/game/models/game_config.dart';
import 'package:main_app_package/src/services/sound_service.dart';
import 'package:main_app_package/src/ui/screens/game_screen.dart';

const AppStrings s = AppStrings('vi');

Future<void> pumpGame(WidgetTester tester, GameConfig config) async {
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    AppScope(
      settings: SettingsController(),
      stats: StatsRepository(),
      sound: SoundService(),
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('vi'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: GameScreen(config: config),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// Gõ [value] lên bàn phím số rồi bấm phím [action].
///
/// Dùng `.last` chứ không `.first`: màn nhập số bí mật là lớp phủ nằm TRÊN màn
/// đoán trong cùng một Stack, nên cả hai bàn phím cùng tồn tại trong cây. Phím
/// bấm được là phím của lớp trên cùng.
Future<void> enterNumber(
  WidgetTester tester,
  String value, {
  required String action,
}) async {
  for (final digit in value.split('')) {
    await tester.tap(find.widgetWithText(InkWell, digit).last);
    await tester.pump();
  }
  await tester.tap(find.widgetWithText(InkWell, action).last);
  await tester.pump();
}

void main() {
  testWidgets('chơi đơn: đoán sai nhận gợi ý, khoảng còn lại thu hẹp',
      (tester) async {
    await pumpGame(
      tester,
      const GameConfig(mode: GameMode.solo, range: GuessRange.small),
    );

    await enterNumber(tester, '50', action: s.submitGuess);

    // Một trong hai gợi ý phải hiện ra — không biết máy bốc số nào.
    final gotHint = find.text(s.hintHigher).evaluate().isNotEmpty ||
        find.text(s.hintLower).evaluate().isNotEmpty ||
        find.text(s.hintCorrect).evaluate().isNotEmpty;
    expect(gotHint, isTrue);

    // Lần đoán vừa rồi được ghi vào lịch sử.
    expect(find.text('50'), findsWidgets);
  });

  testWidgets('chơi đơn: số ngoài khoảng bị từ chối, không tốn lượt',
      (tester) async {
    await pumpGame(
      tester,
      const GameConfig(mode: GameMode.solo, range: GuessRange.tiny),
    );

    // Khoảng 1–50 nên 99 là ngoài khoảng.
    await enterNumber(tester, '99', action: s.submitGuess);

    expect(find.text(s.outOfRangeWarning), findsOneWidget);
    // Bộ đếm lượt còn lại không đổi.
    expect(
      find.text('${GuessRange.tiny.normalGuesses}/'
          '${GuessRange.tiny.normalGuesses}'),
      findsOneWidget,
    );
  });

  testWidgets('2 người: Người 1 chọn số, chuyền máy, Người 2 đoán',
      (tester) async {
    await pumpGame(
      tester,
      const GameConfig(
        mode: GameMode.duel,
        range: GuessRange.small,
        handoffSeconds: 1,
      ),
    );

    // Bước 1: Người 1 đặt số bí mật.
    expect(find.text(s.setSecretTitle(s.player1)), findsOneWidget);
    await enterNumber(tester, '42', action: s.confirm);

    // Bước 2: màn chuyền máy cho Người 2.
    expect(find.text(s.handoffTitle(s.player2)), findsOneWidget);
    await tester.tap(find.text(s.handoffSkip));
    await tester.pump();

    // Bước 3: Người 2 đoán — số 42 đã bị khoá nên gợi ý phải chính xác.
    expect(find.text(s.turnOf(s.player2)), findsOneWidget);
    await enterNumber(tester, '10', action: s.submitGuess);
    expect(find.text(s.hintHigher), findsOneWidget);

    await enterNumber(tester, '80', action: s.submitGuess);
    expect(find.text(s.hintLower), findsOneWidget);
    expect(find.text(s.rangeStillPossible(11, 79)), findsOneWidget);

    // Bước 4: đoán trúng → đổi vai, Người 2 đặt số cho Người 1.
    await enterNumber(tester, '42', action: s.submitGuess);
    await tester.pump();
    expect(find.text(s.setSecretTitle(s.player2)), findsOneWidget);
  });
}
