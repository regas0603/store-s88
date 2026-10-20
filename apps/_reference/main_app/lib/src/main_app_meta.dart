import 'package:flutter/material.dart';

/// Thông tin "nhận diện" của main app — title, tên app, theme.
///
/// Đây là nơi DUY NHẤT sửa tên/title: entry points bên app truyền
/// `mainAppMeta.appName` / `mainAppMeta.theme` vào BootShell của shell,
/// còn AppBar của màn "sạch" tự lấy `mainAppMeta.appTitle`. Shell KHÔNG
/// hardcode bất cứ tên gì.
class MainAppMeta {
  const MainAppMeta({
    this.appTitle = 'Weather',
    this.appName = 'Weather',
    this.theme,
  });

  /// Title hiển thị trên AppBar của màn "sạch".
  final String appTitle;

  /// Tên app — truyền vào `MaterialApp.title` (hiện ở task-switcher/OS).
  final String appName;

  /// Theme của main app; null = dùng theme mặc định của shell
  /// (`_defaultTheme` bên repo app — seed indigo, Material 3).
  final ThemeData? theme;
}

/// ⬇️ ĐỔI NHẬN DIỆN APP Ở ĐÂY (app thật: sửa `apps/<bundleId>/main_app` — thư mục này là tham chiếu).
///
/// `final` (không phải const) vì `theme` có thể là `ThemeData(...)` —
/// ThemeData không có constructor const.
final MainAppMeta mainAppMeta = MainAppMeta(
  appTitle: 'Weather',
  appName: 'Weather',
  // theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
);
