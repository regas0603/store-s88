import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:isolate_manager/isolate_manager.dart';

import '../game/analysis_engine.dart';
import 'game_analysis.dart';
import 'game_history.dart';

/// Giai đoạn của quá trình phân tích — UI đổi câu chú thích theo giai đoạn.
enum AnalysisPhase { shallow, deep, finishing }

class AnalysisProgress {
  /// 0.0 .. 1.0
  final double value;
  final AnalysisPhase phase;

  /// Số thứ tự nước đang xét và tổng số nước, để hiện "nước 24 / 38".
  final int current;
  final int total;

  const AnalysisProgress({
    required this.value,
    required this.phase,
    required this.current,
    required this.total,
  });

  static const AnalysisProgress idle = AnalysisProgress(
    value: 0,
    phase: AnalysisPhase.shallow,
    current: 0,
    total: 0,
  );
}

/// Điều phối việc phân tích một ván đấu.
///
/// **Isolate riêng theo phiên.** Tuyệt đối không dùng chung pool isolate của
/// gameplay trong `caro_game.dart`: pool đó chạy `concurrent: 1`, nếu bị chiếm
/// dụng để phân tích thì nước đi của AI trong ván mới sẽ đứng chờ phía sau.
///
/// **Chia lô để có tiến độ thật.** Thay vì một lần tính dài thượt rồi mới trả
/// kết quả, công việc được chẻ thành nhiều lô nhỏ; mỗi lô là một lần
/// `compute`. Nhờ vậy có tiến độ thật, huỷ được giữa chừng, và không cần đến
/// cơ chế streaming phức tạp của isolate_manager.
class GameAnalysisService {
  GameAnalysisService();

  /// Kích thước lô ở pass quét nông. Nhỏ thì tiến độ mượt, lớn thì ít overhead
  /// truyền dữ liệu. 6 là điểm cân bằng đo được trên bàn 15x15.
  static const int _shallowBatchSize = 6;

  final ValueNotifier<AnalysisProgress> progress =
      ValueNotifier<AnalysisProgress>(AnalysisProgress.idle);

  IsolateManager<List<double>, ProbeRequest>? _isolate;
  int _requestId = 0;
  bool _disposed = false;

  bool get isRunning => _running;
  bool _running = false;

  /// Huỷ lần chạy hiện tại. Kết quả đang bay về sẽ bị bỏ qua nhờ [_requestId].
  void cancel() {
    _requestId++;
    _running = false;
    _stopIsolate();
  }

  void dispose() {
    _disposed = true;
    _requestId++;
    _running = false;
    _stopIsolate();
    progress.dispose();
  }

  void _stopIsolate() {
    final IsolateManager<List<double>, ProbeRequest>? m = _isolate;
    _isolate = null;
    if (m == null) return;
    // Không await — dừng isolate là việc dọn dẹp, không được chặn UI.
    unawaited(() async {
      try {
        await m.stop();
      } catch (_) {
        // Isolate có thể đã chết; nuốt lỗi.
      }
    }());
  }

  Future<IsolateManager<List<double>, ProbeRequest>?> _ensureIsolate() async {
    if (_isolate != null) return _isolate;
    try {
      final IsolateManager<List<double>, ProbeRequest> m =
          IsolateManager<List<double>, ProbeRequest>.create(
        analysisProbeWorker,
        concurrent: 1,
      );
      await m.start();
      if (_disposed) {
        unawaited(m.stop());
        return null;
      }
      _isolate = m;
      return m;
    } catch (_) {
      // Spawn thất bại -> caller tự chạy đồng bộ ở main isolate.
      return null;
    }
  }

  /// Phân tích [record]. Trả null khi bị huỷ, ván quá ngắn, hoặc gặp lỗi.
  Future<GameAnalysis?> analyze(GameRecord record) async {
    if (record.moves.length < kMinMovesToAnalyze) return null;

    _requestId++;
    final int reqId = _requestId;
    _running = true;

    final Stopwatch clock = Stopwatch()..start();
    final int n = record.boardSide;
    final int w = record.winLength;

    final List<AnalysisMove> moves = record.moves
        .map((MoveLog m) => AnalysisMove(
              row: m.row,
              col: m.col,
              player: m.player,
              removedRow: m.removedRow ?? -1,
              removedCol: m.removedCol ?? -1,
            ))
        .toList();

    // Nước nào được chấm? vs AI: chỉ nước của người (X). PvP: cả hai bên.
    final bool vsAI = record.mode == GameMode.vsAI;
    final List<int> scored = <int>[];
    for (int i = 0; i < moves.length; i++) {
      if (vsAI && moves[i].player != 1) continue;
      scored.add(i);
    }
    if (scored.isEmpty) {
      _running = false;
      return null;
    }

    // Seed cố định theo record -> phân tích lại cùng một ván luôn ra cùng kết
    // quả (yêu cầu tất định của US-005-4).
    final int seed = record.id.hashCode & 0x3fffffff;

    final int totalUnits = scored.length + kDeepPositionCount;
    int doneUnits = 0;
    void report(AnalysisPhase phase, int current) {
      if (_disposed) return;
      progress.value = AnalysisProgress(
        value: (doneUnits / totalUnits).clamp(0.0, 1.0),
        phase: phase,
        current: current,
        total: scored.length,
      );
    }

    report(AnalysisPhase.shallow, 0);

    final IsolateManager<List<double>, ProbeRequest>? iso =
        await _ensureIsolate();
    if (reqId != _requestId) return null;

    Future<List<MoveProbe>> run(ProbeRequest req) async {
      if (iso == null) return AnalysisEngine.probe(req);
      try {
        return MoveProbe.decodeAll(await iso.compute(req));
      } catch (_) {
        // Isolate chết giữa chừng -> chạy đồng bộ để không mất cả ván phân
        // tích. Chấp nhận một nhịp khựng nhỏ thay vì hỏng toàn bộ.
        return AnalysisEngine.probe(req);
      }
    }

    // ── Pass 1: quét nông toàn ván ─────────────────────────────────────────
    final Map<int, MoveProbe> probes = <int, MoveProbe>{};
    for (int i = 0; i < scored.length; i += _shallowBatchSize) {
      if (reqId != _requestId) return null;
      final List<int> batch =
          scored.sublist(i, (i + _shallowBatchSize).clamp(0, scored.length));
      final List<MoveProbe> res = await run(ProbeRequest(
        moves: moves,
        boardSide: n,
        winLength: w,
        indexes: batch,
        deep: false,
        timeBudgetMsPerPosition: 0,
        randomSeed: seed,
      ));
      if (reqId != _requestId) return null;
      for (final MoveProbe p in res) {
        probes[p.index] = p;
      }
      doneUnits += batch.length;
      report(AnalysisPhase.shallow, i + batch.length);
    }

    // ── Chọn thế cờ để đào sâu: những nước tổn thất lớn nhất ───────────────
    final List<int> ranked = probes.keys.toList()
      ..sort((int a, int b) => probes[b]!.loss.compareTo(probes[a]!.loss));
    final List<int> deepTargets = ranked.take(kDeepPositionCount).toList();

    bool isShallow = false;

    // ── Pass 2: đào sâu từng thế một ───────────────────────────────────────
    for (int i = 0; i < deepTargets.length; i++) {
      if (reqId != _requestId) return null;
      if (clock.elapsedMilliseconds >= kTotalBudgetMs) {
        // Hết ngân sách -> dừng, giữ kết quả pass nông và đánh dấu degrade.
        isShallow = true;
        break;
      }
      final List<MoveProbe> res = await run(ProbeRequest(
        moves: moves,
        boardSide: n,
        winLength: w,
        indexes: <int>[deepTargets[i]],
        deep: true,
        timeBudgetMsPerPosition: kDeepBudgetMsPerPosition,
        randomSeed: seed,
      ));
      if (reqId != _requestId) return null;
      for (final MoveProbe p in res) {
        probes[p.index] = p;
      }
      doneUnits++;
      report(AnalysisPhase.deep, scored.length);
    }
    doneUnits = totalUnits;
    report(AnalysisPhase.finishing, scored.length);

    final GameAnalysis analysis = buildAnalysis(
      moves: moves,
      probes: probes,
      scored: scored,
      isShallow: isShallow,
    );

    _running = false;
    _stopIsolate();
    return analysis;
  }

  /// Ghép kết quả chấm điểm thành [GameAnalysis].
  ///
  /// Tách riêng thành hàm tĩnh để unit test được mà không cần isolate.
  @visibleForTesting
  static GameAnalysis buildAnalysis({
    required List<AnalysisMove> moves,
    required Map<int, MoveProbe> probes,
    required List<int> scored,
    required bool isShallow,
  }) {
    final List<MoveAnalysis> out = <MoveAnalysis>[];
    final List<double> lossesX = <double>[];
    final List<double> lossesO = <double>[];

    double prevAdvX = 0;
    double worstSwing = 0;
    int turningPoint = -1;

    for (int i = 0; i < moves.length; i++) {
      final AnalysisMove m = moves[i];
      final MoveProbe? p = probes[i];

      if (p == null) {
        // Nước không được chấm (nước của máy). Vẫn cần một giá trị lợi thế để
        // đường biểu đồ liền mạch -> giữ nguyên mức trước đó.
        out.add(MoveAnalysis(
          advantageMilli: (prevAdvX * 1000).round(),
          lossMilli: 0,
          quality: MoveQuality.good,
        ));
        continue;
      }

      // advPlayed theo góc nhìn người đi -> quy về góc nhìn X cho biểu đồ.
      final double advX = m.player == 1 ? p.advPlayed : -p.advPlayed;

      final double loss = p.loss;
      final bool matchedBest = p.bestRow == m.row && p.bestCol == m.col;
      final MoveQuality q = AnalysisScoring.classify(
        loss: loss,
        matchedBest: matchedBest,
        gapToSecond: p.gapToSecond,
      );

      final bool showBetter = q.isBad && p.bestRow >= 0 && !matchedBest;

      out.add(MoveAnalysis(
        advantageMilli: (advX * 1000).round(),
        lossMilli: (loss * 1000).round(),
        quality: q,
        betterRow: showBetter ? p.bestRow : null,
        betterCol: showBetter ? p.bestCol : null,
        shallow: !p.deep && isShallow,
      ));

      if (m.player == 1) {
        lossesX.add(loss);
      } else {
        lossesO.add(loss);
      }

      // Bước ngoặt = nước làm lợi thế X đổi nhiều nhất theo hướng bất lợi cho
      // người vừa đi.
      final double swing =
          m.player == 1 ? (prevAdvX - advX) : (advX - prevAdvX);
      if (swing > worstSwing) {
        worstSwing = swing;
        turningPoint = i;
      }
      prevAdvX = advX;
    }

    return GameAnalysis(
      moveAnalyses: out,
      scoredIndexes: scored,
      accuracyX: AnalysisScoring.accuracy(lossesX),
      accuracyO: AnalysisScoring.accuracy(lossesO),
      turningPointIndex: turningPoint,
      isShallow: isShallow,
      analyzedAt: DateTime.now(),
    );
  }
}
