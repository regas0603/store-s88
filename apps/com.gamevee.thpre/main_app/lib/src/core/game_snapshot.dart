import 'dart:async' as async;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'game_history.dart' show MoveLog, GameMode;

/// Snapshot của một ván đang chơi dở (US-003).
///
/// Chỉ lưu state tối thiểu cần thiết để restore; các giá trị suy diễn được
/// (board matrix, totalMoves, currentPlayer, scores) **không** lưu — tính lại
/// từ [moves] khi restore để tránh drift và giảm size trên SharedPreferences.
///
/// Key lưu: [GameSnapshotStore.key] (1 slot duy nhất — không multi-save).
///
/// Note về schema: schemaVersion giữ ở 1. Key 'hints' có thể còn trong snapshot
/// cũ của user (nếu đã từng build có feature hint) — parser IGNORE key này,
/// không reject snapshot. Forward-compat: nếu tương lai re-add hint, chỉ cần
/// thêm field mới và đọc lại key 'hints'.
class GameSnapshot {
  /// Version của schema — tăng khi thay đổi cấu trúc để invalidate snapshot cũ.
  static const int schemaVersion = 1;

  final GameMode mode;
  final int boardSide;
  final int winLength;
  final int aiDifficultyIndex; // -1 cho PvP
  final List<MoveLog> moves;
  final int timeLeftSecs; // 0 nếu không dùng turn timer
  final DateTime savedAt;

  const GameSnapshot({
    required this.mode,
    required this.boardSide,
    required this.winLength,
    required this.aiDifficultyIndex,
    required this.moves,
    required this.timeLeftSecs,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'v': schemaVersion,
        'mode': mode.name,
        'side': boardSide,
        'win': winLength,
        'ai': aiDifficultyIndex,
        'time': timeLeftSecs,
        'savedAt': savedAt.millisecondsSinceEpoch,
        'moves': moves.map((m) => m.toJson()).toList(),
      };

  static GameSnapshot? fromJson(Map<String, dynamic> json) {
    try {
      final int v = (json['v'] as int?) ?? 0;
      if (v != schemaVersion) return null;
      final String modeName = json['mode'] as String;
      final GameMode mode = GameMode.values.firstWhere(
        (e) => e.name == modeName,
        orElse: () => GameMode.twoPlayers,
      );
      final List<dynamic> rawMoves = (json['moves'] as List<dynamic>? ?? <dynamic>[]);
      final List<MoveLog> moves = rawMoves
          .map((e) => MoveLog.fromJson(e as Map<String, dynamic>))
          .toList();
      // Lưu ý: key 'hints' (nếu có từ snapshot cũ) bị bỏ qua — không reject.
      return GameSnapshot(
        mode: mode,
        boardSide: json['side'] as int,
        winLength: json['win'] as int,
        aiDifficultyIndex: json['ai'] as int,
        moves: moves,
        timeLeftSecs: json['time'] as int,
        savedAt: DateTime.fromMillisecondsSinceEpoch(json['savedAt'] as int),
      );
    } catch (_) {
      return null;
    }
  }
}

/// I/O singleton cho [GameSnapshot]. Debounce 500ms để tránh ghi disk quá
/// nhiều khi user đặt quân liên tục.
class GameSnapshotStore {
  GameSnapshotStore._();
  static final GameSnapshotStore _i = GameSnapshotStore._();
  factory GameSnapshotStore() => _i;

  static const String key = 'in_progress_game';
  static const Duration _debounce = Duration(milliseconds: 500);

  async.Timer? _debounceTimer;
  GameSnapshot? _pending;

  /// Schedule save với debounce. Nhiều save liên tiếp chỉ commit lần cuối.
  void scheduleSave(GameSnapshot snap) {
    _pending = snap;
    _debounceTimer?.cancel();
    _debounceTimer = async.Timer(_debounce, _flush);
  }

  /// Force save ngay (dùng khi app lifecycle sắp paused/detached).
  Future<void> flushNow() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    await _flush();
  }

  Future<void> _flush() async {
    final GameSnapshot? s = _pending;
    if (s == null) return;
    _pending = null;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(s.toJson()));
    } catch (_) {
      // Silent — mất snapshot 1 lần không critical. History vẫn lưu khi game
      // kết thúc qua path riêng.
    }
  }

  Future<GameSnapshot?> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return null;
      final Map<String, dynamic> json = jsonDecode(raw) as Map<String, dynamic>;
      final GameSnapshot? snap = GameSnapshot.fromJson(json);
      // JSON hỏng hoặc schema mismatch → xóa để tránh loop
      if (snap == null) {
        await prefs.remove(key);
      }
      return snap;
    } catch (_) {
      // Corrupt JSON: cleanup và trả null
      try {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.remove(key);
      } catch (_) {}
      return null;
    }
  }

  Future<void> clear() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pending = null;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (_) {}
  }

  /// Nhanh: có snapshot không? (không parse đầy đủ)
  Future<bool> hasSnapshot() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(key);
      return raw != null && raw.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
