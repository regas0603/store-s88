import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/stats_repository.dart';
import '../services/sound_service.dart';
import 'engine/ai_player.dart';
import 'engine/memory_engine.dart';
import 'models/board_card.dart';
import 'models/card_icon.dart';
import 'models/game_config.dart';

/// Trạng thái của ván. UI đọc cái này để quyết định cho bấm hay không.
enum GamePhase {
  /// Đang ngửa toàn bàn cho người chơi nhìn trước.
  peeking,

  /// Chờ người chơi lật lá đầu tiên.
  idle,

  /// Đã lật một lá, chờ lá thứ hai.
  awaitingSecond,

  /// Hai lá đang ngửa, chờ engine xử lý.
  resolving,

  /// Đến lượt AI.
  aiTurn,

  /// Người chơi mở menu tạm dừng.
  paused,

  /// Hết bàn.
  finished,
}

/// Kết quả cuối ván, đã quy về dạng UI dùng được ngay.
class GameResult {
  final GameMode mode;
  final List<int> scores;
  final List<int> winners;
  final Duration elapsed;
  final int moves;
  final bool isNewRecord;

  const GameResult({
    required this.mode,
    required this.scores,
    required this.winners,
    required this.elapsed,
    required this.moves,
    required this.isNewRecord,
  });

  bool get isDraw => winners.length > 1;

  /// Ở chế độ đấu AI, người chơi luôn là index 0.
  bool get humanWon => winners.length == 1 && winners.first == 0;
}

/// Điều phối một ván chơi: nối luật (thuần Dart) với thời gian, âm thanh và UI.
///
/// Mọi độ trễ đều nằm ở đây chứ không nằm trong [MemoryEngine], để luật chơi
/// test được mà không cần giả lập timer.
class GameController extends ChangeNotifier {
  /// Thời gian hai lá ngửa trước khi engine xử lý.
  static const Duration resolveDelay = Duration(milliseconds: 720);

  final GameConfig config;
  final SoundService sound;
  final StatsRepository stats;
  final Random _random;

  late MemoryEngine _engine;
  AiPlayer? _ai;

  GamePhase _phase = GamePhase.idle;
  GamePhase _phaseBeforePause = GamePhase.idle;
  GameResult? _result;

  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;
  Timer? _resolveTimer;
  Timer? _aiTimer;
  Timer? _peekTimer;
  DateTime? _peekEndsAt;

  /// Ô vừa ghép thành công — UI dùng để chạy hiệu ứng nhấp nháy.
  final Set<int> _justMatched = <int>{};

  bool _disposed = false;

  GameController({
    required this.config,
    required this.sound,
    required this.stats,
    Random? random,
  }) : _random = random ?? Random() {
    _buildBoard();
  }

  MemoryEngine get engine => _engine;
  GamePhase get phase => _phase;
  GameResult? get result => _result;
  List<BoardCard> get cards => _engine.cards;
  List<int> get scores => _engine.scores;
  int get currentPlayer => _engine.currentPlayer;
  int get moves => _engine.moves;
  int get pairsLeft => _engine.totalPairs - _engine.matchedPairs;
  Set<int> get justMatched => Set<int>.unmodifiable(_justMatched);

  Duration get elapsed => _stopwatch.elapsed;

  /// Số giây còn lại của giai đoạn xem trước (0 nếu không ở giai đoạn đó).
  int get peekSecondsLeft {
    final endsAt = _peekEndsAt;
    if (_phase != GamePhase.peeking || endsAt == null) return 0;
    final left = endsAt.difference(DateTime.now()).inMilliseconds;
    return left <= 0 ? 0 : (left / 1000).ceil();
  }

  /// Người chơi có được phép chạm vào bàn lúc này không.
  bool get acceptsInput {
    if (_phase != GamePhase.idle && _phase != GamePhase.awaitingSecond) {
      return false;
    }
    // Ở chế độ đấu AI, chỉ người (index 0) mới được chạm.
    if (config.mode == GameMode.vsAi && _engine.currentPlayer != 0) return false;
    return true;
  }

  void _buildBoard() {
    final icons = CardIcons.pick(
      config.boardSize.pairs,
      category: config.category,
      random: _random,
    );
    _engine = MemoryEngine.fromIcons(
      icons,
      playerCount: config.mode.playerCount,
      random: _random,
    );
    _ai = config.mode == GameMode.vsAi
        ? AiPlayer(difficulty: config.aiDifficulty, random: _random)
        : null;
  }

  /// Bắt đầu ván. Gọi một lần sau khi màn hình game đã dựng xong.
  void start() {
    if (config.peekSeconds > 0) {
      _phase = GamePhase.peeking;
      _engine.revealAll();

      final ai = _ai;
      if (ai != null) {
        for (final card in _engine.cards) {
          ai.observe(card, scale: AiPlayer.peekScale);
        }
      }

      _peekEndsAt = DateTime.now().add(Duration(seconds: config.peekSeconds));
      _peekTimer = Timer(Duration(seconds: config.peekSeconds), _endPeek);
      _startTicker();
    } else {
      _beginPlay();
    }
    notifyListeners();
  }

  void _endPeek() {
    if (_disposed) return;
    _engine.hideUnselected();
    _peekEndsAt = null;
    _beginPlay();
    notifyListeners();
  }

  void _beginPlay() {
    _phase = GamePhase.idle;
    if (!_stopwatch.isRunning) _stopwatch.start();
    _startTicker();
  }

  /// Nhịp cập nhật UI. Cố tình KHÔNG động tới [_stopwatch]: giai đoạn xem trước
  /// cần nhịp vẽ để đếm ngược, nhưng không được tính vào thời gian thành tích —
  /// nếu không, bật "xem trước 3 giây" đồng nghĩa với việc mọi kỷ lục tệ đi 3
  /// giây.
  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_disposed) return;
      notifyListeners();
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  /// Người chơi chạm vào một ô.
  void onCardTap(int index) {
    if (!acceptsInput) return;

    final outcome = _engine.flip(index);
    if (outcome == FlipOutcome.rejected) return;

    sound
      ..play(Sfx.flip)
      ..tapFeedback();
    _ai?.observe(_engine.cards[index]);

    if (outcome == FlipOutcome.firstCard) {
      _phase = GamePhase.awaitingSecond;
    } else {
      _phase = GamePhase.resolving;
      _scheduleResolve();
    }
    notifyListeners();
  }

  void _scheduleResolve() {
    _resolveTimer?.cancel();
    _resolveTimer = Timer(resolveDelay, _applyResolve);
  }

  void _applyResolve() {
    if (_disposed || !_engine.awaitingResolve) return;

    final outcome = _engine.resolve();
    _justMatched.clear();

    if (outcome.matched) {
      _justMatched
        ..add(outcome.firstIndex)
        ..add(outcome.secondIndex);
      _ai?.forgetMatched(<int>[outcome.firstIndex, outcome.secondIndex]);
      sound
        ..play(Sfx.match)
        ..successFeedback();
    } else {
      sound.play(Sfx.mismatch);
    }

    if (outcome.gameFinished) {
      _finish();
    } else if (config.mode == GameMode.vsAi && _engine.currentPlayer == 1) {
      _startAiTurn();
    } else {
      _phase = GamePhase.idle;
    }
    notifyListeners();
  }

  void _startAiTurn() {
    final ai = _ai;
    if (ai == null) return;

    _phase = GamePhase.aiTurn;
    ai.decay();

    final delay = config.aiDifficulty.thinkingDelay;
    _aiTimer?.cancel();
    _aiTimer = Timer(delay, () {
      if (_disposed || _phase != GamePhase.aiTurn) return;

      final firstIndex = ai.chooseFirst(_engine.cards);
      if (_engine.flip(firstIndex) == FlipOutcome.rejected) return;
      sound.play(Sfx.flip);
      ai.observe(_engine.cards[firstIndex]);
      notifyListeners();

      _aiTimer = Timer(delay, () {
        if (_disposed || _phase != GamePhase.aiTurn) return;

        final first = _engine.cards[firstIndex];
        final secondIndex = ai.chooseSecond(_engine.cards, first);
        if (_engine.flip(secondIndex) == FlipOutcome.rejected) return;
        sound.play(Sfx.flip);
        ai.observe(_engine.cards[secondIndex]);

        _phase = GamePhase.resolving;
        notifyListeners();
        _scheduleResolve();
      });
    });
  }

  void _finish() {
    _phase = GamePhase.finished;
    _stopwatch.stop();
    _stopTicker();
    _cancelGameTimers();
    sound
      ..play(Sfx.win)
      ..successFeedback();

    final winners = _engine.winners;
    _result = GameResult(
      mode: config.mode,
      scores: _engine.scores,
      winners: winners,
      elapsed: _stopwatch.elapsed,
      moves: _engine.moves,
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
            moves: _engine.moves,
          );
          if (_disposed) return;
          final current = _result;
          if (current != null && isRecord) {
            _result = GameResult(
              mode: current.mode,
              scores: current.scores,
              winners: current.winners,
              elapsed: current.elapsed,
              moves: current.moves,
              isNewRecord: true,
            );
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

  /// Mở menu tạm dừng. Mọi timer đang chạy bị huỷ và sẽ được dựng lại ở
  /// [resume] dựa trên trạng thái engine — an toàn hơn là cố "đóng băng" timer.
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

    if (_phaseBeforePause == GamePhase.peeking) {
      // Chơi lại giai đoạn xem trước từ đầu cho công bằng.
      _phase = GamePhase.peeking;
      _peekEndsAt = DateTime.now().add(Duration(seconds: config.peekSeconds));
      _peekTimer = Timer(Duration(seconds: config.peekSeconds), _endPeek);
    } else if (_engine.awaitingResolve) {
      _phase = GamePhase.resolving;
      _scheduleResolve();
    } else if (config.mode == GameMode.vsAi && _engine.currentPlayer == 1) {
      _startAiTurn();
    } else {
      _phase = _engine.selection.isEmpty
          ? GamePhase.idle
          : GamePhase.awaitingSecond;
    }

    if (_phase != GamePhase.peeking) _stopwatch.start();
    _startTicker();
    notifyListeners();
  }

  /// Xáo bàn mới và chơi lại với cùng cấu hình.
  void restart() {
    _cancelGameTimers();
    _stopTicker();
    _stopwatch
      ..stop()
      ..reset();
    _justMatched.clear();
    _result = null;
    _phase = GamePhase.idle;
    _peekEndsAt = null;
    _buildBoard();
    start();
  }

  void _cancelGameTimers() {
    _resolveTimer?.cancel();
    _resolveTimer = null;
    _aiTimer?.cancel();
    _aiTimer = null;
    _peekTimer?.cancel();
    _peekTimer = null;
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
