import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:main_app_package/src/core/app_scope.dart';
import 'package:main_app_package/src/core/theme.dart';
import 'package:main_app_package/src/data/settings_controller.dart';
import 'package:main_app_package/src/data/stats_repository.dart';
import 'package:main_app_package/src/game/models/game_config.dart';
import 'package:main_app_package/src/l10n/strings.dart';
import 'package:main_app_package/src/services/sound_service.dart';
import 'package:main_app_package/src/ui/screens/game_screen.dart';

const _s = AppStrings('en');

Future<void> _pumpGame(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    AppScope(
      settings: SettingsController(),
      stats: StatsRepository(),
      sound: SoundService(),
      child: MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('en'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const GameScreen(
          config: GameConfig(mode: GameMode.solo, countdownSeconds: 0),
        ),
      ),
    ),
  );
  // Qua đếm ngược, vào trạng thái đang chơi.
  await tester.pump(const Duration(seconds: 1));
}

/// Menu tạm dừng nhận diện bằng nút "Resume" — chỉ nó mới có nút này.
Finder get _pauseOverlay => find.text(_s.resume);
Finder get _quitDialog => find.text(_s.quitTitle);

void main() {
  testWidgets('Bấm X khi đang chơi: chỉ hiện hộp xác nhận, không lòi menu '
      'tạm dừng phía sau', (tester) async {
    await _pumpGame(tester);

    expect(_pauseOverlay, findsNothing);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(_quitDialog, findsOneWidget);
    expect(
      _pauseOverlay,
      findsNothing,
      reason: 'Menu tạm dừng (Resume/Restart/Quit) lộ ra sau hộp thoại '
          '→ hai lớp thoát game chồng nhau',
    );

    await tester.tap(find.text(_s.cancel));
    await tester.pumpAndSettle();
  });

  testWidgets('Huỷ hộp xác nhận thì ván chơi tiếp, không kẹt ở menu tạm dừng',
      (tester) async {
    await _pumpGame(tester);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_s.cancel));
    await tester.pumpAndSettle();

    expect(_quitDialog, findsNothing);
    expect(_pauseOverlay, findsNothing);
  });

  testWidgets('Thoát từ menu tạm dừng: menu vẫn ở đó làm nền cho hộp xác nhận',
      (tester) async {
    await _pumpGame(tester);

    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pumpAndSettle();
    expect(_pauseOverlay, findsOneWidget);

    await tester.tap(find.text(_s.quit));
    await tester.pumpAndSettle();

    expect(_quitDialog, findsOneWidget);
    expect(_pauseOverlay, findsOneWidget,
        reason: 'Mở từ menu tạm dừng thì menu là nền hợp lý, phải giữ');

    await tester.tap(find.text(_s.cancel));
    await tester.pumpAndSettle();
    expect(_pauseOverlay, findsOneWidget,
        reason: 'Huỷ thì quay về menu tạm dừng, không tự chơi tiếp');
  });

  testWidgets('Restart từ menu tạm dừng: đóng menu và chơi lại ngay, '
      'KHÔNG hỏi xác nhận', (tester) async {
    await _pumpGame(tester);

    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pumpAndSettle();
    expect(_pauseOverlay, findsOneWidget);

    await tester.tap(find.text(_s.restart));
    await tester.pump(const Duration(seconds: 1));

    // Menu đóng lại, ván mới chạy.
    expect(_pauseOverlay, findsNothing);
    // Không có hộp xác nhận nào — tiến độ mất ngay lập tức.
    expect(find.byType(AlertDialog), findsNothing);
  });
}
