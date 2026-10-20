import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Skin cho quân cờ ────────────────────────────────────────────────────────

enum PieceSkin {
  neon(
    xColor: Color(0xFF4fc3f7),
    oColor: Color(0xFFf48fb1),
  ),
  fire(
    xColor: Color(0xFFFF6B35),
    oColor: Color(0xFFFFD23F),
  ),
  forest(
    xColor: Color(0xFF56CFE1),
    oColor: Color(0xFF80FFDB),
  ),
  royal(
    xColor: Color(0xFFB388FF),
    oColor: Color(0xFFFFD700),
  ),
  mono(
    xColor: Color(0xFFFFFFFF),
    oColor: Color(0xFF888888),
  );

  final Color xColor;
  final Color oColor;

  const PieceSkin({
    required this.xColor,
    required this.oColor,
  });
}

// ─── Nền bàn cờ (gradient trong vùng lưới) ────────────────────────────────────

enum BoardBackground {
  midnight(
    colorA: Color(0xFF1a1a3e),
    colorB: Color(0xFF0d0d22),
  ),
  ocean(
    colorA: Color(0xFF0d47a1),
    colorB: Color(0xFF01579b),
  ),
  deepForest(
    colorA: Color(0xFF1b5e20),
    colorB: Color(0xFF0d2818),
  ),
  sunset(
    colorA: Color(0xFF6a1b9a),
    colorB: Color(0xFF4a148c),
  ),
  wood(
    colorA: Color(0xFF5d4037),
    colorB: Color(0xFF3e2723),
  ),
  charcoal(
    colorA: Color(0xFF424242),
    colorB: Color(0xFF212121),
  );

  final Color colorA;
  final Color colorB;

  const BoardBackground({
    required this.colorA,
    required this.colorB,
  });
}

// ─── Board size and win line length ───────────────────────────────────────────

enum BoardSizePreset {
  n3(side: 3, winLength: 3),
  n4(side: 4, winLength: 4),
  n6(side: 6, winLength: 4),
  n9(side: 9, winLength: 5),
  n13(side: 13, winLength: 5),
  n15(side: 15, winLength: 5);

  final int side;
  final int winLength;

  const BoardSizePreset({required this.side, required this.winLength});
}

// ─── Ngôn ngữ ─────────────────────────────────────────────────────────────────

enum AppLanguage {
  vietnamese(code: 'vi', label: 'Tiếng Việt', flag: '🇻🇳'),
  english(code: 'en', label: 'English', flag: '🇬🇧'),
  japanese(code: 'ja', label: '日本語', flag: '🇯🇵'),
  chinese(code: 'zh', label: '中文', flag: '🇨🇳');

  final String code;
  final String label;
  final String flag;

  const AppLanguage({required this.code, required this.label, required this.flag});
}

// ─── Độ khó AI (chỉ khi VS AI) ───────────────────────────────────────────────

enum AiDifficulty {
  low,
  medium,
  high,
}

// ─── AppSettings ──────────────────────────────────────────────────────────────

class AppSettings extends ChangeNotifier {
  static final AppSettings _instance = AppSettings._();
  factory AppSettings() => _instance;
  AppSettings._();

  // Defaults
  int _turnTimeSecs = 30; // 0 = không giới hạn
  PieceSkin _skin = PieceSkin.neon;
  AppLanguage _language = AppLanguage.vietnamese;
  bool _soundEnabled = true;
  AiDifficulty _aiDifficulty = AiDifficulty.medium;
  BoardBackground _boardBackground = BoardBackground.midnight;
  BoardSizePreset _boardSizePreset = BoardSizePreset.n15;
  bool _hasSeenOnboarding = false;

  int get turnTimeSecs => _turnTimeSecs;
  PieceSkin get skin => _skin;
  AppLanguage get language => _language;
  bool get soundEnabled => _soundEnabled;
  AiDifficulty get aiDifficulty => _aiDifficulty;
  BoardBackground get boardBackground => _boardBackground;
  BoardSizePreset get boardSizePreset => _boardSizePreset;
  bool get hasSeenOnboarding => _hasSeenOnboarding;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _turnTimeSecs = prefs.getInt('turnTime') ?? 30;
    _skin = PieceSkin.values[prefs.getInt('skin') ?? 0];
    _language = AppLanguage.values[prefs.getInt('language') ?? 0];
    _soundEnabled = prefs.getBool('sound') ?? true;
    final int aiIdx = prefs.getInt('aiDifficulty') ?? 1;
    _aiDifficulty = AiDifficulty.values[aiIdx.clamp(0, AiDifficulty.values.length - 1)];
    final int bgIdx = prefs.getInt('boardBackground') ?? 0;
    _boardBackground =
        BoardBackground.values[bgIdx.clamp(0, BoardBackground.values.length - 1)];
    // Keep default as 15x15 even if enum order changes.
    final int bsIdx = prefs.getInt('boardSizePreset') ?? BoardSizePreset.n15.index;
    _boardSizePreset =
        BoardSizePreset.values[bsIdx.clamp(0, BoardSizePreset.values.length - 1)];
    _hasSeenOnboarding = prefs.getBool('hasSeenOnboarding') ?? false;
    notifyListeners();
  }

  Future<void> setHasSeenOnboarding(bool value) async {
    _hasSeenOnboarding = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenOnboarding', value);
    notifyListeners();
  }

  Future<void> setTurnTime(int secs) async {
    _turnTimeSecs = secs;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('turnTime', secs);
    notifyListeners();
  }

  Future<void> setSkin(PieceSkin skin) async {
    _skin = skin;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('skin', skin.index);
    notifyListeners();
  }

  Future<void> setLanguage(AppLanguage lang) async {
    _language = lang;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('language', lang.index);
    notifyListeners();
  }

  Future<void> setSoundEnabled(bool val) async {
    _soundEnabled = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sound', val);
    notifyListeners();
  }

  Future<void> setAiDifficulty(AiDifficulty value) async {
    _aiDifficulty = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('aiDifficulty', value.index);
    notifyListeners();
  }

  Future<void> setBoardBackground(BoardBackground value) async {
    _boardBackground = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('boardBackground', value.index);
    notifyListeners();
  }

  Future<void> setBoardSizePreset(BoardSizePreset value) async {
    _boardSizePreset = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('boardSizePreset', value.index);
    notifyListeners();
  }
}
