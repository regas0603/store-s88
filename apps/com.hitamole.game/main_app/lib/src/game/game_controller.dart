import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/stats_repository.dart';
import '../services/sound_service.dart';
import 'engine/ai_player.dart';
import 'engine/whack_engine.dart';
import 'models/card_icon.dart';
import 'models/game_config.dart';
import 'models/mole_hole.dart';

/// Trạng thái của ván. UI đọc cái này để quyết định cho bấm hay không.
enum GamePhase {
  /// Đang đếm ngược trước khi bắt đầu (hoặc trước lượt người kế tiếp).
  countdown,

  /// Chuột chũi đang trồi lên, người chơi được đập.
  playing,

  /// Người chơi mở menu tạm dừng.
  paused,

  /// Hết ván.
  finished,
}

/// Kết quả cuối ván, đã quy về dạng UI dùng được ngay.
class GameResult {
  final GameMode mode;
  final List<int> scores;
  final List<int> winners;
  final Duration elapsed;

  /// Tổng số cú đập (trúng + hụt + đập nhầm bom).
  final int moves;

  /// Số lần đập nhầm bom của từng người chơi (cùng thứ tự với [scores]).
  /// null = ván không có bom.
  final List<int>? trapsHit;
  final bool isNewRecord;

  const GameResult({
    required this.mode,
    required this.scores,
    required this.winners,
    required this.elapsed,
    required this.moves,
    this.trapsHit,
    required this.isNewRecord,
  });

  GameResult asNewRecord() => GameResult(
        mode: mode,
        scores: scores,
        winners: winners,
        elapsed: elapsed,
        moves: moves,
        trapsHit: trapsHit,
        isNewRecord: true,
      );

  bool get isDraw => winners.length > 1;

  /// Ở chế độ đấu AI, người chơi luôn là index 0.
  bool get humanWon => winners.length == 1 && winners.first == 0;
}

/// Điều phối một ván chơi: nối luật (thuần Dart) với thời gian, âm thanh và UI.
///
/// Engine chạy theo *thời gian ván* lấy từ [_stopwatch]. Tạm dừng = dừng đồng
/// hồ, nên chuột chũi đang ló đầu vẫn giữ nguyên thời gian còn lại khi chơi
/// tiếp — không cần cố "đóng băng" từng timer.
class GameController extends ChangeNotifier {
  /// Nhịp chạy engine + vẽ lại UI. Đủ mịn để phản xạ AI và hạn thụt xuống
  /// không lệch quá một frame rưỡi.
  static const Duration tickInterval = Duration(milliseconds: 40);

  /// Thời gian tối thiểu để chuyền máy cho người kế tiếp ở chế độ 2 người.
  static const int handoffSeconds = 3;

  final GameConfig config;
  final SoundService sound;
  final StatsRepository stats;
  final Random _random;

  late WhackEngine _engine;
  AiPlayer? _ai;

  GamePhase _phase = GamePhase.countdown;
  GamePhase _phaseBeforePause = GamePhase.countdown;
  GameResult? _result;

  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;
  Timer? _countdownTimer;
  DateTime? _countdownEndsAt;
  int _countdownLength = 0;

  /// Đếm ngược hiện tại là để chuyển sang lượt người kế tiếp.
  bool _turnPending = false;

  bool _disposed = false;

  GameController({
    required this.config,
    required this.sound,
    required this.stats,
    Random? random,
  }) : _random = random ?? Random() {
    _buildBoard();
  }

  WhackEngine get engine => _engine;
  GamePhase get phase => _phase;
  GameResult? get result => _result;
  List<MoleHole> get holes => _engine.holes;
  List<int> get scores => _engine.scores;
  int get moves => _engine.taps;
  int get molesLeft => _engine.molesLeft;
  List<int> get trapsHit => _engine.trapsHitBy;

  /// Người đang tới lượt ở chế độ 2 người. Trong lúc đếm ngược chuyền máy, đây
  /// đã là người *sắp* chơi để UI hiện đúng tên.
  int get currentPlayer => _turnPending
      ? (_engine.currentPlayer + 1) % _engine.playerCount
      : _engine.currentPlayer;

  /// Đang đếm ngược để chuyền máy cho người kế tiếp.
  bool get isHandoff => _turnPending;

  Duration get elapsed => _stopwatch.elapsed;

  /// Số giây đếm ngược còn lại (0 nếu không ở giai đoạn đó).
  int get countdownSecondsLeft {
    final endsAt = _countdownEndsAt;
    if (_phase != GamePhase.countdown || endsAt == null) return 0;
    final left = endsAt.difference(DateTime.now()).inMilliseconds;
    return left <= 0 ? 0 : (left / 1000).ceil();
  }

  /// Người chơi có được phép chạm vào bàn lúc này không.
  bool get acceptsInput => _phase == GamePhase.playing;

  void _buildBoard() {
    final size = config.boardSize;
    final category = config.category;
    _engine = WhackEngine(
      holeCount: size.holeCount,
      playerCount: config.mode.playerCount,
      takesTurns: config.mode.takesTurns,
      characters: category == null
          ? const <CardIcon>[]
          : CardIcons.byCategory(category),
      rules: WhackRules(
        moleCount: size.moleCount,
        untilHits: config.mode == GameMode.solo,
        maxActive: size.maxActive,
        upTime: Duration(milliseconds: size.upTimeMs),
        trapChance: config.boardDifficulty.trapChance,
        trapPenalty: config.boardDifficulty.trapPenalty,
      ),
      random: _random,
    )..beginRound(Duration.zero);
    _ai = config.mode == GameMode.vsAi
        ? AiPlayer(difficulty: config.aiDifficulty, random: _random)
        : null;
  }

  /// Bắt đầu ván. Gọi một lần sau khi màn hình game đã dựng xong.
  void start() {
    _startCountdown(config.countdownSeconds);
    notifyListeners();
  }

  void _startCountdown(int seconds) {
    if (seconds <= 0) {
      _beginPlay();
      return;
    }
    _phase = GamePhase.countdown;
    _countdownLength = seconds;
    _countdownEndsAt = DateTime.now().add(Duration(seconds: seconds));
    _countdownTimer?.cancel();
    _countdownTimer = Timer(Duration(seconds: seconds), () {
      if (_disposed) return;
      _beginPlay();
      notifyListeners();
    });
    _startTicker();
  }

  void _beginPlay() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _countdownEndsAt = null;
    if (_turnPending) {
      _turnPending = false;
      _engine.nextTurn(_stopwatch.elapsed);
    }
    _phase = GamePhase.playing;
    if (!_stopwatch.isRunning) _stopwatch.start();
    _startTicker();
  }

  /// Nhịp chạy chung. Cố tình KHÔNG động tới [_stopwatch]: giai đoạn đếm
  /// ngược cần nhịp vẽ nhưng không được tính vào thời gian thành tích.
  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(tickInterval, (_) {
      if (_disposed) return;
      if (_phase == GamePhase.playing) _gameTick();
      notifyListeners();
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _gameTick() {
    final now = _stopwatch.elapsed;
    final tick = _engine.tick(now);

    if (tick.popped.isNotEmpty) {
      sound.play(Sfx.flip);
      final ai = _ai;
      if (ai != null) {
        for (final index in tick.popped) {
          final hole = _engine.holes[index];
          if (hole.isTrap) {
            ai.onTrapPopped(hole, now);
          } else {
            ai.onMolePopped(hole, now);
          }
        }
      }
    }

    final ai = _ai;
    if (ai != null) {
      for (final index in ai.dueWhacks(_engine.holes, now)) {
        switch (_engine.whack(index, player: 1, now: now)) {
          case WhackOutcome.hit:
            sound.play(Sfx.tap);
            break;
          case WhackOutcome.trap:
            // Không rung: máy dính bom chứ không phải người chơi.
            sound.play(Sfx.mismatch);
            break;
          case WhackOutcome.miss:
          case WhackOutcome.rejected:
            break;
        }
      }
    }

    _checkRoundEnd();
  }

  /// Người chơi chạm vào một hang.
  void onHoleTap(int index) {
    if (!acceptsInput) return;

    final now = _stopwatch.elapsed;
    // Đấu AI: người luôn là index 0. Hai người: người đang tới lượt.
    final player = config.mode == GameMode.vsAi ? 0 : _engine.currentPlayer;
    final outcome = _engine.whack(index, player: player, now: now);

    switch (outcome) {
      case WhackOutcome.rejected:
        return;
      case WhackOutcome.hit:
        sound
          ..play(Sfx.match)
          ..successFeedback();
        break;
      case WhackOutcome.miss:
        sound
          ..play(Sfx.mismatch)
          ..tapFeedback();
        break;
      case WhackOutcome.trap:
        sound
          ..play(Sfx.mismatch)
          ..errorFeedback();
        break;
    }

    _checkRoundEnd();
    notifyListeners();
  }

  void _checkRoundEnd() {
    if (_phase != GamePhase.playing || !_engine.roundOver) return;

    if (_engine.isFinished) {
      _finish();
      return;
    }

    // Hết lượt của người này ở chế độ 2 người: dừng đồng hồ, chuyền máy.
    _stopwatch.stop();
    _engine.clearHoles(_stopwatch.elapsed);
    _ai?.reset();
    _turnPending = true;
    sound.successFeedback();
    _startCountdown(max(handoffSeconds, config.countdownSeconds));
  }

  void _finish() {
    _phase = GamePhase.finished;
    _stopwatch.stop();
    _stopTicker();
    _cancelGameTimers();
    _engine.clearHoles(_stopwatch.elapsed);
    sound
      ..play(Sfx.win)
      ..successFeedback();

    final winners = _engine.winners;
    _result = GameResult(
      mode: config.mode,
      scores: _engine.scores,
      winners: winners,
      elapsed: _stopwatch.elapsed,
      moves: _engine.taps,
      trapsHit: config.hasTraps ? _engine.trapsHitBy : null,
      isNewRecord: false,
    );

    unawaited(_submitStats(winners));
  }

  Future<void> _submitStats(List<int> winners) async {
    try {
      switch (config.mode) {
        case GameMode.solo:
          final isRecord = await stats.submitSolo(
            recordKey: config.recordKey,
            elapsedMs: _stopwatch.elapsed.inMilliseconds,
            moves: _engine.taps,
          );
          if (_disposed) return;
          final current = _result;
          if (current != null && isRecord) {
            _result = current.asNewRecord();
            notifyListeners();
          }
          break;
        case GameMode.vsAi:
          final result = winners.length > 1
              ? VsAiResult.draw
              : (winners.first == 0 ? VsAiResult.win : VsAiResult.loss);
          await stats.submitVsAi(result);
          break;
        case GameMode.pvp:
          await stats.submitPvp();
          break;
      }
    } catch (_) {
      // Thống kê hỏng không được phép làm hỏng màn hình kết quả.
    }
  }

  /// Mở menu tạm dừng. Đồng hồ ván dừng lại nên chuột chũi đang ló đầu giữ
  /// nguyên thời gian còn lại; đếm ngược thì chạy lại từ đầu ở [resume].
  void pause() {
    if (_phase == GamePhase.finished || _phase == GamePhase.paused) return;
    _phaseBeforePause = _phase;
    _phase = GamePhase.paused;
    _stopwatch.stop();
    _stopTicker();
    _cancelGameTimers();
    notifyListeners();
  }

  void resume() {
    if (_phase != GamePhase.paused) return;

    if (_phaseBeforePause == GamePhase.countdown) {
      _startCountdown(_countdownLength);
    } else {
      _beginPlay();
    }
    notifyListeners();
  }

  /// Dựng bàn mới và chơi lại với cùng cấu hình.
  void restart() {
    _cancelGameTimers();
    _stopTicker();
    _stopwatch
      ..stop()
      ..reset();
    _result = null;
    _turnPending = false;
    _phase = GamePhase.countdown;
    _countdownEndsAt = null;
    _buildBoard();
    start();
  }

  void _cancelGameTimers() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelGameTimers();
    _stopTicker();
    _stopwatch.stop();
    super.dispose();
  }
}
