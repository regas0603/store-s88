import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kỷ lục của một cấu hình chơi đơn cụ thể (chế độ + cỡ bàn).
@immutable
class SoloRecord {
  /// Thời gian tốt nhất, mili-giây. null = chưa có.
  final int? bestTimeMs;

  /// Số nước đi ít nhất. null = chưa có.
  final int? bestMoves;

  const SoloRecord({this.bestTimeMs, this.bestMoves});

  bool get isEmpty => bestTimeMs == null && bestMoves == null;
}

/// Kết quả một ván đấu với AI.
enum VsAiResult { win, loss, draw }

/// Lưu thành tích. Dữ liệu phẳng, ít, đọc nhiều ghi ít — shared_preferences là
/// vừa đủ. Chỉ nên đổi sang sqlite/Isar khi cần lưu lịch sử từng ván.
class StatsRepository extends ChangeNotifier {
  static const _kGamesPlayed = 'stats.gamesPlayed';
  static const _kAiWin = 'stats.ai.win';
  static const _kAiLoss = 'stats.ai.loss';
  static const _kAiDraw = 'stats.ai.draw';

  SharedPreferences? _prefs;
  final Map<String, SoloRecord> _records = <String, SoloRecord>{};

  int _gamesPlayed = 0;
  int _aiWins = 0;
  int _aiLosses = 0;
  int _aiDraws = 0;

  int get gamesPlayed => _gamesPlayed;
  int get aiWins => _aiWins;
  int get aiLosses => _aiLosses;
  int get aiDraws => _aiDraws;

  SoloRecord recordFor(String key) => _records[key] ?? const SoloRecord();

  static String _timeKey(String key) => 'stats.record.$key.timeMs';
  static String _movesKey(String key) => 'stats.record.$key.moves';

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      _gamesPlayed = prefs.getInt(_kGamesPlayed) ?? 0;
      _aiWins = prefs.getInt(_kAiWin) ?? 0;
      _aiLosses = prefs.getInt(_kAiLoss) ?? 0;
      _aiDraws = prefs.getInt(_kAiDraw) ?? 0;

      _records.clear();
      for (final prefKey in prefs.getKeys()) {
        if (!prefKey.startsWith('stats.record.')) continue;
        final parts = prefKey.split('.');
        if (parts.length != 4) continue;
        final recordKey = parts[2];
        final existing = _records[recordKey] ?? const SoloRecord();
        _records[recordKey] = SoloRecord(
          bestTimeMs: prefs.getInt(_timeKey(recordKey)) ?? existing.bestTimeMs,
          bestMoves: prefs.getInt(_movesKey(recordKey)) ?? existing.bestMoves,
        );
      }
    } catch (_) {
      // Bỏ qua: thành tích không phải dữ liệu sống còn.
    }
    notifyListeners();
  }

  /// Ghi nhận một ván chơi đơn vừa hoàn thành.
  ///
  /// Trả về true nếu phá được ít nhất một kỷ lục — UI dùng để khoe "Kỷ lục mới!".
  Future<bool> submitSolo({
    required String recordKey,
    required int elapsedMs,
    required int moves,
  }) async {
    final current = recordFor(recordKey);
    final betterTime = current.bestTimeMs == null || elapsedMs < current.bestTimeMs!;
    final betterMoves = current.bestMoves == null || moves < current.bestMoves!;

    _records[recordKey] = SoloRecord(
      bestTimeMs: betterTime ? elapsedMs : current.bestTimeMs,
      bestMoves: betterMoves ? moves : current.bestMoves,
    );
    _gamesPlayed++;
    notifyListeners();

    final prefs = _prefs;
    if (prefs != null) {
      try {
        if (betterTime) await prefs.setInt(_timeKey(recordKey), elapsedMs);
        if (betterMoves) await prefs.setInt(_movesKey(recordKey), moves);
        await prefs.setInt(_kGamesPlayed, _gamesPlayed);
      } catch (_) {
        // ignore
      }
    }
    return betterTime || betterMoves;
  }

  /// Ghi nhận kết quả một ván đấu AI.
  Future<void> submitVsAi(VsAiResult result) async {
    switch (result) {
      case VsAiResult.win:
        _aiWins++;
        break;
      case VsAiResult.loss:
        _aiLosses++;
        break;
      case VsAiResult.draw:
        _aiDraws++;
        break;
    }
    _gamesPlayed++;
    notifyListeners();

    final prefs = _prefs;
    if (prefs == null) return;
    try {
      await prefs.setInt(_kAiWin, _aiWins);
      await prefs.setInt(_kAiLoss, _aiLosses);
      await prefs.setInt(_kAiDraw, _aiDraws);
      await prefs.setInt(_kGamesPlayed, _gamesPlayed);
    } catch (_) {
      // ignore
    }
  }

  /// Ghi nhận một ván 2 người (không có kỷ lục cá nhân để so).
  Future<void> submitPvp() async {
    _gamesPlayed++;
    notifyListeners();
    try {
      await _prefs?.setInt(_kGamesPlayed, _gamesPlayed);
    } catch (_) {
      // ignore
    }
  }

  /// Xoá sạch thành tích. Màn Cài đặt phải hỏi xác nhận trước khi gọi.
  Future<void> reset() async {
    _records.clear();
    _gamesPlayed = 0;
    _aiWins = 0;
    _aiLosses = 0;
    _aiDraws = 0;
    notifyListeners();

    final prefs = _prefs;
    if (prefs == null) return;
    try {
      final doomed = prefs
          .getKeys()
          .where((k) => k.startsWith('stats.'))
          .toList(growable: false);
      for (final key in doomed) {
        await prefs.remove(key);
      }
    } catch (_) {
      // ignore
    }
  }
}
