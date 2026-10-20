import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kỷ lục của một cấu hình chơi đơn cụ thể (khoảng số + độ khó).
@immutable
class SoloRecord {
  /// Thời gian tốt nhất, mili-giây. null = chưa có.
  final int? bestTimeMs;

  /// Số lượt đoán ít nhất. null = chưa có.
  final int? bestGuesses;

  /// Số vòng sống sót nhiều nhất ở chế độ Sinh tồn. null = chưa có.
  final int? bestStreak;

  const SoloRecord({this.bestTimeMs, this.bestGuesses, this.bestStreak});

  bool get isEmpty =>
      bestTimeMs == null && bestGuesses == null && bestStreak == null;
}

/// Lưu thành tích. Dữ liệu phẳng, ít, đọc nhiều ghi ít — shared_preferences là
/// vừa đủ. Chỉ nên đổi sang sqlite/Isar khi cần lưu lịch sử từng ván.
class StatsRepository extends ChangeNotifier {
  static const _kGamesPlayed = 'stats.gamesPlayed';
  static const _kSolved = 'stats.solved';
  static const _kUnsolved = 'stats.unsolved';

  SharedPreferences? _prefs;
  final Map<String, SoloRecord> _records = <String, SoloRecord>{};

  int _gamesPlayed = 0;
  int _solved = 0;
  int _unsolved = 0;

  int get gamesPlayed => _gamesPlayed;

  /// Số ván chơi đơn đoán ra được.
  int get solved => _solved;

  /// Số ván chơi đơn hết lượt mà vẫn chưa ra.
  int get unsolved => _unsolved;

  SoloRecord recordFor(String key) => _records[key] ?? const SoloRecord();

  static String _timeKey(String key) => 'stats.record.$key.timeMs';
  static String _guessKey(String key) => 'stats.record.$key.guesses';
  static String _streakKey(String key) => 'stats.record.$key.streak';

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      _gamesPlayed = prefs.getInt(_kGamesPlayed) ?? 0;
      _solved = prefs.getInt(_kSolved) ?? 0;
      _unsolved = prefs.getInt(_kUnsolved) ?? 0;

      _records.clear();
      for (final prefKey in prefs.getKeys()) {
        if (!prefKey.startsWith('stats.record.')) continue;
        final parts = prefKey.split('.');
        if (parts.length != 4) continue;
        final recordKey = parts[2];
        if (_records.containsKey(recordKey)) continue;
        _records[recordKey] = SoloRecord(
          bestTimeMs: prefs.getInt(_timeKey(recordKey)),
          bestGuesses: prefs.getInt(_guessKey(recordKey)),
          bestStreak: prefs.getInt(_streakKey(recordKey)),
        );
      }
    } catch (_) {
      // Bỏ qua: thành tích không phải dữ liệu sống còn.
    }
    notifyListeners();
  }

  /// Ghi nhận một ván chơi đơn ĐÃ đoán ra.
  ///
  /// Trả về true nếu phá được ít nhất một kỷ lục — UI dùng để khoe "Kỷ lục mới!".
  Future<bool> submitSolo({
    required String recordKey,
    required int elapsedMs,
    required int guesses,
  }) async {
    final current = recordFor(recordKey);
    final betterTime =
        current.bestTimeMs == null || elapsedMs < current.bestTimeMs!;
    final betterGuesses =
        current.bestGuesses == null || guesses < current.bestGuesses!;

    _records[recordKey] = SoloRecord(
      bestTimeMs: betterTime ? elapsedMs : current.bestTimeMs,
      bestGuesses: betterGuesses ? guesses : current.bestGuesses,
      bestStreak: current.bestStreak,
    );
    _gamesPlayed++;
    _solved++;
    notifyListeners();

    final prefs = _prefs;
    if (prefs != null) {
      try {
        if (betterTime) await prefs.setInt(_timeKey(recordKey), elapsedMs);
        if (betterGuesses) await prefs.setInt(_guessKey(recordKey), guesses);
        await prefs.setInt(_kGamesPlayed, _gamesPlayed);
        await prefs.setInt(_kSolved, _solved);
      } catch (_) {
        // ignore
      }
    }
    return betterTime || betterGuesses;
  }

  /// Ghi nhận một ván chơi đơn hết lượt mà chưa đoán ra. Không đụng tới kỷ lục.
  Future<void> registerUnsolved() async {
    _gamesPlayed++;
    _unsolved++;
    notifyListeners();
    try {
      await _prefs?.setInt(_kGamesPlayed, _gamesPlayed);
      await _prefs?.setInt(_kUnsolved, _unsolved);
    } catch (_) {
      // ignore
    }
  }

  /// Ghi nhận một ván Sinh tồn đã kết thúc.
  ///
  /// [streak] là số vòng đoán ra được. Vòng đang chơi dở lúc hết lượt KHÔNG
  /// tính — nó là vòng thua.
  ///
  /// Trả về true nếu phá kỷ lục chuỗi. Một ván sinh tồn tính là **một** ván
  /// trong `gamesPlayed`, dù có bao nhiêu vòng: nếu tính từng vòng thì tỉ lệ
  /// "đoán ra" sẽ bị thổi phồng so với chơi đơn.
  Future<bool> submitSurvival({
    required String recordKey,
    required int streak,
  }) async {
    final current = recordFor(recordKey);
    final better = current.bestStreak == null || streak > current.bestStreak!;

    _records[recordKey] = SoloRecord(
      bestTimeMs: current.bestTimeMs,
      bestGuesses: current.bestGuesses,
      bestStreak: better ? streak : current.bestStreak,
    );
    _gamesPlayed++;
    if (streak > 0) {
      _solved++;
    } else {
      _unsolved++;
    }
    notifyListeners();

    final prefs = _prefs;
    if (prefs != null) {
      try {
        if (better) await prefs.setInt(_streakKey(recordKey), streak);
        await prefs.setInt(_kGamesPlayed, _gamesPlayed);
        await prefs.setInt(_kSolved, _solved);
        await prefs.setInt(_kUnsolved, _unsolved);
      } catch (_) {
        // ignore
      }
    }
    return better;
  }

  /// Ghi nhận một ván 2 người (không có kỷ lục cá nhân để so).
  Future<void> submitDuel() async {
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
    _solved = 0;
    _unsolved = 0;
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
