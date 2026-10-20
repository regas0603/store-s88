import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/models/game_config.dart';
import 'settings.dart';

/// Nguồn sự thật duy nhất cho tuỳ chọn người dùng.
///
/// Dùng [ChangeNotifier] của chính Flutter thay vì một package state management.
/// Lý do: app này chỉ có hai store toàn cục (settings + stats) và state của ván
/// chơi thì cục bộ trong một màn hình. Thêm Riverpod/Bloc ở quy mô này là chi
/// phí học và boilerplate không đổi lại được gì.
///
/// Điểm đổi ý: khi có multiplayer online hoặc đồng bộ tài khoản, hãy chuyển
/// sang Riverpod — lúc đó việc tách provider theo scope mới thực sự có giá trị.
class SettingsController extends ChangeNotifier {
  static const _kSound = 'settings.sound';
  static const _kVolume = 'settings.volume';
  static const _kHaptics = 'settings.haptics';
  static const _kTheme = 'settings.theme';
  static const _kLanguage = 'settings.language';
  static const _kShowTimer = 'settings.showTimer';
  static const _kShowRangeHint = 'settings.showRangeHint';
  static const _kRange = 'settings.range';
  static const _kDifficulty = 'settings.difficulty';
  static const _kHandoff = 'settings.handoffSeconds';
  static const _kTutorialSeen = 'settings.tutorialSeen';

  /// Giới hạn đếm ngược chuyền máy: dưới 1 giây thì người kia chưa kịp cầm
  /// máy, trên 5 giây thì ngồi chờ.
  static const int minHandoff = 1;
  static const int maxHandoff = 5;

  SharedPreferences? _prefs;
  Settings _value = const Settings();

  Settings get value => _value;

  /// Nạp tuỳ chọn từ đĩa. Gọi một lần lúc khởi động.
  ///
  /// Hỏng dữ liệu (người dùng downgrade app, key rác) không được phép làm chết
  /// app: mọi lỗi đọc đều rơi về giá trị mặc định.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      _value = Settings(
        soundEnabled: prefs.getBool(_kSound) ?? true,
        volume: (prefs.getDouble(_kVolume) ?? 0.7).clamp(0.0, 1.0).toDouble(),
        hapticsEnabled: prefs.getBool(_kHaptics) ?? true,
        themeMode: _readEnum(ThemeMode.values, prefs.getString(_kTheme)) ??
            ThemeMode.system,
        language:
            _readEnum(LanguageSetting.values, prefs.getString(_kLanguage)) ??
                LanguageSetting.system,
        showTimer: prefs.getBool(_kShowTimer) ?? true,
        showRangeHint: prefs.getBool(_kShowRangeHint) ?? true,
        range: _readEnum(GuessRange.values, prefs.getString(_kRange)) ??
            GuessRange.small,
        difficulty:
            _readEnum(GuessDifficulty.values, prefs.getString(_kDifficulty)) ??
                GuessDifficulty.normal,
        handoffSeconds: (prefs.getInt(_kHandoff) ?? 3)
            .clamp(minHandoff, maxHandoff)
            .toInt(),
        tutorialSeen: prefs.getBool(_kTutorialSeen) ?? false,
      );
    } catch (_) {
      _value = const Settings();
    }
    notifyListeners();
  }

  static T? _readEnum<T extends Enum>(List<T> values, String? raw) {
    if (raw == null) return null;
    for (final value in values) {
      if (value.name == raw) return value;
    }
    return null;
  }

  Future<void> _update(Settings next) async {
    _value = next;
    notifyListeners();
    await _persist(next);
  }

  Future<void> _persist(Settings s) async {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      await prefs.setBool(_kSound, s.soundEnabled);
      await prefs.setDouble(_kVolume, s.volume);
      await prefs.setBool(_kHaptics, s.hapticsEnabled);
      await prefs.setString(_kTheme, s.themeMode.name);
      await prefs.setString(_kLanguage, s.language.name);
      await prefs.setBool(_kShowTimer, s.showTimer);
      await prefs.setBool(_kShowRangeHint, s.showRangeHint);
      await prefs.setString(_kRange, s.range.name);
      await prefs.setString(_kDifficulty, s.difficulty.name);
      await prefs.setInt(_kHandoff, s.handoffSeconds);
      await prefs.setBool(_kTutorialSeen, s.tutorialSeen);
    } catch (_) {
      // Ghi hỏng thì thôi — tuỳ chọn trong phiên vẫn đúng, không đáng để crash.
    }
  }

  Future<void> setSoundEnabled(bool v) =>
      _update(_value.copyWith(soundEnabled: v));

  Future<void> setVolume(double v) =>
      _update(_value.copyWith(volume: v.clamp(0.0, 1.0).toDouble()));

  Future<void> setHapticsEnabled(bool v) =>
      _update(_value.copyWith(hapticsEnabled: v));

  Future<void> setThemeMode(ThemeMode v) =>
      _update(_value.copyWith(themeMode: v));

  Future<void> setLanguage(LanguageSetting v) =>
      _update(_value.copyWith(language: v));

  Future<void> setShowTimer(bool v) => _update(_value.copyWith(showTimer: v));

  Future<void> setShowRangeHint(bool v) =>
      _update(_value.copyWith(showRangeHint: v));

  Future<void> setRange(GuessRange v) => _update(_value.copyWith(range: v));

  Future<void> setDifficulty(GuessDifficulty v) =>
      _update(_value.copyWith(difficulty: v));

  Future<void> setHandoffSeconds(int v) => _update(
        _value.copyWith(
          handoffSeconds: v.clamp(minHandoff, maxHandoff).toInt(),
        ),
      );

  Future<void> setTutorialSeen(bool v) =>
      _update(_value.copyWith(tutorialSeen: v));

  /// Đưa mọi tuỳ chọn về mặc định (không đụng tới thành tích).
  Future<void> resetToDefaults() => _update(const Settings());
}
