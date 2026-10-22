// Smoke test contract main_app_package: mainAppMeta có tên, MainAppScreen
// dựng được dạng const (shell dùng MainAppScreen.new).
import 'package:flutter_test/flutter_test.dart';
import 'package:main_app_package/main_app_package.dart';

void main() {
  test('contract: mainAppMeta có title/tên app', () {
    expect(mainAppMeta.appTitle, isNotEmpty);
    expect(mainAppMeta.appName, isNotEmpty);
  });

  test('contract: MainAppScreen là widget const không tham số', () {
    const MainAppScreen screen = MainAppScreen();
    expect(screen, isA<MainAppScreen>());
  });
}
