import 'package:flutter/material.dart';

import 'src/main_app_meta.dart';
import 'src/main_app_screen.dart';

/// Entry CHẠY THỬ main app standalone (preview) — KHÔNG phải entry của app
/// thật. App thật vẫn chạy qua shell:
///
///   • `app/lib/main.dart`       — release (nộp store), dựng BootShell.
///   • `app/lib/main_patch.dart` — patch OTA (BootShell + game của app_package).
///
/// File này chỉ để xem/chỉnh UI màn "sạch" mà KHÔNG cần boot flow:
///
///   cd apps/_reference/main_app && flutter run
///
/// Title/tên app/theme lấy từ [mainAppMeta] — y hệt lúc chạy trong shell
/// (khi meta không đặt theme thì dùng mirror của theme mặc định shell).
void main() {
  runApp(
    MaterialApp(
      title: mainAppMeta.appName,
      theme: mainAppMeta.theme ?? _previewTheme,
      debugShowCheckedModeBanner: false,
      home: const MainAppScreen(),
    ),
  );
}

/// Mirror của `_defaultTheme` trong `BootShell` (app/lib/shell/boot_shell.dart)
/// — dùng khi `mainAppMeta.theme` = null để preview giống hệt lúc chạy trong
/// shell. Muốn đổi theme hẳn thì đặt `theme:` trong `mainAppMeta`.
final ThemeData _previewTheme = ThemeData(
  colorSchemeSeed: Colors.indigo,
  useMaterial3: true,
);
