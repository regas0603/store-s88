import 'package:flutter/material.dart';

ThemeData buildAppTheme() {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF4fc3f7),
      brightness: Brightness.dark,
    ),
    useMaterial3: true,
    scaffoldBackgroundColor: const Color(0xFF070714),
  );
}

/// Nhận diện app cho shell: title AppBar, tên app (MaterialApp.title /
/// task-switcher), theme của MaterialApp shell.
class MainAppMeta {
  const MainAppMeta({
    required this.appTitle,
    required this.appName,
    this.theme,
  });

  final String appTitle;
  final String appName;
  final ThemeData? theme;
}

final MainAppMeta mainAppMeta = MainAppMeta(
  appTitle: 'Cờ Caro',
  appName: 'Cờ Caro',
  theme: buildAppTheme(),
);
