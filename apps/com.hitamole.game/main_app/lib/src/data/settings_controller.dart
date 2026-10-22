import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/models/card_icon.dart';
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
  static const _kBoardSize = 'settings.boardSize';
  static const _kAiDifficulty = 'settings.aiDifficulty';
  // Tên key từ hồi độ khó chỉ áp dụng cho chơi đơn — giữ để không mất tuỳ chọn.
  static const _kBoardDifficulty = 'settings.soloDifficulty';
  static const _kCategory = 'settings.cardCategory';
  // Giữ tên key cũ để người dùng nâng cấp không mất tuỳ chọn.
  static const _kCountdown = 'settings.peekSeconds';
  static const _kTutorialSeen = 'settings.tutorialSeen';

  static const String _allCategories = '__all__';

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
        boardSize: _readEnum(BoardSize.values, prefs.getString(_kBoardSize)) ??
            BoardSize.medium,
        aiDifficulty:
            _readEnum(AiDifficulty.values, prefs.getString(_kAiDifficulty)) ??
                AiDifficulty.normal,
        boardDifficulty: _readEnum(
              BoardDifficulty.values,
              prefs.getString(_kBoardDifficulty),
            ) ??
            BoardDifficulty.normal,
        cardCategory: _readCategory(prefs.getString(_kCategory)),
        countdownSeconds: (prefs.getInt(_kCountdown) ?? 2).clamp(0, 3).toInt(),
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

  static CardCategory? _readCategory(String? raw) {
    if (raw == null || raw == _allCategories) return null;
    return _readEnum(CardCategory.values, raw);
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
      await prefs.setString(_kBoardSize, s.boardSize.name);
      await prefs.setString(_kAiDifficulty, s.aiDifficulty.name);
      await prefs.setString(_kBoardDifficulty, s.boardDifficulty.name);
      await prefs.setString(_kCategory, s.cardCategory?.name ?? _allCategories);
      await prefs.setInt(_kCountdown, s.countdownSeconds);
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

  Future<void> setBoardSize(BoardSize v) =>
      _update(_value.copyWith(boardSize: v));

  Future<void> setAiDifficulty(AiDifficulty v) =>
      _update(_value.copyWith(aiDifficulty: v));

  Future<void> setBoardDifficulty(BoardDifficulty v) =>
      _update(_value.copyWith(boardDifficulty: v));

  Future<void> setCardCategory(CardCategory? v) => _update(
        _value.copyWith(cardCategory: v, clearCardCategory: v == null),
      );

  Future<void> setCountdownSeconds(int v) =>
      _update(_value.copyWith(countdownSeconds: v.clamp(0, 3).toInt()));

  Future<void> setTutorialSeen(bool v) =>
      _update(_value.copyWith(tutorialSeen: v));

  /// Đưa mọi tuỳ chọn về mặc định (không đụng tới thành tích).
  Future<void> resetToDefaults() => _update(const Settings());
}
