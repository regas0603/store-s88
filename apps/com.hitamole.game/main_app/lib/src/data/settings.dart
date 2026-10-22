import 'package:flutter/material.dart';

import '../game/models/card_icon.dart';
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

  // --- Mặc định khi vào ván mới ---
  final BoardSize boardSize;
  final AiDifficulty aiDifficulty;
  final BoardDifficulty boardDifficulty;

  /// Nhân vật trồi lên. null = chuột chũi cổ điển.
  final CardCategory? cardCategory;

  /// 0..3 giây đếm ngược trước khi bắt đầu.
  final int countdownSeconds;

  // --- Trạng thái onboarding ---
  final bool tutorialSeen;

  const Settings({
    this.soundEnabled = true,
    this.volume = 0.7,
    this.hapticsEnabled = true,
    this.themeMode = ThemeMode.system,
    this.language = LanguageSetting.system,
    this.showTimer = true,
    this.boardSize = BoardSize.medium,
    this.aiDifficulty = AiDifficulty.normal,
    this.boardDifficulty = BoardDifficulty.normal,
    this.cardCategory,
    this.countdownSeconds = 2,
    this.tutorialSeen = false,
  });

  Settings copyWith({
    bool? soundEnabled,
    double? volume,
    bool? hapticsEnabled,
    ThemeMode? themeMode,
    LanguageSetting? language,
    bool? showTimer,
    BoardSize? boardSize,
    AiDifficulty? aiDifficulty,
    BoardDifficulty? boardDifficulty,
    CardCategory? cardCategory,
    bool clearCardCategory = false,
    int? countdownSeconds,
    bool? tutorialSeen,
  }) {
    return Settings(
      soundEnabled: soundEnabled ?? this.soundEnabled,
      volume: volume ?? this.volume,
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      themeMode: themeMode ?? this.themeMode,
      language: language ?? this.language,
      showTimer: showTimer ?? this.showTimer,
      boardSize: boardSize ?? this.boardSize,
      aiDifficulty: aiDifficulty ?? this.aiDifficulty,
      boardDifficulty: boardDifficulty ?? this.boardDifficulty,
      cardCategory:
          clearCardCategory ? null : (cardCategory ?? this.cardCategory),
      countdownSeconds: countdownSeconds ?? this.countdownSeconds,
      tutorialSeen: tutorialSeen ?? this.tutorialSeen,
    );
  }

  /// Cấu hình ván mới dựng từ tuỳ chọn hiện tại.
  GameConfig configFor(GameMode mode) => GameConfig(
        mode: mode,
        boardSize: boardSize,
        aiDifficulty: aiDifficulty,
        boardDifficulty: boardDifficulty,
        category: cardCategory,
        countdownSeconds: countdownSeconds,
      );
}
