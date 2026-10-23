import 'package:flutter_test/flutter_test.dart';
import 'package:main_app_package/main_app_package.dart';

void main() {
  test('contract: mainAppMeta có title/tên app (không rỗng)', () {
    expect(mainAppMeta.appTitle, isNotEmpty);
    expect(mainAppMeta.appName, isNotEmpty);
    expect(mainAppMeta.theme, isNotNull);
  });

  test('contract: MainAppScreen dựng được không tham số', () {
    expect(const MainAppScreen(), isA<MainAppScreen>());
  });
}
