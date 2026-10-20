import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/stats_repository.dart';
import '../services/sound_service.dart';
import 'engine/guess_engine.dart';
import 'models/game_config.dart';
import 'models/guess.dart';

/// Trạng thái của ván. UI đọc cái này để quyết định hiện bàn phím nào.
enum GamePhase {
  /// Chế độ 2 người: một bên đang nhập số bí mật cho bên kia.
  settingSecret,

  /// Chế độ 2 người: đã nhập xong, đang đếm ngược để chuyền máy.
  handoff,

  /// Người chơi đang đoán.
  playing,

  /// Sinh tồn: vừa qua một vòng, đang nghỉ một nhịp trước vòng kế.
  roundCleared,

  /// Người chơi mở menu tạm dừng.
  paused,

  /// Hết ván.
  finished,
}

/// Tóm tắt một lượt đoán, đã quy về dạng UI dùng được ngay.
class RoundSummary {
  /// Người đoán.
  final int player;

  /// Người đặt số bí mật (chơi đơn thì là máy — null).
  final int? setter;

  final int secret;
  final int guessesUsed;
  final bool solved;
  final Duration elapsed;

  const RoundSummary({
    required this.player,
    required this.setter,
    required this.secret,
    required this.guessesUsed,
    required this.solved,
    required this.elapsed,
  });
}

/// Kết quả cuối ván.
class GameResult {
  final GameMode mode;

  /// Một phần tử cho mỗi người đoán, theo đúng chỉ số người chơi.
  final List<RoundSummary> rounds;

  final List<int> winners;

  /// Tổng thời gian cả ván.
  final Duration elapsed;

  final bool isNewRecord;

  /// Sinh tồn: số vòng đoán ra được. 0 ở các chế độ khác.
  final int survivedRounds;

  /// Sinh tồn: kỷ lục chuỗi trước ván này, để bảng kết quả so sánh. null nếu
  /// chưa từng có hoặc không phải chế độ sinh tồn.
  final int? previousBestStreak;

  const GameResult({
    required this.mode,
    required this.rounds,
    required this.winners,
    required this.elapsed,
    required this.isNewRecord,
    this.survivedRounds = 0,
    this.previousBestStreak,
  });

  GameResult asNewRecord() => GameResult(
        mode: mode,
        rounds: rounds,
        winners: winners,
        elapsed: elapsed,
        isNewRecord: true,
        survivedRounds: survivedRounds,
        previousBestStreak: previousBestStreak,
      );

  bool get isDraw => winners.length > 1;

  /// Chơi đơn: có đoán ra không.
  bool get soloSolved => rounds.isNotEmpty && rounds.first.solved;
}

/// Điều phối một ván chơi: nối luật (thuần Dart) với thời gian, âm thanh và UI.
///
/// Chế độ 2 người đi theo đúng thứ tự "chọn xong đoán":
///   1. Người 1 nhập số bí mật  →  2. chuyền máy  →  3. Người 2 đoán
///   4. Người 2 nhập số bí mật  →  5. chuyền máy  →  6. Người 1 đoán
/// Ai đoán ra bằng ít lượt hơn thì thắng. Hai lượt đối xứng nhau nên không bên
/// nào bị thiệt vì chơi trước.
class GameController extends ChangeNotifier {
  /// Nhịp vẽ lại đồng hồ và số giây chuyền máy.
  static const Duration tickInterval = Duration(milliseconds: 200);

  /// Nhịp nghỉ giữa hai vòng Sinh tồn. Đủ để đọc "qua vòng rồi" mà không làm
  /// đứt mạch; người chơi sốt ruột bấm nút là đi tiếp ngay.
  static const Duration roundBreak = Duration(milliseconds: 1400);

  final GameConfig config;
  final SoundService sound;
  final StatsRepository stats;
  final Random _random;

  late GuessEngine _engine;

  GamePhase _phase = GamePhase.playing;
  GamePhase _phaseBeforePause = GamePhase.playing;
  GameResult? _result;

  /// Lượt thứ mấy của ván đấu (0 hoặc 1). Chơi đơn luôn là 0.
  int _leg = 0;

  /// Đồng hồ của *lượt hiện tại*. Thành tích chơi đơn và tie-break của chế độ
  /// đấu đều tính theo đây, nên lúc nhập số bí mật và chuyền máy phải dừng.
  final Stopwatch _stopwatch = Stopwatch();

  /// Tổng thời gian đã tính xong của các lượt trước.
  Duration _completedTime = Duration.zero;

  Timer? _ticker;
  Timer? _handoffTimer;
  DateTime? _handoffEndsAt;

  /// Sinh tồn: vòng đang chơi, đếm từ 1.
  int _survivalRound = 1;

  /// Sinh tồn: số vòng đã đoán ra.
  int _survived = 0;

  Timer? _roundBreakTimer;

  /// Phản hồi cho lần nhập gần nhất ("ngoài khoảng", "đã đoán rồi"), hiện một
  /// nhịp rồi tự mất khi người chơi nhập tiếp.
  GuessOutcome? _lastRejection;

  bool _disposed = false;

  GameController({
    required this.config,
    required this.sound,
    required this.stats,
    Random? random,
  }) : _random = random ?? Random() {
    _buildGame();
  }

  GuessEngine get engine => _engine;
  GamePhase get phase => _phase;
  GameResult? get result => _result;

  /// Lượt đoán đang diễn ra.
  GuessRound get round => _engine.currentRound;

  List<Guess> get history => _engine.currentRound.history;

  int get guessesUsed => _engine.currentRound.guessesUsed;
  int get guessesLeft => _engine.currentRound.guessesLeft;

  int get lowBound => _engine.currentRound.lowBound;
  int get highBound => _engine.currentRound.highBound;

  Guess? get lastGuess => _engine.currentRound.lastGuess;
  GuessOutcome? get lastRejection => _lastRejection;

  /// Người đang đoán.
  int get guesser => _engine.currentPlayer;

  /// Người đang đặt số bí mật (chỉ có nghĩa ở [GamePhase.settingSecret]).
  int get setter => (_engine.currentPlayer + 1) % _engine.playerCount;

  /// Tổng thời gian đã chơi của cả ván.
  Duration get elapsed => _completedTime + _stopwatch.elapsed;

  /// Thời gian của riêng lượt đang chơi.
  Duration get legElapsed => _stopwatch.elapsed;

  /// Số giây còn lại của màn chuyền máy.
  int get handoffSecondsLeft {
    final endsAt = _handoffEndsAt;
    if (_phase != GamePhase.handoff || endsAt == null) return 0;
    final left = endsAt.difference(DateTime.now()).inMilliseconds;
    return left <= 0 ? 0 : (left / 1000).ceil();
  }

  bool get acceptsGuess => _phase == GamePhase.playing;

  /// Sinh tồn: vòng đang chơi, đếm từ 1. Chế độ khác luôn là 1.
  int get survivalRound => _survivalRound;

  /// Sinh tồn: số vòng đã đoán ra tính tới lúc này.
  int get survivedRounds => _survived;

  /// Ngân sách lượt của vòng đang chơi. Ở Sinh tồn con số này giảm dần, nên UI
  /// phải đọc đây chứ không phải `config.maxGuesses`.
  int get guessBudget => config.mode.isSurvival
      ? config.survivalGuessesFor(_survivalRound)
      : config.maxGuesses;

  void _buildGame() {
    _engine = GuessEngine(
      min: config.range.min,
      max: config.range.max,
      maxGuesses: guessBudget,
      playerCount: config.mode.playerCount,
      showHeat: config.showsHeat,
      random: _random,
    );
  }

  /// Bắt đầu ván. Gọi một lần sau khi màn hình game đã dựng xong.
  void start() {
    _leg = 0;
    if (config.mode != GameMode.duel) {
      _engine
        ..moveToPlayer(0)
        ..rollSecretFor(0);
      _beginPlay();
    } else {
      // Lượt 1: Người 1 (index 0) đặt số, Người 2 (index 1) đoán.
      _engine.moveToPlayer(1);
      _phase = GamePhase.settingSecret;
      _startTicker();
    }
    notifyListeners();
  }

  /// Người đang đặt số xác nhận số bí mật. Trả về false nếu số ngoài khoảng.
  bool confirmSecret(int secret) {
    if (_phase != GamePhase.settingSecret) return false;
    if (!_engine.setSecretFor(_engine.currentPlayer, secret)) return false;

    sound
      ..play(Sfx.flip)
      ..tapFeedback();
    _startHandoff();
    notifyListeners();
    return true;
  }

  void _startHandoff() {
    final seconds = max(1, config.handoffSeconds);
    _phase = GamePhase.handoff;
    _handoffEndsAt = DateTime.now().add(Duration(seconds: seconds));
    _handoffTimer?.cancel();
    _handoffTimer = Timer(Duration(seconds: seconds), () {
      if (_disposed) return;
      _beginPlay();
      notifyListeners();
    });
    _startTicker();
  }

  /// Bỏ qua phần còn lại của đếm ngược chuyền máy.
  void skipHandoff() {
    if (_phase != GamePhase.handoff) return;
    _beginPlay();
    notifyListeners();
  }

  void _beginPlay() {
    _handoffTimer?.cancel();
    _handoffTimer = null;
    _handoffEndsAt = null;
    _lastRejection = null;
    _phase = GamePhase.playing;
    _stopwatch
      ..reset()
      ..start();
    _startTicker();
  }

  /// Nhịp chạy chỉ để vẽ lại đồng hồ và bộ đếm chuyền máy — không có luật nào
  /// chạy ở đây, nên 200ms là đủ mịn mà gần như không tốn pin.
  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(tickInterval, (_) {
      if (_disposed) return;
      notifyListeners();
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  /// Người chơi gửi một con số.
  GuessOutcome submitGuess(int value) {
    if (!acceptsGuess) return GuessOutcome.rejected;

    final outcome = _engine.submit(value);
    switch (outcome) {
      case GuessOutcome.rejected:
        return outcome;
      case GuessOutcome.outOfRange:
      case GuessOutcome.duplicate:
        _lastRejection = outcome;
        sound
          ..play(Sfx.mismatch)
          ..errorFeedback();
        notifyListeners();
        return outcome;
      case GuessOutcome.wrong:
        _lastRejection = null;
        sound
          ..play(Sfx.flip)
          ..tapFeedback();
        break;
      case GuessOutcome.exhausted:
        _lastRejection = null;
        sound
          ..play(Sfx.mismatch)
          ..errorFeedback();
        break;
      case GuessOutcome.correct:
        _lastRejection = null;
        sound
          ..play(Sfx.match)
          ..successFeedback();
        break;
    }

    if (_engine.currentRound.isOver) {
      _closeLeg();
    } else {
      notifyListeners();
    }
    return outcome;
  }

  /// Khoá lượt hiện tại rồi đi tiếp: sang lượt sau hoặc kết thúc ván.
  void _closeLeg() {
    _stopwatch.stop();
    _engine.currentRound.elapsed = _stopwatch.elapsed;
    _completedTime += _stopwatch.elapsed;

    if (config.mode.isSurvival) {
      if (_engine.currentRound.solved) {
        _survived++;
        _enterRoundBreak();
      } else {
        _finish();
      }
      return;
    }

    final isLastLeg = config.mode == GameMode.solo || _leg >= 1;
    if (isLastLeg) {
      _finish();
      return;
    }

    // Lượt 2: đổi vai — người vừa đoán giờ đặt số cho người kia.
    _leg = 1;
    _engine.moveToPlayer(0);
    _phase = GamePhase.settingSecret;
    _lastRejection = null;
    _startTicker();
    notifyListeners();
  }

  /// Sinh tồn: nghỉ một nhịp giữa hai vòng.
  void _enterRoundBreak() {
    _phase = GamePhase.roundCleared;
    _roundBreakTimer?.cancel();
    _roundBreakTimer = Timer(roundBreak, () {
      if (_disposed) return;
      _startNextSurvivalRound();
      notifyListeners();
    });
    _startTicker();
    notifyListeners();
  }

  /// Bỏ qua phần còn lại của nhịp nghỉ giữa hai vòng Sinh tồn.
  void skipRoundBreak() {
    if (_phase != GamePhase.roundCleared) return;
    _startNextSurvivalRound();
    notifyListeners();
  }

  void _startNextSurvivalRound() {
    _roundBreakTimer?.cancel();
    _roundBreakTimer = null;
    _survivalRound++;
    // Engine mới cho mỗi vòng: số bí mật mới, ngân sách lượt mới, lịch sử
    // đoán sạch. Rẻ hơn và ít chỗ sai hơn là reset tại chỗ.
    _buildGame();
    _engine
      ..moveToPlayer(0)
      ..rollSecretFor(0);
    _beginPlay();
  }

  void _finish() {
    _phase = GamePhase.finished;
    _stopwatch.stop();
    _stopTicker();
    _cancelGameTimers();
    // Sinh tồn kết thúc là do THUA — tiếng thắng ở đây nghe trêu ngươi.
    if (config.mode.isSurvival) {
      sound
        ..play(Sfx.mismatch)
        ..errorFeedback();
    } else {
      sound
        ..play(Sfx.win)
        ..successFeedback();
    }

    final winners = _engine.winners;
    _result = GameResult(
      mode: config.mode,
      rounds: <RoundSummary>[
        for (var i = 0; i < _engine.playerCount; i++)
          RoundSummary(
            player: i,
            setter: config.mode.isDuel ? (i + 1) % _engine.playerCount : null,
            secret: _engine.roundOf(i).secret ?? 0,
            guessesUsed: _engine.roundOf(i).guessesUsed,
            solved: _engine.roundOf(i).solved,
            elapsed: _engine.roundOf(i).elapsed,
          ),
      ],
      winners: winners,
      elapsed: _completedTime,
      isNewRecord: false,
      survivedRounds: _survived,
      previousBestStreak: config.mode.isSurvival
          ? stats.recordFor(config.recordKey).bestStreak
          : null,
    );
    notifyListeners();

    unawaited(_submitStats());
  }

  Future<void> _submitStats() async {
    try {
      switch (config.mode) {
        case GameMode.solo:
          final solo = _engine.roundOf(0);
          // Chỉ ghi kỷ lục khi đoán ra: một ván bí mà tính "ít lượt nhất" thì
          // bảng kỷ lục sẽ toàn những ván thua.
          if (!solo.solved) {
            await stats.registerUnsolved();
            return;
          }
          final isRecord = await stats.submitSolo(
            recordKey: config.recordKey,
            elapsedMs: solo.elapsed.inMilliseconds,
            guesses: solo.guessesUsed,
          );
          if (_disposed) return;
          final current = _result;
          if (current != null && isRecord) {
            _result = current.asNewRecord();
            notifyListeners();
          }
        case GameMode.survival:
          final isRecord = await stats.submitSurvival(
            recordKey: config.recordKey,
            streak: _survived,
          );
          if (_disposed) return;
          final current = _result;
          // Chuỗi 0 vòng không đáng gọi là kỷ lục, kể cả khi đó là lần đầu.
          if (current != null && isRecord && _survived > 0) {
            _result = current.asNewRecord();
            notifyListeners();
          }
        case GameMode.duel:
          await stats.submitDuel();
      }
    } catch (_) {
      // Thống kê hỏng không được phép làm hỏng màn hình kết quả.
    }
  }

  /// Mở menu tạm dừng. Đồng hồ lượt dừng theo, nên tạm dừng không ăn gian được
  /// thành tích về thời gian.
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

    switch (_phaseBeforePause) {
      case GamePhase.handoff:
        _startHandoff();
      case GamePhase.playing:
        _phase = GamePhase.playing;
        _stopwatch.start();
        _startTicker();
      case GamePhase.settingSecret:
        _phase = GamePhase.settingSecret;
        _startTicker();
      case GamePhase.roundCleared:
        // Nhịp nghỉ đếm lại từ đầu: hẹn giờ cũ đã bị pause() huỷ, và người
        // chơi vừa quay lại cũng cần một nhịp để định thần.
        _enterRoundBreak();
      case GamePhase.paused:
      case GamePhase.finished:
        _phase = _phaseBeforePause;
    }
    notifyListeners();
  }

  /// Chơi lại với cùng cấu hình, số bí mật mới.
  void restart() {
    _cancelGameTimers();
    _stopTicker();
    _stopwatch
      ..stop()
      ..reset();
    _completedTime = Duration.zero;
    _result = null;
    _lastRejection = null;
    _survivalRound = 1;
    _survived = 0;
    _buildGame();
    start();
  }

  void _cancelGameTimers() {
    _handoffTimer?.cancel();
    _handoffTimer = null;
    _roundBreakTimer?.cancel();
    _roundBreakTimer = null;
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
