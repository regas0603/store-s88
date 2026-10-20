// Smoke test cho main_app_package — kiểm CONTRACT mà shell/app dựa vào:
//   • MainAppScreen: widget `const`, dựng được, AppBar hiện `mainAppMeta.appTitle`.
//   • mainAppMeta: appTitle/appName không rỗng.
//
// (File gốc là template `flutter create` trỏ class `MyApp` không tồn tại →
// bản xuất của tools/cmd/build_main_app.sh fail ở `flutter analyze`.)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:main_app_package/main_app_package.dart';

void main() {
  testWidgets('MainAppScreen dựng được và hiện appTitle',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        title: mainAppMeta.appName,
        theme: mainAppMeta.theme,
        home: const MainAppScreen(),
      ),
    );

    expect(find.byType(MainAppScreen), findsOneWidget);
    expect(find.text(mainAppMeta.appTitle), findsWidgets);
  });

  test('mainAppMeta có appTitle + appName', () {
    expect(mainAppMeta.appTitle, isNotEmpty);
    expect(mainAppMeta.appName, isNotEmpty);
  });
}
