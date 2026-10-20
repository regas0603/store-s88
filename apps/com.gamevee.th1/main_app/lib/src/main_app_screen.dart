import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/app_settings.dart';
import 'core/audio_service.dart';
import 'core/text_app_style.dart';
import 'screens/splash_screen.dart';

/// Màn "sạch" của shell: khởi tạo cài đặt + âm thanh 1 lần (trước đây nằm ở
/// main() của app demo) rồi vào game. Dùng Navigator của MaterialApp shell.
class MainAppScreen extends StatefulWidget {
  const MainAppScreen({super.key});

  @override
  State<MainAppScreen> createState() => _MainAppScreenState();
}

class _MainAppScreenState extends State<MainAppScreen> {
  static Future<void>? _bootstrap;

  static Future<void> _runBootstrap() async {
    await AppSettings().load();
    await AudioService().init();
    TextAppStyle.precacheMultilingualFonts();
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _bootstrap ??= _runBootstrap();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _bootstrap,
      builder: (BuildContext context, AsyncSnapshot<void> snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: Color(0xFF070714),
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return const SplashScreen();
      },
    );
  }
}
