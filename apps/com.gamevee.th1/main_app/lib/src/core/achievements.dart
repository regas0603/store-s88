import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'game_analysis.dart';
import 'game_history.dart';

/// Achievement tier — quyết định màu huy hiệu.
enum BadgeTier { bronze, silver, gold, diamond }

/// Toàn bộ badge của app (US-004).
/// Thứ tự enum = thứ tự hiển thị trong grid.
enum BadgeId {
  firstGame,
  win10,
  win50,
  win100,
  streak3,
  streak7,
  beatAiLow,
  beatAiMedium,
  beatAiHigh,
  played10,
  played50,
  fastWin,
  blitzWin,
  allBoardSizes,
  slidingCapWinner,
  bigBoardWinner,
  modeVariety,
  skinExplorer,
  // ── US-005 ──
  // BẮT BUỘC thêm vào CUỐI: index của enum này được persist trong
  // AchievementStore, chèn vào giữa sẽ làm lệch badge của người dùng hiện hữu.
  perfectGame,
  analyst,
}

/// Định nghĩa static của mỗi badge. [l10nKey] trỏ tới string trong l10n.
/// Ví dụ key "badge_win10_name" và "badge_win10_desc".
class BadgeDef {
  final BadgeId id;
  final BadgeTier tier;
  final IconData icon;
  final String l10nKey; // base key, ghép "_name" và "_desc"

  const BadgeDef({
    required this.id,
    required this.tier,
    required this.icon,
    required this.l10nKey,
  });

  Color get tierColor {
    switch (tier) {
      case BadgeTier.bronze:
        return const Color(0xFFCD7F32);
      case BadgeTier.silver:
        return const Color(0xFFC0C0C0);
      case BadgeTier.gold:
        return const Color(0xFFFFD700);
      case BadgeTier.diamond:
        return const Color(0xFFB9F2FF);
    }
  }
}

/// Registry — single source of truth về định nghĩa badge.
class BadgeCatalog {
  BadgeCatalog._();

  static const Map<BadgeId, BadgeDef> _all = <BadgeId, BadgeDef>{
    BadgeId.firstGame: BadgeDef(
      id: BadgeId.firstGame,
      tier: BadgeTier.bronze,
      icon: Icons.flag_rounded,
      l10nKey: 'badge_firstGame',
    ),
    BadgeId.win10: BadgeDef(
      id: BadgeId.win10,
      tier: BadgeTier.bronze,
      icon: Icons.emoji_events_rounded,
      l10nKey: 'badge_win10',
    ),
    BadgeId.win50: BadgeDef(
      id: BadgeId.win50,
      tier: BadgeTier.silver,
      icon: Icons.emoji_events_rounded,
      l10nKey: 'badge_win50',
    ),
    BadgeId.win100: BadgeDef(
      id: BadgeId.win100,
      tier: BadgeTier.gold,
      icon: Icons.emoji_events_rounded,
      l10nKey: 'badge_win100',
    ),
    BadgeId.streak3: BadgeDef(
      id: BadgeId.streak3,
      tier: BadgeTier.bronze,
      icon: Icons.local_fire_department_rounded,
      l10nKey: 'badge_streak3',
    ),
    BadgeId.streak7: BadgeDef(
      id: BadgeId.streak7,
      tier: BadgeTier.silver,
      icon: Icons.local_fire_department_rounded,
      l10nKey: 'badge_streak7',
    ),
    BadgeId.beatAiLow: BadgeDef(
      id: BadgeId.beatAiLow,
      tier: BadgeTier.bronze,
      icon: Icons.smart_toy_rounded,
      l10nKey: 'badge_beatAiLow',
    ),
    BadgeId.beatAiMedium: BadgeDef(
      id: BadgeId.beatAiMedium,
      tier: BadgeTier.silver,
      icon: Icons.smart_toy_rounded,
      l10nKey: 'badge_beatAiMedium',
    ),
    BadgeId.beatAiHigh: BadgeDef(
      id: BadgeId.beatAiHigh,
      tier: BadgeTier.gold,
      icon: Icons.smart_toy_rounded,
      l10nKey: 'badge_beatAiHigh',
    ),
    BadgeId.played10: BadgeDef(
      id: BadgeId.played10,
      tier: BadgeTier.bronze,
      icon: Icons.videogame_asset_rounded,
      l10nKey: 'badge_played10',
    ),
    BadgeId.played50: BadgeDef(
      id: BadgeId.played50,
      tier: BadgeTier.silver,
      icon: Icons.videogame_asset_rounded,
      l10nKey: 'badge_played50',
    ),
    BadgeId.fastWin: BadgeDef(
      id: BadgeId.fastWin,
      tier: BadgeTier.silver,
      icon: Icons.bolt_rounded,
      l10nKey: 'badge_fastWin',
    ),
    BadgeId.blitzWin: BadgeDef(
      id: BadgeId.blitzWin,
      tier: BadgeTier.silver,
      icon: Icons.speed_rounded,
      l10nKey: 'badge_blitzWin',
    ),
    BadgeId.allBoardSizes: BadgeDef(
      id: BadgeId.allBoardSizes,
      tier: BadgeTier.gold,
      icon: Icons.grid_view_rounded,
      l10nKey: 'badge_allBoardSizes',
    ),
    BadgeId.slidingCapWinner: BadgeDef(
      id: BadgeId.slidingCapWinner,
      tier: BadgeTier.silver,
      icon: Icons.swap_horiz_rounded,
      l10nKey: 'badge_slidingCapWinner',
    ),
    BadgeId.bigBoardWinner: BadgeDef(
      id: BadgeId.bigBoardWinner,
      tier: BadgeTier.silver,
      icon: Icons.apps_rounded,
      l10nKey: 'badge_bigBoardWinner',
    ),
    BadgeId.modeVariety: BadgeDef(
      id: BadgeId.modeVariety,
      tier: BadgeTier.bronze,
      icon: Icons.sync_alt_rounded,
      l10nKey: 'badge_modeVariety',
    ),
    BadgeId.skinExplorer: BadgeDef(
      id: BadgeId.skinExplorer,
      tier: BadgeTier.silver,
      icon: Icons.palette_rounded,
      l10nKey: 'badge_skinExplorer',
    ),
    BadgeId.perfectGame: BadgeDef(
      id: BadgeId.perfectGame,
      tier: BadgeTier.diamond,
      icon: Icons.auto_awesome_rounded,
      l10nKey: 'badge_perfectGame',
    ),
    BadgeId.analyst: BadgeDef(
      id: BadgeId.analyst,
      tier: BadgeTier.silver,
      icon: Icons.insights_rounded,
      l10nKey: 'badge_analyst',
    ),
  };

  static BadgeDef def(BadgeId id) => _all[id]!;
  static List<BadgeDef> get all => BadgeId.values.map(def).toList();
  static int get count => BadgeId.values.length;
}

/// Pure function: từ [records] tính ra set badge đã unlock.
///
/// **Nguyên tắc:**
/// - Source of truth là [GameHistory.records]. Khi user clear history, badge
///   sẽ re-compute lại (có thể bị reset). Trade-off: consistency > persistence.
/// - Chỉ đếm [GameResult.xWins] là "user thắng" (theo convention user = X).
///   PvP mode: cả X và O đều là "user" nhưng ta đếm X-wins để nhất quán với
///   cách `GameRecord` ghi — không phân biệt seat. Documented limitation.
class AchievementEngine {
  AchievementEngine._();

  static Set<BadgeId> evaluate(List<GameRecord> records) {
    final Set<BadgeId> unlocked = <BadgeId>{};
    if (records.isEmpty) return unlocked;

    // Ghi chú: records đã được sort giảm dần theo playedAt trong GameHistory.
    // Ta cần tăng dần (từ cũ → mới) để tính streak theo thứ tự thời gian.
    final List<GameRecord> asc = List<GameRecord>.from(records).reversed.toList();

    // ── Counters ──
    final int totalGames = asc.length;
    int xWins = 0;
    int bestStreak = 0;
    int currentStreak = 0;
    bool hasVsAi = false;
    bool hasPvp = false;
    final Set<int> boardSidesPlayed = <int>{};
    final Set<String> skinsUsed = <String>{};
    bool hasFastWin = false;
    bool hasBlitzWin = false;
    bool hasSlidingCapWin = false;
    bool hasBigBoardWin = false;
    bool beatAiLow = false, beatAiMed = false, beatAiHigh = false;
    int analyzedGames = 0;
    bool hasPerfectGame = false;

    for (final GameRecord r in asc) {
      // US-005: badge dựa trên kết quả phân tích (nếu ván đã được phân tích).
      final GameAnalysis? an = r.analysis;
      if (an != null) {
        analyzedGames++;
        final Map<MoveQuality, int> c = an.counts;
        final bool noBadMoves = (c[MoveQuality.mistake] ?? 0) == 0 &&
            (c[MoveQuality.blunder] ?? 0) == 0;
        // Chỉ tính ván có đủ số nước được chấm — ván 4 nước mà 100% thì không
        // đáng gọi là hoàn hảo.
        if (noBadMoves && an.accuracyX >= 95 && an.scoredIndexes.length >= 8) {
          hasPerfectGame = true;
        }
      }
      if (r.mode == GameMode.vsAI) hasVsAi = true;
      if (r.mode == GameMode.twoPlayers) hasPvp = true;
      boardSidesPlayed.add(r.boardSide);
      skinsUsed.add(r.skinName);

      final bool userWon = r.result == GameResult.xWins;
      if (userWon) {
        xWins++;
        currentStreak++;
        if (currentStreak > bestStreak) bestStreak = currentStreak;
        if (r.totalMoves > 0 && r.totalMoves <= 10) hasFastWin = true;
        if (r.durationSecs > 0 && r.durationSecs <= 60) hasBlitzWin = true;
        if (r.boardSide == 3 || r.boardSide == 4) hasSlidingCapWin = true;
        if (r.boardSide >= 13) hasBigBoardWin = true;
        if (r.mode == GameMode.vsAI) {
          switch (r.aiDifficultyIndex) {
            case 0:
              beatAiLow = true;
              break;
            case 1:
              beatAiMed = true;
              break;
            case 2:
              beatAiHigh = true;
              break;
          }
        }
      } else {
        currentStreak = 0;
      }
    }

    // ── Assign badges ──
    unlocked.add(BadgeId.firstGame);
    if (xWins >= 10) unlocked.add(BadgeId.win10);
    if (xWins >= 50) unlocked.add(BadgeId.win50);
    if (xWins >= 100) unlocked.add(BadgeId.win100);
    if (bestStreak >= 3) unlocked.add(BadgeId.streak3);
    if (bestStreak >= 7) unlocked.add(BadgeId.streak7);
    if (beatAiLow) unlocked.add(BadgeId.beatAiLow);
    if (beatAiMed) unlocked.add(BadgeId.beatAiMedium);
    if (beatAiHigh) unlocked.add(BadgeId.beatAiHigh);
    if (totalGames >= 10) unlocked.add(BadgeId.played10);
    if (totalGames >= 50) unlocked.add(BadgeId.played50);
    if (hasFastWin) unlocked.add(BadgeId.fastWin);
    if (hasBlitzWin) unlocked.add(BadgeId.blitzWin);
    // 6 board sizes: 3, 4, 6, 9, 13, 15
    if (boardSidesPlayed.length >= 6) unlocked.add(BadgeId.allBoardSizes);
    if (hasSlidingCapWin) unlocked.add(BadgeId.slidingCapWinner);
    if (hasBigBoardWin) unlocked.add(BadgeId.bigBoardWinner);
    if (hasVsAi && hasPvp) unlocked.add(BadgeId.modeVariety);
    if (skinsUsed.length >= 3) unlocked.add(BadgeId.skinExplorer);
    if (hasPerfectGame) unlocked.add(BadgeId.perfectGame);
    if (analyzedGames >= 10) unlocked.add(BadgeId.analyst);

    return unlocked;
  }
}

/// Store persist mốc thời gian lần đầu unlock mỗi badge. Dùng để:
/// - Detect "newly unlocked" = trong tập unlocked mới mà chưa có timestamp cũ.
/// - Show ngày đạt trong badge detail dialog.
class AchievementStore extends ChangeNotifier {
  static final AchievementStore _i = AchievementStore._();
  factory AchievementStore() => _i;
  AchievementStore._();

  static const String _key = 'badge_unlocked_at';
  Map<BadgeId, DateTime> _unlockedAt = <BadgeId, DateTime>{};
  Map<BadgeId, DateTime> get unlockedAt =>
      Map<BadgeId, DateTime>.unmodifiable(_unlockedAt);

  /// Notifier cho các badge mới unlock cần show toast. UI consume rồi dọn.
  final ValueNotifier<List<BadgeId>> newlyUnlockedQueue =
      ValueNotifier<List<BadgeId>>(<BadgeId>[]);

  Future<void> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final Map<String, dynamic> json =
          jsonDecode(raw) as Map<String, dynamic>;
      final Map<BadgeId, DateTime> parsed = <BadgeId, DateTime>{};
      json.forEach((String k, dynamic v) {
        // Tránh phụ thuộc firstOrNull (có thể cần import) — dùng loop tường minh.
        BadgeId? id;
        for (final BadgeId b in BadgeId.values) {
          if (b.name == k) {
            id = b;
            break;
          }
        }
        if (id != null && v is int) {
          parsed[id] = DateTime.fromMillisecondsSinceEpoch(v);
        }
      });
      _unlockedAt = parsed;
    } catch (_) {
      _unlockedAt = <BadgeId, DateTime>{};
    }
  }

  Future<void> _persist() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final Map<String, int> json = <String, int>{
        for (final MapEntry<BadgeId, DateTime> e in _unlockedAt.entries)
          e.key.name: e.value.millisecondsSinceEpoch,
      };
      await prefs.setString(_key, jsonEncode(json));
    } catch (_) {}
  }

  /// Sync [AchievementStore] với kết quả evaluate. Trả về list badge vừa
  /// unlock lần đầu (để UI show toast). Badge đã có timestamp sẽ không fire
  /// lại dù re-compute nhiều lần.
  Future<List<BadgeId>> syncWithUnlocked(Set<BadgeId> unlocked) async {
    final DateTime now = DateTime.now();
    final List<BadgeId> fresh = <BadgeId>[];
    for (final BadgeId id in unlocked) {
      if (!_unlockedAt.containsKey(id)) {
        _unlockedAt[id] = now;
        fresh.add(id);
      }
    }
    if (fresh.isNotEmpty) {
      await _persist();
      // Append vào queue, notify UI. UI tự dọn sau khi show.
      newlyUnlockedQueue.value = <BadgeId>[...newlyUnlockedQueue.value, ...fresh];
      notifyListeners();
    }
    return fresh;
  }

  /// UI gọi sau khi đã show toast để lấy badge kế tiếp.
  void popFromQueue(BadgeId id) {
    final List<BadgeId> next = List<BadgeId>.from(newlyUnlockedQueue.value)
      ..remove(id);
    newlyUnlockedQueue.value = next;
  }

  bool isUnlocked(BadgeId id) => _unlockedAt.containsKey(id);
  DateTime? unlockedDate(BadgeId id) => _unlockedAt[id];
  int get unlockedCount => _unlockedAt.length;
}

