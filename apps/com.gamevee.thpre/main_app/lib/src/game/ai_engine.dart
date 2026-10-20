import 'dart:math';

/// Top-level entry point used by `IsolateManager` to run the AI move
/// computation inside a long-lived background isolate. Must be a top-level
/// (not method) function. `@pragma('vm:entry-point')` prevents tree-shaking
/// from stripping the symbol in release builds.
@pragma('vm:entry-point')
List<int>? aiPickMoveWorker(AiMoveRequest req) => AiEngine.pickMove(req);

// ─── Threat score constants (calibrated for gomoku / caro) ───────────────────
//
// The hierarchy reflects standard gomoku theory:
//   Five        → immediate win
//   Open Four   → XOOOO X (both ends free) → wins next move regardless of opponent
//   Dead Four   → XOOOO| (one end blocked) → wins next move IF opponent doesn't block
//   Open Three  → _OOO_   → creates two open-four threats simultaneously
//   Dead Three  → _OOO|   → one open-four threat
//   Open Two    → _OO_
//   Dead Two    → _OO|
//
// Scores are 10× apart so single stronger threat > many weaker threats.
const int _sWin    = 100000000;
const int _sOpen4  = 1000000;
const int _sDead4  = 100000;
const int _sOpen3  = 10000;
const int _sDead3  = 1000;
const int _sOpen2  = 100;
const int _sDead2  = 10;
const int _sOpen1  = 1;

// ─── Request ─────────────────────────────────────────────────────────────────

class AiMoveRequest {
  final List<List<int>> board;
  final int boardSize;
  final int winLength;
  final int difficultyIndex;
  final int randomSeed;
  final bool isSlidingCapRuleEnabled;
  final int maxPiecesPerPlayer;
  final List<int> orderP1;
  final List<int> orderP2;

  const AiMoveRequest({
    required this.board,
    required this.boardSize,
    required this.winLength,
    required this.difficultyIndex,
    required this.randomSeed,
    required this.isSlidingCapRuleEnabled,
    required this.maxPiecesPerPlayer,
    required this.orderP1,
    required this.orderP2,
  });
}

// ─── Engine ──────────────────────────────────────────────────────────────────

class AiEngine {
  // Terminal values offset by depth so shallower wins are preferred.
  static const int _aiWinTerminal  =  100000000;
  static const int _aiLoseTerminal = -100000000;
  static const int _ttMaxEntries   = 500000;

  static const List<(int, int)> _dirs = [(0, 1), (1, 0), (1, 1), (1, -1)];

  // ─── Public entry point ──────────────────────────────────────────────────

  static List<int>? pickMove(AiMoveRequest req) {
    final Random random = Random(req.randomSeed);
    final List<List<int>> board = req.board;
    final int n = req.boardSize;
    final int w = req.winLength;
    final List<(int, int)> candidates = _getCandidateMoves(board, n);
    if (candidates.isEmpty) return null;

    // ── Priority 1: win immediately ─────────────────────────────────────────
    final (int, int)? winAi = _findImmediateWinningMove(board, n, w, 2, candidates);
    if (winAi != null) return [winAi.$1, winAi.$2];

    // ── Priority 2: block human immediate win ───────────────────────────────
    final (int, int)? winHuman = _findImmediateWinningMove(board, n, w, 1, candidates);
    if (winHuman != null) {
      if (req.difficultyIndex != 0 || random.nextDouble() < 0.55) {
        return [winHuman.$1, winHuman.$2];
      }
    }

    // ── Priority 3 (medium+): create / block open-four threats ─────────────
    if (req.difficultyIndex >= 1) {
      // If AI can create an open-four, that guarantees a win in 2 moves.
      final (int, int)? aiOpenFour =
          _findMoveCreatingForcedWin(board, n, w, 2, candidates);
      if (aiOpenFour != null) return [aiOpenFour.$1, aiOpenFour.$2];

      // If human can create an open-four on their next turn, block it.
      final (int, int)? humanOpenFour =
          _findMoveCreatingForcedWin(board, n, w, 1, candidates);
      if (humanOpenFour != null) return [humanOpenFour.$1, humanOpenFour.$2];
    }

    // ── Easy difficulty: play randomly among candidates ─────────────────────
    if (req.difficultyIndex == 0) {
      final (int, int) m = candidates[random.nextInt(candidates.length)];
      return [m.$1, m.$2];
    }

    final List<int> order1 = List<int>.from(req.orderP1);
    final List<int> order2 = List<int>.from(req.orderP2);

    // ── Medium difficulty: one-ply heuristic ────────────────────────────────
    if (req.difficultyIndex == 1) {
      final (int, int)? m = _bestMoveOnePly(
        board, n, w, candidates,
        isSliding: req.isSlidingCapRuleEnabled,
        maxPieces: req.maxPiecesPerPlayer,
        orderP1: order1,
        orderP2: order2,
      );
      return m == null ? null : [m.$1, m.$2];
    }

    // ── Hard difficulty: iterative-deepening negamax ─────────────────────────
    final int maxDepth     = _maxDepthFor(n);
    final int timeBudgetMs = _timeBudgetMsFor(req.difficultyIndex, n);
    final (int, int)? m = _bestMoveIterativeDeepening(
      board: board,
      n: n,
      w: w,
      candidates: candidates,
      maxDepth: maxDepth,
      timeBudgetMs: timeBudgetMs,
      random: random,
      isSliding: req.isSlidingCapRuleEnabled,
      maxPieces: req.maxPiecesPerPlayer,
      orderP1: order1,
      orderP2: order2,
    );
    return m == null ? null : [m.$1, m.$2];
  }

  // ─── Search parameters ───────────────────────────────────────────────────

  static int _maxDepthFor(int n) {
    final int cells = n * n;
    if (cells <= 9)  return 12;
    if (cells <= 25) return 8;
    if (cells <= 64) return 8;
    // 10×10 and larger: rely on time budget, allow up to depth 8.
    return 8;
  }

  static int _timeBudgetMsFor(int difficultyIndex, int n) {
    if (difficultyIndex <= 1) return 40;
    if (n <= 5)  return 600;
    if (n <= 8)  return 900;
    if (n <= 10) return 1200;
    return 1500; // 15×15 hard: up to 1.5 s for strongest play.
  }

  // ─── Core scoring primitives ─────────────────────────────────────────────

  /// Map (count, openEnds, winLength) → threat score.
  static int _scoreSeq(int count, int openEnds, int w) {
    if (count >= w) return _sWin;
    final int need = w - count;
    if (need == 1) {
      if (openEnds == 2) return _sOpen4;
      if (openEnds == 1) return _sDead4;
    } else if (need == 2) {
      if (openEnds == 2) return _sOpen3;
      if (openEnds == 1) return _sDead3;
    } else if (need == 3) {
      if (openEnds == 2) return _sOpen2;
      if (openEnds == 1) return _sDead2;
    } else {
      if (openEnds > 0) return _sOpen1;
    }
    return 0;
  }

  /// Score the contiguous sequence of `player` that passes through (r,c) in
  /// direction (dr,dc).  The cell (r,c) must already contain `player`.
  ///
  /// Unlike the old forward-only implementation, this scans both directions
  /// from (r,c) so the result is always the full run length.
  static int _evaluateLine(
    List<List<int>> board,
    int n,
    int w,
    int r,
    int c,
    int dr,
    int dc,
    int player,
  ) {
    // Count pieces in the forward (+) direction.
    int fwd = 0;
    for (int i = 1; i < w; i++) {
      final int nr = r + dr * i, nc = c + dc * i;
      if (nr < 0 || nr >= n || nc < 0 || nc >= n || board[nr][nc] != player) break;
      fwd++;
    }
    // Count pieces in the backward (−) direction.
    int bwd = 0;
    for (int i = 1; i < w; i++) {
      final int nr = r - dr * i, nc = c - dc * i;
      if (nr < 0 || nr >= n || nc < 0 || nc >= n || board[nr][nc] != player) break;
      bwd++;
    }
    final int count = 1 + fwd + bwd;

    // Check open ends beyond the sequence.
    final int efr = r + dr * (fwd + 1), efc = c + dc * (fwd + 1);
    final bool openFwd =
        efr >= 0 && efr < n && efc >= 0 && efc < n && board[efr][efc] == 0;
    final int ebr = r - dr * (bwd + 1), ebc = c - dc * (bwd + 1);
    final bool openBwd =
        ebr >= 0 && ebr < n && ebc >= 0 && ebc < n && board[ebr][ebc] == 0;

    return _scoreSeq(count, (openFwd ? 1 : 0) + (openBwd ? 1 : 0), w);
  }

  /// Full static evaluation of the board from the AI's (player 2) perspective.
  ///
  /// Scans every direction using a canonical-start rule so each sequence is
  /// counted exactly once.  Adds a small centre-proximity bonus so the AI
  /// favours central positions when threat values are equal.
  static int _evaluateBoard(List<List<int>> board, int n, int w) {
    int aiScore = 0, humanScore = 0;
    final double cr = (n - 1) / 2.0, cc = (n - 1) / 2.0;

    for (final (int dr, int dc) in _dirs) {
      for (int r = 0; r < n; r++) {
        for (int c = 0; c < n; c++) {
          final int p = board[r][c];
          if (p == 0) continue;

          // Only process the first cell of each sequence (canonical start).
          final int pr = r - dr, pc = c - dc;
          if (pr >= 0 && pr < n && pc >= 0 && pc < n && board[pr][pc] == p) {
            continue;
          }

          // Measure sequence length.
          int count = 0;
          while (true) {
            final int nr = r + dr * count, nc = c + dc * count;
            if (nr < 0 || nr >= n || nc < 0 || nc >= n || board[nr][nc] != p) {
              break;
            }
            count++;
          }

          // Check open ends.
          final bool ob =
              pr >= 0 && pr < n && pc >= 0 && pc < n && board[pr][pc] == 0;
          final int er = r + dr * count, ec = c + dc * count;
          final bool oa =
              er >= 0 && er < n && ec >= 0 && ec < n && board[er][ec] == 0;

          final int s = _scoreSeq(count, (ob ? 1 : 0) + (oa ? 1 : 0), w);
          if (p == 2) {
            aiScore += s;
          } else {
            humanScore += s;
          }
        }
      }
    }

    // Early-exit on terminal positions found during leaf eval.
    if (aiScore >= _sWin)    return _aiWinTerminal;
    if (humanScore >= _sWin) return _aiLoseTerminal;

    // Centre-proximity bonus (small: won't override threat evaluation).
    int centreBonus = 0;
    for (int r = 0; r < n; r++) {
      for (int c = 0; c < n; c++) {
        final int p = board[r][c];
        if (p == 0) continue;
        final double dist =
            (r - cr).abs() + (c - cc).abs();
        final int bonus = (n - dist.round()).clamp(0, n);
        if (p == 2) {
          centreBonus += bonus;
        } else {
          centreBonus -= bonus;
        }
      }
    }

    // Defensive bias: weight opponent threats 20 % higher to avoid being
    // caught by traps while still playing aggressively.
    return aiScore - (humanScore * 12 ~/ 10) + centreBonus;
  }

  // ─── Move heuristic (used for ordering and one-ply) ─────────────────────

  /// Score a candidate move at (r,c) for `player` by evaluating both the
  /// offensive gain (what the player achieves) and the defensive gain (what
  /// is denied to the opponent).  Checks all four directions bidirectionally.
  static int _scoreMoveHeuristic(
    List<List<int>> board,
    int n,
    int w,
    int r,
    int c,
    int player,
  ) {
    final int opp = player == 1 ? 2 : 1;
    int offScore = 0, defScore = 0;

    board[r][c] = player;
    for (final (int dr, int dc) in _dirs) {
      offScore += _evaluateLine(board, n, w, r, c, dr, dc, player);
    }

    board[r][c] = opp;
    for (final (int dr, int dc) in _dirs) {
      defScore += _evaluateLine(board, n, w, r, c, dr, dc, opp);
    }

    board[r][c] = 0;

    // Winning moves get highest weight; blocking is slightly less urgent
    // than attacking so the AI is willing to sacrifice defence for a win.
    return offScore * 2 + defScore;
  }

  // ─── Immediate win / forced win detection ────────────────────────────────

  static (int, int)? _findImmediateWinningMove(
    List<List<int>> board,
    int n,
    int w,
    int player,
    List<(int, int)> candidates,
  ) {
    for (final (int r, int c) in candidates) {
      board[r][c] = player;
      final bool wins = _checkWin(board, n, w, r, c, player);
      board[r][c] = 0;
      if (wins) return (r, c);
    }
    return null;
  }

  /// Returns a candidate that, when played for `player`, creates an open-four
  /// (count == w−1 with both ends open) or a dead-four (count == w−1 with one
  /// end open) in any direction.  Both are "forced win" threats that the
  /// opponent must block on the very next turn.
  static (int, int)? _findMoveCreatingForcedWin(
    List<List<int>> board,
    int n,
    int w,
    int player,
    List<(int, int)> candidates,
  ) {
    for (final (int r, int c) in candidates) {
      board[r][c] = player;
      for (final (int dr, int dc) in _dirs) {
        final int s = _evaluateLine(board, n, w, r, c, dr, dc, player);
        if (s >= _sDead4) {
          board[r][c] = 0;
          return (r, c);
        }
      }
      board[r][c] = 0;
    }
    return null;
  }

  // ─── Candidate generation ────────────────────────────────────────────────

  /// All empty cells within Chebyshev distance 2 of any occupied cell.
  /// Falls back to the centre on an empty board.
  static List<(int, int)> _getCandidateMoves(List<List<int>> board, int n) {
    final Set<(int, int)> result = {};
    bool hasAny = false;
    for (int r = 0; r < n; r++) {
      for (int c = 0; c < n; c++) {
        if (board[r][c] != 0) {
          hasAny = true;
          for (int dr = -2; dr <= 2; dr++) {
            for (int dc = -2; dc <= 2; dc++) {
              final int nr = r + dr, nc = c + dc;
              if (nr >= 0 &&
                  nr < n &&
                  nc >= 0 &&
                  nc < n &&
                  board[nr][nc] == 0) {
                result.add((nr, nc));
              }
            }
          }
        }
      }
    }
    if (!hasAny) return [(n ~/ 2, n ~/ 2)];
    return result.toList();
  }

  /// Return the top [limit] candidates scored by the combined
  /// offense+defense heuristic.  When the candidate list is already small
  /// enough, it is returned as-is (no allocation overhead).
  static List<(int, int)> _topCandidateMovesForPlayer(
    List<List<int>> board,
    int n,
    int w,
    int forPlayer, {
    required int limit,
  }) {
    final List<(int, int)> raw = _getCandidateMoves(board, n);
    if (raw.length <= limit) return raw;
    final scored = <({int score, (int, int) m})>[];
    for (final (int r, int c) in raw) {
      scored.add((
        score: _scoreMoveHeuristic(board, n, w, r, c, forPlayer),
        m: (r, c),
      ));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).map((e) => e.m).toList();
  }

  static List<(int, int)> _orderMoves(
    List<List<int>> board,
    int n,
    int w,
    List<(int, int)> moves,
    int player,
  ) {
    final scored = <({int score, (int, int) m})>[];
    for (final (int r, int c) in moves) {
      scored.add((
        score: _scoreMoveHeuristic(board, n, w, r, c, player),
        m: (r, c),
      ));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.map((e) => e.m).toList();
  }

  // ─── One-ply search (medium difficulty) ─────────────────────────────────

  static (int, int)? _bestMoveOnePly(
    List<List<int>> board,
    int n,
    int w,
    List<(int, int)> candidates, {
    required bool isSliding,
    required int maxPieces,
    required List<int> orderP1,
    required List<int> orderP2,
  }) {
    int bestScore = -999999999;
    (int, int)? bestMove;
    for (final (int r, int c) in candidates) {
      final List<int>? removed = _applySlidingMoveIfNeeded(
        board: board,
        player: 2,
        isSliding: isSliding,
        maxPieces: maxPieces,
        orderP1: orderP1,
        orderP2: orderP2,
      );
      board[r][c] = 2;
      _appendOrder(orderP2, r, c);
      final int score = _evaluateBoard(board, n, w);
      _removeLastOrder(orderP2);
      board[r][c] = 0;
      _undoSlidingMoveIfNeeded(
        board: board,
        player: 2,
        removed: removed,
        isSliding: isSliding,
        orderP1: orderP1,
        orderP2: orderP2,
      );
      if (score > bestScore) {
        bestScore = score;
        bestMove = (r, c);
      }
    }
    return bestMove;
  }

  // ─── Iterative-deepening negamax (hard difficulty) ───────────────────────

  static (int, int)? _bestMoveIterativeDeepening({
    required List<List<int>> board,
    required int n,
    required int w,
    required List<(int, int)> candidates,
    required int maxDepth,
    required int timeBudgetMs,
    required Random random,
    required bool isSliding,
    required int maxPieces,
    required List<int> orderP1,
    required List<int> orderP2,
  }) {
    final Stopwatch sw = Stopwatch()..start();
    final List<int> zobrist = _buildZobristTable(n, seed: 1337);
    final Map<int, _TranspositionEntry> tt = {};
    int rootHash = _computeBoardHash(board, n, zobrist);

    (int, int)? bestMove;
    // Pre-order root moves once; inner iterations rely on TT for re-ordering.
    final List<(int, int)> rootOrdered = _orderMoves(board, n, w, candidates, 2);

    for (int depth = 1; depth <= maxDepth; depth++) {
      if (sw.elapsedMilliseconds >= timeBudgetMs) break;

      int localBest = -999999999;
      (int, int)? localMove;

      for (final (int r, int c) in rootOrdered) {
        if (sw.elapsedMilliseconds >= timeBudgetMs) break;

        final List<int>? removed = _applySlidingMoveIfNeeded(
          board: board,
          player: 2,
          isSliding: isSliding,
          maxPieces: maxPieces,
          orderP1: orderP1,
          orderP2: orderP2,
        );
        board[r][c] = 2;
        _appendOrder(orderP2, r, c);
        rootHash = _applyHash(rootHash, n, zobrist, r, c, 2);

        final int score = -_negamaxTt(
          board: board,
          n: n,
          w: w,
          depth: 0,
          maxDepth: depth,
          alpha: -999999999,
          beta: 999999999,
          playerToMove: 1,
          lastMoveRow: r,
          lastMoveCol: c,
          lastMovePlayer: 2,
          hash: rootHash,
          tt: tt,
          sw: sw,
          timeBudgetMs: timeBudgetMs,
          zobrist: zobrist,
          isSliding: isSliding,
          maxPieces: maxPieces,
          orderP1: orderP1,
          orderP2: orderP2,
        );

        rootHash = _applyHash(rootHash, n, zobrist, r, c, 2);
        _removeLastOrder(orderP2);
        board[r][c] = 0;
        _undoSlidingMoveIfNeeded(
          board: board,
          player: 2,
          removed: removed,
          isSliding: isSliding,
          orderP1: orderP1,
          orderP2: orderP2,
        );

        if (score > localBest) {
          localBest = score;
          localMove = (r, c);
        }
      }

      if (localMove != null) bestMove = localMove;
    }

    if (bestMove != null) return bestMove;
    return rootOrdered.isEmpty
        ? candidates[random.nextInt(candidates.length)]
        : rootOrdered.first;
  }

  // ─── Negamax with alpha-beta pruning + transposition table ───────────────

  static int _negamaxTt({
    required List<List<int>> board,
    required int n,
    required int w,
    required int depth,
    required int maxDepth,
    required int alpha,
    required int beta,
    required int playerToMove,
    required int lastMoveRow,
    required int lastMoveCol,
    required int lastMovePlayer,
    required int hash,
    required Map<int, _TranspositionEntry> tt,
    required Stopwatch sw,
    required int timeBudgetMs,
    required List<int> zobrist,
    required bool isSliding,
    required int maxPieces,
    required List<int> orderP1,
    required List<int> orderP2,
  }) {
    // Time check — return static eval when budget exhausted.
    if (sw.elapsedMilliseconds >= timeBudgetMs) {
      return _evaluateBoard(board, n, w);
    }

    // Terminal: last move won.
    if (_checkWin(board, n, w, lastMoveRow, lastMoveCol, lastMovePlayer)) {
      return lastMovePlayer == 2
          ? _aiWinTerminal - depth
          : _aiLoseTerminal + depth;
    }

    // Leaf or full board.
    if (depth >= maxDepth || _isBoardFull(board, n)) {
      return _evaluateBoard(board, n, w);
    }

    // Transposition table look-up.
    final _TranspositionEntry? cached = tt[hash];
    if (cached != null && cached.depth >= (maxDepth - depth)) {
      if (cached.flag == _TtFlag.exact) return cached.score;
      if (cached.flag == _TtFlag.lowerBound && cached.score > alpha) {
        alpha = cached.score;
      }
      if (cached.flag == _TtFlag.upperBound && cached.score < beta) {
        beta = cached.score;
      }
      if (alpha >= beta) return cached.score;
    }

    // Generate and order moves.
    // Increase move limit near the root for better coverage.
    final int candidateLimit = depth <= 1 ? 20 : 15;
    final List<(int, int)> moves = _topCandidateMovesForPlayer(
      board, n, w, playerToMove,
      limit: candidateLimit,
    );
    if (moves.isEmpty) return _evaluateBoard(board, n, w);

    final List<(int, int)> ordered = _orderMoves(board, n, w, moves, playerToMove);

    final int alphaOrig = alpha;
    int best = -999999999;
    int a = alpha;
    int localHash = hash;

    for (final (int r, int c) in ordered) {
      if (sw.elapsedMilliseconds >= timeBudgetMs) break;

      final List<int>? removed = _applySlidingMoveIfNeeded(
        board: board,
        player: playerToMove,
        isSliding: isSliding,
        maxPieces: maxPieces,
        orderP1: orderP1,
        orderP2: orderP2,
      );
      board[r][c] = playerToMove;
      if (playerToMove == 1) {
        _appendOrder(orderP1, r, c);
      } else {
        _appendOrder(orderP2, r, c);
      }
      localHash = _applyHash(localHash, n, zobrist, r, c, playerToMove);

      final int score = -_negamaxTt(
        board: board,
        n: n,
        w: w,
        depth: depth + 1,
        maxDepth: maxDepth,
        alpha: -beta,
        beta: -a,
        playerToMove: playerToMove == 2 ? 1 : 2,
        lastMoveRow: r,
        lastMoveCol: c,
        lastMovePlayer: playerToMove,
        hash: localHash,
        tt: tt,
        sw: sw,
        timeBudgetMs: timeBudgetMs,
        zobrist: zobrist,
        isSliding: isSliding,
        maxPieces: maxPieces,
        orderP1: orderP1,
        orderP2: orderP2,
      );

      localHash = _applyHash(localHash, n, zobrist, r, c, playerToMove);
      if (playerToMove == 1) {
        _removeLastOrder(orderP1);
      } else {
        _removeLastOrder(orderP2);
      }
      board[r][c] = 0;
      _undoSlidingMoveIfNeeded(
        board: board,
        player: playerToMove,
        removed: removed,
        isSliding: isSliding,
        orderP1: orderP1,
        orderP2: orderP2,
      );

      if (score > best) best = score;
      if (best > a) a = best;
      if (a >= beta) break; // alpha-beta cut-off
    }

    // Store result in transposition table.
    // Replace oldest entries when the table exceeds the limit.
    if (tt.length > _ttMaxEntries) {
      // Remove ~20 % of entries to avoid thrashing.
      final int toRemove = _ttMaxEntries ~/ 5;
      final List<int> keys = tt.keys.take(toRemove).toList();
      for (final k in keys) tt.remove(k);
    }
    final _TtFlag flag;
    if (best <= alphaOrig) {
      flag = _TtFlag.upperBound;
    } else if (best >= beta) {
      flag = _TtFlag.lowerBound;
    } else {
      flag = _TtFlag.exact;
    }
    tt[hash] = _TranspositionEntry(
      depth: maxDepth - depth,
      score: best,
      flag: flag,
    );
    return best;
  }

  // ─── Win / full-board detection ──────────────────────────────────────────

  static bool _checkWin(
    List<List<int>> board,
    int n,
    int w,
    int row,
    int col,
    int player,
  ) {
    for (final (int dr, int dc) in _dirs) {
      int count = 1;
      for (int i = 1; i < w; i++) {
        final int nr = row + dr * i, nc = col + dc * i;
        if (nr < 0 || nr >= n || nc < 0 || nc >= n) break;
        if (board[nr][nc] == player) count++; else break;
      }
      for (int i = 1; i < w; i++) {
        final int nr = row - dr * i, nc = col - dc * i;
        if (nr < 0 || nr >= n || nc < 0 || nc >= n) break;
        if (board[nr][nc] == player) count++; else break;
      }
      if (count >= w) return true;
    }
    return false;
  }

  static bool _isBoardFull(List<List<int>> board, int n) {
    for (int r = 0; r < n; r++) {
      for (int c = 0; c < n; c++) {
        if (board[r][c] == 0) return false;
      }
    }
    return true;
  }

  // ─── Sliding-cap rule helpers ─────────────────────────────────────────────

  static void _appendOrder(List<int> order, int row, int col) {
    order.add(row);
    order.add(col);
  }

  static void _removeLastOrder(List<int> order) {
    order.removeLast();
    order.removeLast();
  }

  /// Đếm số ô trống trên board mô phỏng của AI.
  static int _countEmptyCells(List<List<int>> board) {
    int count = 0;
    final int n = board.length;
    for (int r = 0; r < n; r++) {
      for (int c = 0; c < n; c++) {
        if (board[r][c] == 0) count++;
      }
    }
    return count;
  }

  /// Gỡ quân cũ nhất của [player] khi bàn cờ chỉ còn đúng 1 ô trống
  /// (tức là ô mà AI sắp đặt quân vào).  Logic này áp dụng nhất quán cho
  /// cả 3×3 lẫn 4×4 — tránh gỡ quân sớm khi vẫn còn nhiều ô trống (lỗi 4×4).
  static List<int>? _applySlidingMoveIfNeeded({
    required List<List<int>> board,
    required int player,
    required bool isSliding,
    required int maxPieces, // tham số giữ lại cho tương thích API, không dùng để so ngưỡng
    required List<int> orderP1,
    required List<int> orderP2,
  }) {
    if (!isSliding) return null;
    // Chỉ gỡ khi bàn gần đầy: đúng 1 ô trống còn lại (chính là ô sắp đặt)
    if (_countEmptyCells(board) != 1) return null;
    final List<int> order = player == 1 ? orderP1 : orderP2;
    if (order.isEmpty) return null;
    final int rr = order[0], rc = order[1];
    board[rr][rc] = 0;
    order.removeAt(0);
    order.removeAt(0);
    return [rr, rc];
  }

  static void _undoSlidingMoveIfNeeded({
    required List<List<int>> board,
    required int player,
    required List<int>? removed,
    required bool isSliding,
    required List<int> orderP1,
    required List<int> orderP2,
  }) {
    if (!isSliding || removed == null) return;
    final int rr = removed[0], rc = removed[1];
    board[rr][rc] = player;
    final List<int> order = player == 1 ? orderP1 : orderP2;
    order.insert(0, rc);
    order.insert(0, rr);
  }

  // ─── Zobrist hashing ─────────────────────────────────────────────────────

  static List<int> _buildZobristTable(int side, {required int seed}) {
    final Random rnd = Random(seed);
    final int cells = side * side;
    final List<int> t = List<int>.filled(cells * 2, 0);
    for (int i = 0; i < t.length; i++) {
      final int hi = rnd.nextInt(1 << 30);
      final int lo = rnd.nextInt(1 << 30);
      t[i] = (hi << 32) ^ lo;
    }
    return t;
  }

  static int _zIndex(int side, int row, int col, int player) =>
      (row * side + col) * 2 + (player - 1);

  static int _applyHash(
    int hash,
    int side,
    List<int> table,
    int row,
    int col,
    int player,
  ) =>
      hash ^ table[_zIndex(side, row, col, player)];

  static int _computeBoardHash(
    List<List<int>> board,
    int side,
    List<int> table,
  ) {
    int h = 0;
    for (int r = 0; r < side; r++) {
      for (int c = 0; c < side; c++) {
        final int p = board[r][c];
        if (p != 0) h = _applyHash(h, side, table, r, c, p);
      }
    }
    return h;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // API bổ sung cho tính năng Phân tích ván đấu (US-005)
  //
  // NGUYÊN TẮC: chỉ THÊM, tuyệt đối không sửa hành vi của [pickMove] hay bất kỳ
  // hàm nào gameplay đang dùng. Toàn bộ phần dưới là public wrapper mỏng quanh
  // các primitive đã có.
  // ══════════════════════════════════════════════════════════════════════════

  /// Tổng điểm đe doạ của riêng [player] trên [board].
  ///
  /// Dùng đúng quy tắc canonical-start như [_evaluateBoard] nên mỗi chuỗi quân
  /// chỉ được tính một lần. Trả về [_sWin] khi player đã có đủ [w] quân liền.
  ///
  /// **Vì sao cần hàm này thay vì dùng thẳng [_evaluateBoard]:**
  /// [_evaluateBoard] KHÔNG đối xứng — nó nhân điểm đối thủ với 1.2 (thiên lệch
  /// phòng thủ) và cộng thêm centre bonus. Cả hai là thủ thuật tinh chỉnh cho
  /// AI chơi hay, nhưng làm méo thang đo khi cần lượng giá khách quan. Vì vậy
  /// tầng phân tích tự dựng thang đo đối xứng từ [threatScoreFor].
  static int threatScoreFor(List<List<int>> board, int n, int w, int player) {
    int total = 0;
    for (final (int dr, int dc) in _dirs) {
      for (int r = 0; r < n; r++) {
        for (int c = 0; c < n; c++) {
          final int p = board[r][c];
          if (p != player) continue;

          // Chỉ xử lý ô đầu tiên của mỗi chuỗi (canonical start).
          final int pr = r - dr, pc = c - dc;
          if (pr >= 0 && pr < n && pc >= 0 && pc < n && board[pr][pc] == p) {
            continue;
          }

          int count = 0;
          while (true) {
            final int nr = r + dr * count, nc = c + dc * count;
            if (nr < 0 || nr >= n || nc < 0 || nc >= n || board[nr][nc] != p) {
              break;
            }
            count++;
          }

          final bool ob =
              pr >= 0 && pr < n && pc >= 0 && pc < n && board[pr][pc] == 0;
          final int er = r + dr * count, ec = c + dc * count;
          final bool oa =
              er >= 0 && er < n && ec >= 0 && ec < n && board[er][ec] == 0;

          total += _scoreSeq(count, (ob ? 1 : 0) + (oa ? 1 : 0), w);
        }
      }
    }
    return total;
  }

  /// Điểm ngưỡng "thắng" — tầng phân tích cần hằng số này để nhận diện thế cờ
  /// đã kết thúc mà không phải tự đoán độ lớn.
  static int get winThreatScore => _sWin;

  /// Danh sách ô ứng viên (trong bán kính 2 quanh quân đã đặt).
  static List<(int, int)> candidateMoves(List<List<int>> board, int n) =>
      _getCandidateMoves(board, n);

  /// Tìm nước tốt nhất cho [player] bằng iterative-deepening negamax, với
  /// ngân sách thời gian tự chỉ định.
  ///
  /// Engine hard-code player 2 là bên đang đi. Khi [player] == 1, ta **lật bàn
  /// cờ** (đổi 1↔2) và hoán vị luôn hai mảng thứ tự quân, rồi gọi cùng một
  /// search. Toạ độ trả về không đổi vì phép lật chỉ đổi giá trị ô, không đổi
  /// vị trí.
  ///
  /// Lưu ý: phép lật là hợp lệ cho việc TÌM NƯỚC (search đối xứng theo cấu
  /// trúc), nhưng KHÔNG hợp lệ cho việc LƯỢNG GIÁ bằng [_evaluateBoard] —
  /// xem ghi chú ở [threatScoreFor].
  static List<int>? bestMoveForPlayer({
    required List<List<int>> board,
    required int n,
    required int w,
    required int player,
    required int timeBudgetMs,
    required int randomSeed,
    required bool isSliding,
    required List<int> orderP1,
    required List<int> orderP2,
  }) {
    final List<List<int>> work =
        player == 2 ? board : flipPlayers(board, n);
    final List<int> o1 = player == 2 ? List<int>.from(orderP1) : List<int>.from(orderP2);
    final List<int> o2 = player == 2 ? List<int>.from(orderP2) : List<int>.from(orderP1);

    final List<(int, int)> candidates = _getCandidateMoves(work, n);
    if (candidates.isEmpty) return null;

    final (int, int)? m = _bestMoveIterativeDeepening(
      board: work,
      n: n,
      w: w,
      candidates: candidates,
      maxDepth: _maxDepthFor(n),
      timeBudgetMs: timeBudgetMs,
      random: Random(randomSeed),
      isSliding: isSliding,
      maxPieces: n * n,
      orderP1: o1,
      orderP2: o2,
    );
    return m == null ? null : <int>[m.$1, m.$2];
  }

  /// Bản sao của [board] với hai bên đổi vai (1↔2). Ô trống giữ nguyên.
  static List<List<int>> flipPlayers(List<List<int>> board, int n) {
    return List<List<int>>.generate(
      n,
      (int r) => List<int>.generate(
        n,
        (int c) {
          final int v = board[r][c];
          return v == 0 ? 0 : (v == 1 ? 2 : 1);
        },
      ),
    );
  }
}

// ─── Transposition-table types ───────────────────────────────────────────────

enum _TtFlag { exact, lowerBound, upperBound }

class _TranspositionEntry {
  final int depth;
  final int score;
  final _TtFlag flag;

  const _TranspositionEntry({
    required this.depth,
    required this.score,
    required this.flag,
  });
}
