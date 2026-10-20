// Entry CHẠY THỬ standalone (`flutter run` trong thư mục này) — KHÔNG phải
// entry của app thật (entry thật là app/lib/main.dart của shell).
import 'package:flutter/material.dart';

import 'main_app_package.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      title: mainAppMeta.appName,
      debugShowCheckedModeBanner: false,
      theme: mainAppMeta.theme,
      home: const MainAppScreen(),
    ),
  );
}
