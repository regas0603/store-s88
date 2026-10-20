import 'package:flutter/material.dart';

import '../game/models/game_config.dart';

/// Ngôn ngữ hiển thị. [system] = bám theo locale của thiết bị.
enum LanguageSetting { system, vi, en }

extension LanguageSettingX on LanguageSetting {
  /// Locale ép buộc, hoặc null để Flutter tự phân giải theo thiết bị.
  Locale? get locale {
    switch (this) {
      case LanguageSetting.system:
        return null;
      case LanguageSetting.vi:
        return const Locale('vi');
      case LanguageSetting.en:
        return const Locale('en');
    }
  }
}

/// Toàn bộ tuỳ chọn người dùng. Bất biến — [SettingsController] tạo bản sao mới
/// mỗi lần đổi, nhờ vậy không có state nào bị sửa lén ở nơi khác.
@immutable
class Settings {
  // --- Âm thanh & phản hồi ---
  final bool soundEnabled;
  final double volume;
  final bool hapticsEnabled;

  // --- Hiển thị ---
  final ThemeMode themeMode;
  final LanguageSetting language;
  final bool showTimer;

  /// Hiện khoảng còn lại ("số nằm trong 42…67") sau mỗi gợi ý.
  ///
  /// Tắt đi là chế độ "tự nhẩm" cho người chơi muốn khó hơn mà không phải
  /// giảm số lượt.
  final bool showRangeHint;

  // --- Mặc định khi vào ván mới ---
  final GuessRange range;
  final GuessDifficulty difficulty;

  /// 1..5 giây đếm ngược khi chuyền máy ở chế độ 2 người.
  final int handoffSeconds;

  // --- Trạng thái onboarding ---
  final bool tutorialSeen;

  const Settings({
    this.soundEnabled = true,
    this.volume = 0.7,
    this.hapticsEnabled = true,
    this.themeMode = ThemeMode.system,
    this.language = LanguageSetting.system,
    this.showTimer = true,
    this.showRangeHint = true,
    this.range = GuessRange.small,
    this.difficulty = GuessDifficulty.normal,
    this.handoffSeconds = 3,
    this.tutorialSeen = false,
  });

  Settings copyWith({
    bool? soundEnabled,
    double? volume,
    bool? hapticsEnabled,
    ThemeMode? themeMode,
    LanguageSetting? language,
    bool? showTimer,
    bool? showRangeHint,
    GuessRange? range,
    GuessDifficulty? difficulty,
    int? handoffSeconds,
    bool? tutorialSeen,
  }) {
    return Settings(
      soundEnabled: soundEnabled ?? this.soundEnabled,
      volume: volume ?? this.volume,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      themeMode: themeMode ?? this.themeMode,
      language: language ?? this.language,
      showTimer: showTimer ?? this.showTimer,
      showRangeHint: showRangeHint ?? this.showRangeHint,
      range: range ?? this.range,
      difficulty: difficulty ?? this.difficulty,
      handoffSeconds: handoffSeconds ?? this.handoffSeconds,
      tutorialSeen: tutorialSeen ?? this.tutorialSeen,
    );
  }

  /// Cấu hình ván mới dựng từ tuỳ chọn hiện tại.
  GameConfig configFor(GameMode mode) => GameConfig(
        mode: mode,
        range: range,
        difficulty: difficulty,
        handoffSeconds: handoffSeconds,
      );
}
