import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'data/settings_controller.dart';
import 'data/stats_repository.dart';
import 'services/sound_service.dart';

/// Màn "sạch" của shell: nạp cài đặt + thành tích + âm thanh 1 lần (trước đây
/// nằm ở main() của app demo) rồi dựng [FlipmindApp] (MaterialApp riêng cho
/// theme/locale theo cài đặt — giống cấu trúc app gốc).
class MainAppScreen extends StatefulWidget {
  const MainAppScreen({super.key});

  @override
  State<MainAppScreen> createState() => _MainAppScreenState();
}

class _MainAppScreenState extends State<MainAppScreen> {
  static final SettingsController _settings = SettingsController();
  static final StatsRepository _stats = StatsRepository();
  static final SoundService _sound = SoundService();
  static Future<void>? _bootstrap;

  static Future<void> _syncSound() {
    final value = _settings.value;
    return _sound.applySettings(
      soundEnabled: value.soundEnabled,
      musicEnabled: value.musicEnabled,
      hapticsEnabled: value.hapticsEnabled,
      volume: value.volume,
    );
  }

  static Future<void> _runBootstrap() async {
    // Game lật thẻ chỉ hợp lý ở màn dọc.
    await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    await Future.wait<void>(<Future<void>>[_settings.load(), _stats.load()]);
    await _sound.init();
    await _syncSound();
    _settings.addListener(_syncSound);
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
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return FlipmindApp(settings: _settings, stats: _stats, sound: _sound);
      },
    );
  }
}
