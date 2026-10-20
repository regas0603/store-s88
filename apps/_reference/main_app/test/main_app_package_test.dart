import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:main_app_package/main_app_package.dart';

void main() {
  test('contract: mainAppMeta có title/tên app (không rỗng)', () {
    expect(mainAppMeta.appTitle, isNotEmpty);
    expect(mainAppMeta.appName, isNotEmpty);
  });

  testWidgets('MainAppScreen render AppBar với title từ mainAppMeta', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(MaterialApp(home: MainAppScreen()));

    // AppBar lấy title TỪ meta (không hardcode) — variant đổi meta là đổi UI.
    expect(find.text(mainAppMeta.appTitle), findsOneWidget);
    expect(find.text('Hà Nội'), findsOneWidget);
    expect(find.text('28°'), findsOneWidget);
  });
}
