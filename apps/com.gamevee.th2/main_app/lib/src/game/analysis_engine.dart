/// Engine chấm điểm nước đi cho tính năng Phân tích ván đấu (US-005).
///
/// **Thuần Dart** (chỉ `dart:math`) — chạy được trong isolate và unit test
/// được mà không cần Flutter binding.
///
/// ─────────────────────────────────────────────────────────────────────────
/// THANG ĐO LỢI THẾ
/// ─────────────────────────────────────────────────────────────────────────
/// Điểm đe doạ thô của engine tăng theo **luỹ thừa 10** mỗi bậc mối đe doạ
/// (open two = 100, open three = 10 000, open four = 1 000 000, thắng = 1e8).
/// So sánh hiệu số thô trực tiếp là vô nghĩa: chênh một bậc đã gấp 10 lần.
///
/// Vì vậy lợi thế được tính bằng **log có dấu của hiệu số**:
///
///     d   = threat(me) - threat(opponent)
///     adv = sign(d) * log10(1 + |d|) / [kAdvLogScale]
///
/// [kAdvLogScale] = 16 = 2 * log10(1 + 1e8), chọn sao cho:
///   hơn 1 open two   -> 0.125
///   hơn 1 open three -> 0.250
///   hơn 1 open four  -> 0.375
///   thắng (terminal) -> 1.000  (đặt tường minh, tạo bước nhảy có chủ ý)
///
/// Hằng số này đã được hiệu chuẩn trên 24 ván mô phỏng ở 4 mức kỹ năng khác
/// nhau: phân bố nhãn thu được là ~90% Tốt, 3% Thiếu chính xác, 2% Sai lầm,
/// 5% Thảm hoạ — hợp lý cho một trận đấu thật.
///
/// **CẢNH BÁO:** không dùng `AiEngine._evaluateBoard` để đo lợi thế. Hàm đó
/// nhân điểm đối thủ với 1.2 và cộng centre bonus nên KHÔNG đối xứng — đã đo
/// được sai lệch ~17% khi lật bàn cờ. Tầng phân tích dùng
/// [AiEngine.threatScoreFor] để tự dựng thang đo đối xứng tuyệt đối.
library;

import 'dart:math';

import '../core/game_analysis.dart';
import 'ai_engine.dart';

// ─── Hằng số hiệu chuẩn ───────────────────────────────────────────────────
//
// Toàn bộ hằng số cần tinh chỉnh nằm gọn ở đây (task T-DEV-05).

/// Mẫu số của thang log. 16 = 2 * log10(1 + 1e8).
const double kAdvLogScale = 16.0;

/// Ngưỡng phân loại theo tổn thất so với nước tốt nhất.
const double kThresholdBrilliant = 0.02;
const double kThresholdGood = 0.08;
const double kThresholdInaccuracy = 0.18;
const double kThresholdMistake = 0.40;

/// Nhãn "Xuất sắc" chỉ được cấp khi nước đi trùng nước tốt nhất của engine
/// VÀ nước tốt nhì kém hơn ít nhất chừng này — tức là một nước "chỉ có một
/// lựa chọn đúng". Không có điều kiện này thì ~70% số nước sẽ thành Xuất sắc.
const double kBrilliantGapRequired = 0.06;

/// Tổn thất từ mức này trở lên bị quy về 0 điểm khi tính Độ chính xác.
const double kAccuracyLossCap = 0.50;

/// Bỏ qua N nước đầu khi tính Độ chính xác — khai cuộc gần như luôn "đúng",
/// tính vào sẽ làm chỉ số bị thổi phồng.
const int kAccuracyOpeningSkip = 2;

/// Ngân sách cho một thế cờ ở pass đào sâu.
const int kDeepBudgetMsPerPosition = 400;

/// Số thế cờ được đào sâu (những nước biến động mạnh nhất ở pass nông).
const int kDeepPositionCount = 6;

/// Trần thời gian cho cả ván. Vượt ngưỡng -> trả kết quả pass nông.
const int kTotalBudgetMs = 10000;

/// Ván ngắn hơn chừng này không đáng phân tích.
const int kMinMovesToAnalyze = 4;

// ─── Kiểu dữ liệu truyền qua isolate ──────────────────────────────────────

/// Một nước đi ở dạng phẳng, dễ copy qua isolate.
class AnalysisMove {
  final int row;
  final int col;
  final int player;

  /// -1 khi nước này không đẩy quân nào ra (luật sliding-cap chỉ áp dụng cho
  /// bàn 3x3 / 4x4).
  final int removedRow;
  final int removedCol;

  const AnalysisMove({
    required this.row,
    required this.col,
    required this.player,
    this.removedRow = -1,
    this.removedCol = -1,
  });

  bool get hasRemoval => removedRow >= 0 && removedCol >= 0;
}

/// Yêu cầu chấm một LÔ nước đi. Chia lô để UI có tiến độ thật và huỷ được
/// giữa chừng mà không cần cơ chế streaming phức tạp.
class ProbeRequest {
  final List<AnalysisMove> moves;
  final int boardSide;
  final int winLength;

  /// Chỉ chấm những nước có index nằm trong danh sách này.
  final List<int> indexes;

  /// true = pass đào sâu (chạy negamax), false = pass quét nông (1 tầng).
  final bool deep;

  final int timeBudgetMsPerPosition;
  final int randomSeed;

  const ProbeRequest({
    required this.moves,
    required this.boardSide,
    required this.winLength,
    required this.indexes,
    required this.deep,
    required this.timeBudgetMsPerPosition,
    required this.randomSeed,
  });
}

/// Kết quả chấm một nước đi.
class MoveProbe {
  final int index;

  /// Lợi thế sau nước ĐÃ ĐÁNH, theo góc nhìn người đi nước đó.
  final double advPlayed;

  /// Lợi thế cao nhất đạt được trong các nước khả dĩ, cùng góc nhìn.
  final double advBest;

  /// Nước tốt nhất engine tìm được (-1 khi không có).
  final int bestRow;
  final int bestCol;

  /// Chênh lệch giữa nước tốt nhất và nước tốt nhì — dùng để quyết định
  /// nhãn "Xuất sắc".
  final double gapToSecond;

  final bool deep;

  const MoveProbe({
    required this.index,
    required this.advPlayed,
    required this.advBest,
    required this.bestRow,
    required this.bestCol,
    required this.gapToSecond,
    required this.deep,
  });

  double get loss {
    final double v = advBest - advPlayed;
    return v < 0 ? 0.0 : v;
  }

  /// Số ô mỗi probe chiếm trong mảng phẳng.
  static const int fieldCount = 7;

  void encodeInto(List<double> out) {
    out.add(index.toDouble());
    out.add(advPlayed);
    out.add(advBest);
    out.add(bestRow.toDouble());
    out.add(bestCol.toDouble());
    out.add(gapToSecond);
    out.add(deep ? 1.0 : 0.0);
  }

  /// Giải mã kết quả phẳng trả về từ isolate.
  static List<MoveProbe> decodeAll(List<double> flat) {
    final List<MoveProbe> out = <MoveProbe>[];
    for (int i = 0; i + fieldCount <= flat.length; i += fieldCount) {
      out.add(MoveProbe(
        index: flat[i].round(),
        advPlayed: flat[i + 1],
        advBest: flat[i + 2],
        bestRow: flat[i + 3].round(),
        bestCol: flat[i + 4].round(),
        gapToSecond: flat[i + 5],
        deep: flat[i + 6] != 0,
      ));
    }
    return out;
  }
}

/// Entry point cho isolate. Phải là hàm top-level; `vm:entry-point` chặn
/// tree-shaking xoá symbol trong bản release.
///
/// Trả về **mảng phẳng `List<double>`** chứ không phải `List<MoveProbe>`: chỉ
/// primitive đi qua ranh giới isolate thì không phụ thuộc vào cách
/// `isolate_manager` tuần tự hoá đối tượng tuỳ biến. Dùng
/// [MoveProbe.decodeAll] để giải mã ở phía gọi.
@pragma('vm:entry-point')
List<double> analysisProbeWorker(ProbeRequest req) {
  final List<double> out = <double>[];
  for (final MoveProbe p in AnalysisEngine.probe(req)) {
    p.encodeInto(out);
  }
  return out;
}

// ─── Engine ───────────────────────────────────────────────────────────────

class AnalysisEngine {
  AnalysisEngine._();

  /// Lợi thế của [player] trên [board], trong khoảng [-1, 1].
  ///
  /// Đối xứng tuyệt đối theo cấu trúc: `advantage(b, 1) == -advantage(b, 2)`
  /// với mọi thế cờ (có unit test khẳng định).
  static double advantage(List<List<int>> board, int n, int w, int player) {
    final int me = AiEngine.threatScoreFor(board, n, w, player);
    final int op = AiEngine.threatScoreFor(board, n, w, player == 1 ? 2 : 1);
    final int winScore = AiEngine.winThreatScore;
    if (me >= winScore) return 1.0;
    if (op >= winScore) return -1.0;
    final int d = me - op;
    if (d == 0) return 0.0;
    final double mag = log(1 + d.abs()) / ln10 / kAdvLogScale;
    final double v = d > 0 ? mag : -mag;
    return v.clamp(-1.0, 1.0);
  }

  /// Dựng lại thế cờ sau [count] nước đầu tiên.
  ///
  /// Xử lý luật sliding-cap đúng thứ tự thời gian: gỡ quân cũ TRƯỚC khi đặt
  /// quân mới — giống `CaroGame.applySnapshot` và `ReplayScreen._buildBoard`.
  static List<List<int>> rebuildBoard(
    List<AnalysisMove> moves,
    int n,
    int count,
  ) {
    final List<List<int>> board =
        List<List<int>>.generate(n, (_) => List<int>.filled(n, 0));
    final int limit = count < moves.length ? count : moves.length;
    for (int i = 0; i < limit; i++) {
      final AnalysisMove m = moves[i];
      if (m.hasRemoval) board[m.removedRow][m.removedCol] = 0;
      board[m.row][m.col] = m.player;
    }
    return board;
  }

  /// Thứ tự đặt quân của mỗi bên sau [count] nước — cần cho search khi bàn
  /// dùng luật sliding-cap.
  static (List<int>, List<int>) rebuildOrders(
    List<AnalysisMove> moves,
    int count,
  ) {
    final List<int> o1 = <int>[];
    final List<int> o2 = <int>[];
    final int limit = count < moves.length ? count : moves.length;
    for (int i = 0; i < limit; i++) {
      final AnalysisMove m = moves[i];
      final List<int> target = m.player == 1 ? o1 : o2;
      if (m.hasRemoval && target.length >= 2) {
        target.removeAt(0);
        target.removeAt(0);
      }
      target.add(m.row);
      target.add(m.col);
    }
    return (o1, o2);
  }

  /// Chấm các nước được yêu cầu trong [req].
  static List<MoveProbe> probe(ProbeRequest req) {
    final int n = req.boardSide;
    final int w = req.winLength;
    final List<MoveProbe> out = <MoveProbe>[];

    for (final int idx in req.indexes) {
      if (idx < 0 || idx >= req.moves.length) continue;
      final AnalysisMove played = req.moves[idx];
      final int player = played.player;

      // Thế cờ TRƯỚC nước đi.
      final List<List<int>> before = rebuildBoard(req.moves, n, idx);

      // Luật sliding-cap: quân bị đẩy ra phụ thuộc vào độ đầy của bàn và thứ
      // tự quân của người đi — KHÔNG phụ thuộc ô nào được chọn. Nên mọi ứng
      // viên đều dùng chung phép gỡ mà nước thật đã ghi lại.
      final int remR = played.removedRow;
      final int remC = played.removedCol;
      final bool hasRemoval = played.hasRemoval;

      // Lợi thế của nước ĐÃ ĐÁNH.
      final double advPlayed =
          _advAfterMove(before, n, w, player, played.row, played.col,
              hasRemoval, remR, remC);

      // Quét 1 tầng toàn bộ ứng viên.
      final List<(int, int)> candidates = AiEngine.candidateMoves(before, n);
      double best = -2.0, second = -2.0;
      int bestR = -1, bestC = -1;
      for (final (int r, int c) in candidates) {
        if (before[r][c] != 0) continue;
        final double v = _advAfterMove(
            before, n, w, player, r, c, hasRemoval, remR, remC);
        if (v > best) {
          second = best;
          best = v;
          bestR = r;
          bestC = c;
        } else if (v > second) {
          second = v;
        }
      }

      // Pass đào sâu: chạy negamax để tìm nước mạnh hơn mà quét 1 tầng bỏ sót.
      // advBest lấy max nên tổn thất chỉ có thể tăng — nhất quán giữa hai pass.
      if (req.deep) {
        final (List<int> o1, List<int> o2) = rebuildOrders(req.moves, idx);
        final List<int>? deepMove = AiEngine.bestMoveForPlayer(
          board: before,
          n: n,
          w: w,
          player: player,
          timeBudgetMs: req.timeBudgetMsPerPosition,
          randomSeed: req.randomSeed + idx,
          isSliding: n == 3 || n == 4,
          orderP1: o1,
          orderP2: o2,
        );
        if (deepMove != null &&
            deepMove.length == 2 &&
            before[deepMove[0]][deepMove[1]] == 0) {
          final double v = _advAfterMove(before, n, w, player, deepMove[0],
              deepMove[1], hasRemoval, remR, remC);
          if (v > best) {
            second = best;
            best = v;
            bestR = deepMove[0];
            bestC = deepMove[1];
          }
        }
      }

      out.add(MoveProbe(
        index: idx,
        advPlayed: advPlayed,
        advBest: bestR < 0 ? advPlayed : best,
        bestRow: bestR,
        bestCol: bestC,
        gapToSecond: (second <= -2.0) ? 0.0 : (best - second),
        deep: req.deep,
      ));
    }
    return out;
  }

  /// Đặt thử một nước rồi đo lợi thế, sau đó hoàn tác. Không cấp phát bàn cờ
  /// mới nên gọi được hàng nghìn lần mà không tạo áp lực GC.
  static double _advAfterMove(
    List<List<int>> board,
    int n,
    int w,
    int player,
    int r,
    int c,
    bool hasRemoval,
    int remR,
    int remC,
  ) {
    int? savedRemoved;
    if (hasRemoval) {
      savedRemoved = board[remR][remC];
      board[remR][remC] = 0;
    }
    board[r][c] = player;
    final double v = advantage(board, n, w, player);
    board[r][c] = 0;
    if (hasRemoval && savedRemoved != null) {
      board[remR][remC] = savedRemoved;
    }
    return v;
  }
}

// ─── Chấm điểm & phân loại (thuần hàm, dễ test) ───────────────────────────

class AnalysisScoring {
  AnalysisScoring._();

  /// Phân loại một nước từ tổn thất và độ "chỉ có một lựa chọn" của thế cờ.
  static MoveQuality classify({
    required double loss,
    required bool matchedBest,
    required double gapToSecond,
  }) {
    if (loss <= kThresholdBrilliant) {
      final bool onlyMove = matchedBest && gapToSecond >= kBrilliantGapRequired;
      return onlyMove ? MoveQuality.brilliant : MoveQuality.good;
    }
    if (loss <= kThresholdGood) return MoveQuality.good;
    if (loss <= kThresholdInaccuracy) return MoveQuality.inaccuracy;
    if (loss <= kThresholdMistake) return MoveQuality.mistake;
    return MoveQuality.blunder;
  }

  /// Điểm 0..100 cho một nước.
  static double moveScore(double loss) {
    final double capped = loss > kAccuracyLossCap ? kAccuracyLossCap : loss;
    return 100.0 * (1.0 - capped / kAccuracyLossCap);
  }

  /// Độ chính xác của cả ván cho một bên. Trả 0 khi không có nước nào hợp lệ.
  ///
  /// [orderedLosses] phải theo đúng thứ tự thời gian — hàm tự bỏ
  /// [kAccuracyOpeningSkip] nước đầu.
  static int accuracy(List<double> orderedLosses) {
    if (orderedLosses.isEmpty) return 0;
    final List<double> used = orderedLosses.length > kAccuracyOpeningSkip
        ? orderedLosses.sublist(kAccuracyOpeningSkip)
        : orderedLosses;
    if (used.isEmpty) return 0;
    double sum = 0;
    for (final double l in used) {
      sum += moveScore(l);
    }
    return (sum / used.length).round().clamp(0, 100);
  }
}
