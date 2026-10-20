import 'package:flutter/material.dart';

import 'core/theme.dart';

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
  appTitle: 'Flipmind',
  appName: 'Flipmind',
  theme: AppTheme.dark(),
);
