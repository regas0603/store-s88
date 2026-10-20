import 'dart:async' as async;
import 'dart:math';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:isolate_manager/isolate_manager.dart';
import '../core/achievements.dart';
import '../core/app_settings.dart';
import '../core/audio_service.dart';
import '../core/game_history.dart';
import '../core/game_snapshot.dart';
import 'board_component.dart';
import 'ai_engine.dart';

// ─── Shared AI isolate pool ───────────────────────────────────────────────────
//
// Một isolate duy nhất được giữ ấm xuyên suốt vòng đời app, tránh cold-start
// ~100-200ms mỗi lần AI ra nước đi. Khởi tạo lazily ở nước đi AI đầu tiên.

IsolateManager<List<int>?, AiMoveRequest>? _pooledAiIsolate;
Future<IsolateManager<List<int>?, AiMoveRequest>>? _aiIsolateFuture;

Future<IsolateManager<List<int>?, AiMoveRequest>> _ensureAiIsolate() {
  final pooled = _pooledAiIsolate;
  if (pooled != null) return Future<IsolateManager<List<int>?, AiMoveRequest>>.value(pooled);
  return _aiIsolateFuture ??= () async {
    final IsolateManager<List<int>?, AiMoveRequest> manager =
        IsolateManager<List<int>?, AiMoveRequest>.create(
      aiPickMoveWorker,
      concurrent: 1,
    );
    await manager.start();
    _pooledAiIsolate = manager;
    return manager;
  }();
}

// ─── Enums & State ────────────────────────────────────────────────────────────

enum GameStatus { playing, xWins, oWins, draw, timeout }

class GameState {
  final int currentPlayer;
  final GameStatus status;
  final int timeLeft;
  final bool canUndo;

  const GameState({
    required this.currentPlayer,
    required this.status,
    required this.timeLeft,
    required this.canUndo,
  });
}

// ─── Move record for undo ─────────────────────────────────────────────────────

class MoveRecord {
  final int row;
  final int col;
  final int player;
  final int? removedRow;
  final int? removedCol;

  MoveRecord(
    this.row,
    this.col,
    this.player, {
    this.removedRow,
    this.removedCol,
  });
}

// ─── CaroGame ─────────────────────────────────────────────────────────────────

class CaroGame extends FlameGame with TapCallbacks {
  final bool vsAI;
  final int boardSize;
  final int winLength;

  late List<List<int>> board;
  int _currentPlayer = 1;
  GameStatus _status = GameStatus.playing;

  // Scores
  int xScore = 0;
  int oScore = 0;
  int draws = 0;

  // Move history for undo
  final List<MoveRecord> _moves = [];
  final Map<int, List<Point<int>>> _pieceOrder = <int, List<Point<int>>>{
    1: <Point<int>>[],
    2: <Point<int>>[],
  };

  // Winning cells
  List<Point<int>> winningCells = [];

  // Timer
  int _timeLeft = 0;
  async.Timer? _timer;
  DateTime? _gameStartTime;
  int _totalMoves = 0;
  final Random _aiRandom = Random();
  int _aiRequestId = 0;

  // Dùng để tránh gửi notify trùng trong cùng microtask
  bool _pendingNotify = false;

  // Notifier — Flutter UI lắng nghe state từ đây
  final ValueNotifier<GameState> gameStateNotifier = ValueNotifier(
    const GameState(
      currentPlayer: 1,
      status: GameStatus.playing,
      timeLeft: 0,
      canUndo: false,
    ),
  );

  late BoardComponent _boardComponent;

  /// Constructor bình thường dùng [AppSettings.boardSizePreset].
  /// Khi [resumeBoardSide]/[resumeWinLength] được cung cấp (từ snapshot US-003),
  /// dùng giá trị đó thay vì preset hiện tại — tránh lỗi khi user đổi preset
  /// trong Settings giữa lúc pause và resume.
  CaroGame({
    required this.vsAI,
    int? resumeBoardSide,
    int? resumeWinLength,
  })  : boardSize = resumeBoardSide ?? AppSettings().boardSizePreset.side,
        winLength = resumeWinLength ?? AppSettings().boardSizePreset.winLength;

  int get turnTimeSecs => AppSettings().turnTimeSecs;

  @override
  Color backgroundColor() => const Color(0xFF0f0f1a);

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  Future<void> onLoad() async {
    camera.viewfinder.anchor = Anchor.topLeft;
    _boardComponent = BoardComponent(game: this);
    world.add(_boardComponent);
    // _initBoard gọi SAU khi board component đã add vào world
    _initBoard();

    // Warm up AI isolate ngay khi game mở nếu chơi vs AI — nước đi đầu tiên
    // của AI sẽ không phải chờ cold-start.
    if (vsAI) {
      // Không await — chạy background, không chặn onLoad.
      // Nếu start fail, _doAIMove sẽ fallback sang chạy đồng bộ ở main isolate.
      _warmUpAiIsolate();
    }
  }

  Future<void> _warmUpAiIsolate() async {
    try {
      await _ensureAiIsolate();
    } catch (_) {
      // Nuốt lỗi — fallback sẽ xử lý khi cần.
    }
  }

  @override
  void onRemove() {
    _timer?.cancel();
    _timer = null;
    super.onRemove();
  }

  // ─── Board init ────────────────────────────────────────────────────────────

  void _initBoard() {
    board = List.generate(boardSize, (_) => List.filled(boardSize, 0));
    _currentPlayer = 1;
    _status = GameStatus.playing;
    winningCells = [];
    _moves.clear();
    _pieceOrder[1]!.clear();
    _pieceOrder[2]!.clear();
    _totalMoves = 0;
    _gameStartTime = DateTime.now();
    _startTimer();
    _notify();
  }

  bool get _usesSlidingCapRule => boardSize == 3 || boardSize == 4;

  /// Đếm số ô trống trên bàn cờ hiện tại.
  int _countEmptyCells() {
    int count = 0;
    for (int r = 0; r < boardSize; r++) {
      for (int c = 0; c < boardSize; c++) {
        if (board[r][c] == 0) count++;
      }
    }
    return count;
  }

  // ─── Timer ─────────────────────────────────────────────────────────────────

  void _startTimer() {
    _timer?.cancel();
    _timer = null;
    if (turnTimeSecs == 0) {
      _timeLeft = 0;
      return;
    }
    _timeLeft = turnTimeSecs;
    _timer = async.Timer.periodic(const Duration(seconds: 1), (_) {
      if (_status != GameStatus.playing) {
        _timer?.cancel();
        _timer = null;
        return;
      }
      _timeLeft--;
      if (_timeLeft <= 0) {
        _handleTimeout();
      } else {
        _notify();
      }
    });
  }

  void _handleTimeout() {
    _timer?.cancel();
    _timer = null;
    _status = GameStatus.timeout;
    AudioService().playTimeout();
    HapticFeedback.mediumImpact();
    if (_currentPlayer == 1) {
      oScore++;
    } else {
      xScore++;
    }
    _saveHistory(GameResult.timeout);
    _notify();
  }

  // ─── Notify — LUÔN dùng scheduleMicrotask để tránh "setState during build" ─

  void _notify() {
    // Gộp nhiều lần gọi liên tiếp thành 1 lần update duy nhất
    if (_pendingNotify) return;
    _pendingNotify = true;

    async.scheduleMicrotask(() {
      _pendingNotify = false;
      gameStateNotifier.value = GameState(
        currentPlayer: _currentPlayer,
        status: _status,
        timeLeft: _timeLeft,
        canUndo: _canUndo,
      );
    });
  }

  // ─── Undo ──────────────────────────────────────────────────────────────────

  bool get _canUndo {
    if (_moves.isEmpty) return false;
    if (vsAI) return _moves.length >= 2;
    return _moves.isNotEmpty;
  }

  // ─── Reset ─────────────────────────────────────────────────────────────────

  void resetGame() {
    _timer?.cancel();
    _timer = null;
    _initBoard();
    _boardComponent.resetAnimations();
    // US-003: reset = clean slate, xóa snapshot cũ.
    async.unawaited(GameSnapshotStore().clear());
    // _notify() đã được gọi bên trong _initBoard()
  }

  // ─── Undo Move ─────────────────────────────────────────────────────────────

  void undoMove() {
    if (!_canUndo || _status != GameStatus.playing) return;

    if (vsAI) {
      for (int i = 0; i < 2 && _moves.isNotEmpty; i++) {
        final m = _moves.removeLast();
        board[m.row][m.col] = 0;
        _boardComponent.removePiece(m.row, m.col);
        _pieceOrder[m.player]!.removeLast();
        if (_usesSlidingCapRule &&
            m.removedRow != null &&
            m.removedCol != null) {
          final int rr = m.removedRow!;
          final int rc = m.removedCol!;
          board[rr][rc] = m.player;
          _boardComponent.addPiece(rr, rc, m.player);
          _pieceOrder[m.player]!.insert(0, Point(rr, rc));
        }
        _totalMoves--;
      }
      _currentPlayer = 1;
    } else {
      final m = _moves.removeLast();
      board[m.row][m.col] = 0;
      _boardComponent.removePiece(m.row, m.col);
      _totalMoves--;
      _pieceOrder[m.player]!.removeLast();
      if (_usesSlidingCapRule && m.removedRow != null && m.removedCol != null) {
        final int rr = m.removedRow!;
        final int rc = m.removedCol!;
        board[rr][rc] = m.player;
        _boardComponent.addPiece(rr, rc, m.player);
        _pieceOrder[m.player]!.insert(0, Point(rr, rc));
      }
      _currentPlayer = m.player;
    }

    AudioService().playUndo();
    _startTimer();
    _notify();
  }

  // ─── Tap handler ───────────────────────────────────────────────────────────

  void handleTap(int row, int col) {
    if (_status != GameStatus.playing) return;
    if (board[row][col] != 0) return;
    if (vsAI && _currentPlayer == 2) return;
    _placeMove(row, col);
  }

  // ─── Place move ────────────────────────────────────────────────────────────

  void _placeMove(int row, int col) {
    int? removedRow;
    int? removedCol;
    // Sliding-cap rule: chỉ gỡ quân cũ nhất khi bàn cờ gần đầy
    // (chỉ còn đúng 1 ô trống — chính là ô sắp đánh vào).
    // Điều này đúng cho cả 3×3 (hết ô sau 8 quân) lẫn 4×4
    // (hết ô sau 15 quân), tránh việc gỡ quân sớm khi 4×4 còn nhiều ô trống.
    if (_usesSlidingCapRule) {
      final List<Point<int>> order = _pieceOrder[_currentPlayer]!;
      if (order.isNotEmpty && _countEmptyCells() == 1) {
        final Point<int> oldest = order.removeAt(0);
        removedRow = oldest.x;
        removedCol = oldest.y;
        board[removedRow][removedCol] = 0;
        _boardComponent.removePiece(removedRow, removedCol);
      }
    }
    board[row][col] = _currentPlayer;
    _moves.add(MoveRecord(
      row,
      col,
      _currentPlayer,
      removedRow: removedRow,
      removedCol: removedCol,
    ));
    _pieceOrder[_currentPlayer]!.add(Point(row, col));
    _totalMoves++;
    _boardComponent.addPiece(row, col, _currentPlayer);
    AudioService().playPlace();
    HapticFeedback.lightImpact();

    final wins = _checkWin(row, col, _currentPlayer);
    if (wins != null) {
      _timer?.cancel();
      _timer = null;
      winningCells = wins;
      _status = _currentPlayer == 1 ? GameStatus.xWins : GameStatus.oWins;
      if (_currentPlayer == 1) {
        xScore++;
      } else {
        oScore++;
      }
      _boardComponent.highlightWin(winningCells);
      AudioService().playWin();
      HapticFeedback.heavyImpact();
      _saveHistory(_currentPlayer == 1 ? GameResult.xWins : GameResult.oWins);
      _notify();
      return;
    }

    if (_isBoardFull()) {
      _timer?.cancel();
      _timer = null;
      _status = GameStatus.draw;
      draws++;
      HapticFeedback.mediumImpact();
      _saveHistory(GameResult.draw);
      _notify();
      return;
    }

    _currentPlayer = _currentPlayer == 1 ? 2 : 1;
    _startTimer();
    _notify();
    // US-003: auto-save sau mỗi nước đi (debounce 500ms trong store).
    _scheduleSnapshotSave();

    if (vsAI && _currentPlayer == 2) {
      // Keep a tiny delay for UX, but don't block timer perception.
      async.Future.delayed(const Duration(milliseconds: 80), _doAIMove);
    }
  }

  // ─── Snapshot / Resume (US-003) ────────────────────────────────────────────

  void _scheduleSnapshotSave() {
    if (_status != GameStatus.playing) return;
    if (_moves.isEmpty) return; // ván chưa có nước → không cần snapshot
    final List<MoveLog> log = _moves
        .map((MoveRecord m) => MoveLog(
              row: m.row,
              col: m.col,
              player: m.player,
              removedRow: m.removedRow,
              removedCol: m.removedCol,
            ))
        .toList();
    GameSnapshotStore().scheduleSave(GameSnapshot(
      mode: vsAI ? GameMode.vsAI : GameMode.twoPlayers,
      boardSide: boardSize,
      winLength: winLength,
      aiDifficultyIndex: vsAI ? AppSettings().aiDifficulty.index : -1,
      moves: log,
      timeLeftSecs: _timeLeft,
      savedAt: DateTime.now(),
    ));
  }

  /// Force-flush snapshot (gọi khi app sắp paused/detached).
  Future<void> flushSnapshot() => GameSnapshotStore().flushNow();

  /// Khôi phục state từ snapshot vào game đã [onLoad]. Gọi SAU khi
  /// BoardComponent đã sẵn sàng (sau onLoad). Snapshot phải có board size khớp
  /// với game đang chạy.
  void applySnapshot(GameSnapshot snap) {
    assert(snap.boardSide == boardSize,
        'Snapshot boardSide ${snap.boardSide} != game boardSize $boardSize');
    // Reset UI layer, giữ scores (match scores là cross-game trong session,
    // nhưng snapshot chỉ restore ván đơn — scores có thể bị lệch khi kill app.
    // Chấp nhận trade-off: khi resume, scores về 0 cho match mới).
    _boardComponent.resetAnimations();
    _initBoard();

    // Apply từng nước đi như đã xảy ra: set board array, add piece visual,
    // đẩy vào _moves + _pieceOrder để undo/win-detect hoạt động đúng.
    for (final MoveLog m in snap.moves) {
      // Xử lý sliding-cap removed piece TRƯỚC khi place (đúng order thời gian)
      if (m.removedRow != null && m.removedCol != null) {
        board[m.removedRow!][m.removedCol!] = 0;
        _boardComponent.removePiece(m.removedRow!, m.removedCol!);
        // Bỏ quân cũ khỏi _pieceOrder[m.player] (FIFO)
        final List<Point<int>> order = _pieceOrder[m.player]!;
        if (order.isNotEmpty) order.removeAt(0);
      }
      board[m.row][m.col] = m.player;
      _moves.add(MoveRecord(
        m.row,
        m.col,
        m.player,
        removedRow: m.removedRow,
        removedCol: m.removedCol,
      ));
      _pieceOrder[m.player]!.add(Point(m.row, m.col));
      _boardComponent.addPiece(m.row, m.col, m.player);
      _totalMoves++;
    }

    // currentPlayer: dựa vào nước cuối cùng — next player là đối thủ của họ.
    if (snap.moves.isNotEmpty) {
      _currentPlayer = snap.moves.last.player == 1 ? 2 : 1;
    }

    // Restore timer: nếu snapshot có timeLeft hợp lệ (>0 và setting bật timer),
    // set _timeLeft = snap.timeLeftSecs trước khi _startTimer(). Tránh bị reset.
    if (turnTimeSecs > 0 && snap.timeLeftSecs > 0) {
      _timeLeft = snap.timeLeftSecs;
      _timer?.cancel();
      _timer = async.Timer.periodic(const Duration(seconds: 1), (_) {
        if (_status != GameStatus.playing) {
          _timer?.cancel();
          _timer = null;
          return;
        }
        _timeLeft--;
        if (_timeLeft <= 0) {
          _handleTimeout();
        } else {
          _notify();
        }
      });
    }

    _notify();

    // Nếu đến lượt AI, trigger AI move ngay.
    if (vsAI && _currentPlayer == 2 && _status == GameStatus.playing) {
      async.Future.delayed(const Duration(milliseconds: 400), _doAIMove);
    }
  }

  // ─── Save history ──────────────────────────────────────────────────────────

  Future<void> _saveHistory(GameResult result) async {
    final duration = _gameStartTime != null
        ? DateTime.now().difference(_gameStartTime!).inSeconds
        : 0;
    final List<MoveLog> moveLog = _moves
        .map((MoveRecord m) => MoveLog(
              row: m.row,
              col: m.col,
              player: m.player,
              removedRow: m.removedRow,
              removedCol: m.removedCol,
            ))
        .toList();
    await GameHistory().add(GameRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      playedAt: DateTime.now(),
      mode: vsAI ? GameMode.vsAI : GameMode.twoPlayers,
      result: result,
      totalMoves: _totalMoves,
      durationSecs: duration,
      skinName: AppSettings().skin.name,
      boardSide: boardSize,
      winLength: winLength,
      aiDifficultyIndex: vsAI ? AppSettings().aiDifficulty.index : -1,
      moves: moveLog,
    ));
    // US-003: Ván đã kết thúc → xóa snapshot đang dở (nếu có).
    async.unawaited(GameSnapshotStore().clear());
    // US-004: Evaluate achievements sau khi history đã update. Newly unlocked
    // badges sẽ xuất hiện qua AchievementStore.newlyUnlockedQueue — GameScreen
    // listen và show toast.
    final Set<BadgeId> unlocked =
        AchievementEngine.evaluate(GameHistory().records);
    async.unawaited(AchievementStore().syncWithUnlocked(unlocked));
  }

  int get totalMoves => _totalMoves;

  int get gameDurationSecs => _gameStartTime != null
      ? DateTime.now().difference(_gameStartTime!).inSeconds
      : 0;

  // ─── AI ────────────────────────────────────────────────────────────────────

  Future<void> _doAIMove() async {
    if (_status != GameStatus.playing) return;
    if (_currentPlayer != 2) return;
    _aiRequestId++;
    final int requestId = _aiRequestId;
    final List<List<int>> snapshot =
        board.map((List<int> row) => List<int>.from(row)).toList();
    final AiDifficulty diff = AppSettings().aiDifficulty;
    final AiMoveRequest req = AiMoveRequest(
      board: snapshot,
      boardSize: boardSize,
      winLength: winLength,
      difficultyIndex: diff.index,
      randomSeed: _aiRandom.nextInt(1 << 30),
      isSlidingCapRuleEnabled: _usesSlidingCapRule,
      maxPiecesPerPlayer: boardSize * boardSize, // placeholder — AI dùng board fullness
      orderP1: _serializeOrder(_pieceOrder[1]!),
      orderP2: _serializeOrder(_pieceOrder[2]!),
    );

    List<int>? res;
    try {
      final IsolateManager<List<int>?, AiMoveRequest> isolate =
          await _ensureAiIsolate();
      res = await isolate.compute(req);
    } catch (_) {
      // Fallback: chạy AI ngay trên main isolate (blocking) thay vì bỏ nước đi.
      // Trường hợp này hiếm (spawn isolate fail), nên accept hit nhỏ về UX
      // hơn là để game đứng hình.
      try {
        res = AiEngine.pickMove(req);
      } catch (_) {
        res = null;
      }
    }

    if (res == null) return;
    // Kiểm tra lại state sau khi isolate trả về (user có thể đã reset/undo).
    if (_status != GameStatus.playing) return;
    if (_currentPlayer != 2) return;
    if (requestId != _aiRequestId) return;
    final int r = res[0];
    final int c = res[1];
    if (r < 0 || r >= boardSize || c < 0 || c >= boardSize) return;
    if (board[r][c] != 0) return;
    _placeMove(r, c);
  }

  static List<int> _serializeOrder(List<Point<int>> points) {
    final List<int> out = <int>[];
    for (final Point<int> p in points) {
      out.add(p.x);
      out.add(p.y);
    }
    return out;
  }

  bool _isBoardFull() {
    for (int r = 0; r < boardSize; r++) {
      for (int c = 0; c < boardSize; c++) {
        if (board[r][c] == 0) return false;
      }
    }
    return true;
  }

  List<Point<int>>? _checkWin(int row, int col, int player) {
    const dirs = [(0, 1), (1, 0), (1, 1), (1, -1)];
    for (final dir in dirs) {
      final cells = <Point<int>>[Point(row, col)];
      for (int i = 1; i < winLength; i++) {
        final nr = row + dir.$1 * i, nc = col + dir.$2 * i;
        if (nr < 0 || nr >= boardSize || nc < 0 || nc >= boardSize) break;
        if (board[nr][nc] == player) {
          cells.add(Point(nr, nc));
        } else {
          break;
        }
      }
      for (int i = 1; i < winLength; i++) {
        final nr = row - dir.$1 * i, nc = col - dir.$2 * i;
        if (nr < 0 || nr >= boardSize || nc < 0 || nc >= boardSize) break;
        if (board[nr][nc] == player) {
          cells.add(Point(nr, nc));
        } else {
          break;
        }
      }
      if (cells.length >= winLength) return cells;
    }
    return null;
  }
}
