import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import '../core/achievements.dart';
import '../core/app_settings.dart';
import '../core/audio_service.dart';
import '../core/l10n.dart';
import '../core/game_history.dart';
import '../core/text_app_style.dart';
import '../game/caro_game.dart';
import 'result_screen.dart';

/// Reserved height for the VS-AI playing status line so the score panel does not jump.
const double _playingStatusLineSlotHeight = 26;
/// Reserved height under the board for [l10n.aiThinking] (padding + up to two lines).
const double _aiThinkingSlotHeight = 56;

class GameScreen extends StatefulWidget {
  final CaroGame game;
  final bool vsAI;

  const GameScreen({super.key, required this.game, required this.vsAI});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  bool _showingResult = false;
  bool _processingBadgeQueue = false;

  @override
  void initState() {
    super.initState();
    widget.game.gameStateNotifier.addListener(_onGameStateChanged);
    AchievementStore().newlyUnlockedQueue.addListener(_onBadgeQueueChanged);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AudioService().startMatchAmbience();
    });
  }

  /// US-004: show toast khi có badge mới. Queue pattern — 1 toast/lần,
  /// 1.5s giữa các toast để user có thể đọc từng cái.
  Future<void> _onBadgeQueueChanged() async {
    if (_processingBadgeQueue) return;
    _processingBadgeQueue = true;
    try {
      while (mounted) {
        final List<BadgeId> q = AchievementStore().newlyUnlockedQueue.value;
        if (q.isEmpty) break;
        final BadgeId id = q.first;
        _showBadgeToast(id);
        AchievementStore().popFromQueue(id);
        await Future<void>.delayed(const Duration(milliseconds: 1500));
      }
    } finally {
      _processingBadgeQueue = false;
    }
  }

  void _showBadgeToast(BadgeId id) {
    if (!mounted) return;
    final BadgeDef def = BadgeCatalog.def(id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 1400),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        content: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              colors: [
                def.tierColor.withValues(alpha: 0.25),
                const Color(0xFF1a1a3e).withValues(alpha: 0.95),
              ],
            ),
            border: Border.all(color: def.tierColor.withValues(alpha: 0.6)),
            boxShadow: [
              BoxShadow(
                color: def.tierColor.withValues(alpha: 0.4),
                blurRadius: 16,
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      def.tierColor.withValues(alpha: 0.4),
                      def.tierColor.withValues(alpha: 0.05),
                    ],
                  ),
                  border: Border.all(color: def.tierColor, width: 2),
                ),
                child: Icon(def.icon, color: def.tierColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.badgeUnlockedTitle,
                      style: TextAppStyle.ui(
                        fontSize: 11,
                        color: def.tierColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      l10n.get('${def.l10nKey}_name'),
                      style: TextAppStyle.ui(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // US-003: khi app vào background/sắp kill, flush snapshot ngay để user
    // có thể resume ở lần mở sau.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      widget.game.flushSnapshot();
    }
  }

  void _onGameStateChanged() {
    // Guard: không làm gì nếu widget đã bị dispose
    if (!mounted) return;

    final state = widget.game.gameStateNotifier.value;
    final isOver = state.status != GameStatus.playing;

    if (isOver && !_showingResult) {
      // setState an toàn vì _notify() luôn dùng scheduleMicrotask
      setState(() => _showingResult = true);
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) _showResultDialog();
      });
    }
  }

  void _showResultDialog() {
    if (!mounted) return;

    final state = widget.game.gameStateNotifier.value;
    GameResult result;
    switch (state.status) {
      case GameStatus.xWins:
        result = GameResult.xWins;
        break;
      case GameStatus.oWins:
        result = GameResult.oWins;
        break;
      case GameStatus.draw:
        result = GameResult.draw;
        break;
      case GameStatus.timeout:
        result = GameResult.timeout;
        break;
      case GameStatus.playing:
        return;
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) => ResultScreen(
        result: result,
        vsAI: widget.vsAI,
        totalMoves: widget.game.totalMoves,
        durationSecs: widget.game.gameDurationSecs,
        boardSide: widget.game.boardSize,
        winLength: widget.game.winLength,
        onPlayAgain: () {
          Navigator.pop(context);
          if (mounted) setState(() => _showingResult = false);
          widget.game.resetGame();
        },
        onHome: () {
          Navigator.pop(context);
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  void dispose() {
    widget.game.gameStateNotifier.removeListener(_onGameStateChanged);
    AchievementStore().newlyUnlockedQueue.removeListener(_onBadgeQueueChanged);
    WidgetsBinding.instance.removeObserver(this);
    // Flush snapshot lần cuối nếu user navigate back (không kill app).
    // Nếu ván đã kết thúc, clear trong _saveHistory đã chạy, flush là no-op.
    widget.game.flushSnapshot();
    AudioService().stopMatchAmbience();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070714),
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──
            _GameHeader(
              vsAI: widget.vsAI,
              game: widget.game,
              onReset: () {
                if (mounted) setState(() => _showingResult = false);
                widget.game.resetGame();
              },
              onUndo: () => widget.game.undoMove(),
              onBack: () => Navigator.pop(context),
            ),
            // ── Score + Status ──
            ValueListenableBuilder<GameState>(
              valueListenable: widget.game.gameStateNotifier,
              builder: (_, state, __) => _ScorePanel(
                game: widget.game,
                state: state,
                vsAI: widget.vsAI,
              ),
            ),
            // ── Timer ──
            if (AppSettings().turnTimeSecs > 0)
              ValueListenableBuilder<GameState>(
                valueListenable: widget.game.gameStateNotifier,
                builder: (_, state, __) => _TimerBar(
                  timeLeft: state.timeLeft,
                  totalTime: AppSettings().turnTimeSecs,
                  currentPlayer: state.currentPlayer,
                  playing: state.status == GameStatus.playing,
                ),
              ),
            // ── Board ──
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: GameWidget(game: widget.game),
              ),
            ),
            if (widget.vsAI)
              ValueListenableBuilder<GameState>(
                valueListenable: widget.game.gameStateNotifier,
                builder: (_, GameState state, __) {
                  final bool isAiTurn = state.status == GameStatus.playing &&
                      state.currentPlayer == 2;
                  return SizedBox(
                    height: _aiThinkingSlotHeight,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
                      child: Center(
                        child: AnimatedOpacity(
                          opacity: isAiTurn ? 1 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: Text(
                            l10n.aiThinking,
                            style: TextAppStyle.rajdhani(
                              color: AppSettings().skin.oColor,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Game Header ──────────────────────────────────────────────────────────────

class _GameHeader extends StatelessWidget {
  final bool vsAI;
  final CaroGame game;
  final VoidCallback onReset;
  final VoidCallback onUndo;
  final VoidCallback onBack;

  const _GameHeader({
    required this.vsAI,
    required this.game,
    required this.onReset,
    required this.onUndo,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          _HdrBtn(icon: Icons.arrow_back_ios, onTap: onBack),
          const Spacer(),
          Column(
            children: [
              Text(
                l10n.appTitle,
                style: TextAppStyle.sfProWithCjkFallback(
                  fontSize: 13,
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  height: 1.05,
                ).copyWith(
                  shadows: const [
                    Shadow(color: Color(0xFF4fc3f7), blurRadius: 8),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                vsAI ? 'VS AI' : '2 PLAYERS',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 9,
                  letterSpacing: 3,
                ),
              ),
            ],
          ),
          const Spacer(),
          ValueListenableBuilder<GameState>(
            valueListenable: game.gameStateNotifier,
            builder: (_, state, __) => Row(
              children: [
                AnimatedOpacity(
                  opacity: state.canUndo && state.status == GameStatus.playing
                      ? 1.0
                      : 0.3,
                  duration: const Duration(milliseconds: 200),
                  child: _HdrBtn(
                    icon: Icons.undo_rounded,
                    onTap: state.canUndo ? onUndo : () {},
                  ),
                ),
                const SizedBox(width: 8),
                _HdrBtn(icon: Icons.refresh_rounded, onTap: onReset),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HdrBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _HdrBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.12),
            width: 1,
          ),
          color: Colors.white.withValues(alpha: 0.04),
        ),
        child: Icon(
          icon,
          color: Colors.white.withValues(alpha: 0.7),
          size: 18,
        ),
      ),
    );
  }
}

// ─── Score Panel ──────────────────────────────────────────────────────────────

class _ScorePanel extends StatelessWidget {
  final CaroGame game;
  final GameState state;
  final bool vsAI;

  const _ScorePanel({
    required this.game,
    required this.state,
    required this.vsAI,
  });

  String get _statusText {
    switch (state.status) {
      case GameStatus.playing:
        if (vsAI) {
          return '';
        }
        return state.currentPlayer == 1 ? l10n.turnX : l10n.turnO;
      case GameStatus.xWins:
        return vsAI ? l10n.youWin : l10n.xWins;
      case GameStatus.oWins:
        return vsAI ? l10n.aiWins : l10n.oWins;
      case GameStatus.draw:
        return l10n.draw;
      case GameStatus.timeout:
        return l10n.timeout;
    }
  }

  Color get _statusColor {
    final skin = AppSettings().skin;
    switch (state.status) {
      case GameStatus.playing:
        return state.currentPlayer == 1 ? skin.xColor : skin.oColor;
      case GameStatus.xWins:
        return skin.xColor;
      case GameStatus.oWins:
        return skin.oColor;
      case GameStatus.draw:
        return Colors.amber;
      case GameStatus.timeout:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppSettings().skin;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          if (vsAI && state.status == GameStatus.playing) ...[
            SizedBox(
              height: _playingStatusLineSlotHeight,
              child: Center(
                child: AnimatedOpacity(
                  opacity: state.currentPlayer == 1 ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    l10n.yourTurn,
                    style: TextAppStyle.rajdhani(
                      color: skin.xColor,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ] else if (_statusText.isNotEmpty) ...[
            Text(
              _statusText,
              style: TextAppStyle.rajdhani(
                color: _statusColor,
                fontSize: 15,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ScoreBox(
                label: vsAI ? l10n.you : 'X',
                score: game.xScore,
                color: skin.xColor,
                active: state.currentPlayer == 1 &&
                    state.status == GameStatus.playing,
              ),
              _ScoreBox(
                label: l10n.drawLabel,
                score: game.draws,
                color: Colors.amber,
                active: false,
              ),
              _ScoreBox(
                label: vsAI ? l10n.ai : 'O',
                score: game.oScore,
                color: skin.oColor,
                active: state.currentPlayer == 2 &&
                    state.status == GameStatus.playing,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScoreBox extends StatelessWidget {
  final String label;
  final int score;
  final Color color;
  final bool active;

  const _ScoreBox({
    required this.label,
    required this.score,
    required this.color,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: active ? color.withValues(alpha: 0.18) : Colors.transparent,
        border: Border.all(
          color: active ? color : color.withValues(alpha: 0.25),
          width: active ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextAppStyle.rajdhani(
              color: color.withValues(alpha: 0.7),
              fontSize: 9,
              letterSpacing: 1.5,
            ),
          ),
          Text(
            '$score',
            style: TextAppStyle.rajdhani(
              color: color,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Timer Bar ────────────────────────────────────────────────────────────────

class _TimerBar extends StatelessWidget {
  final int timeLeft;
  final int totalTime;
  final int currentPlayer;
  final bool playing;

  const _TimerBar({
    required this.timeLeft,
    required this.totalTime,
    required this.currentPlayer,
    required this.playing,
  });

  @override
  Widget build(BuildContext context) {
    final skin = AppSettings().skin;
    final color = currentPlayer == 1 ? skin.xColor : skin.oColor;
    final ratio = totalTime > 0 ? timeLeft / totalTime : 1.0;
    final isUrgent = ratio <= 0.3;
    final barColor = isUrgent
        ? Color.lerp(Colors.red, color, ratio / 0.3)!
        : color;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: Row(
        children: [
          Container(
            width: 44,
            padding: const EdgeInsets.symmetric(vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: (isUrgent ? Colors.red : color).withValues(alpha: 0.15),
              border: Border.all(
                color:
                    (isUrgent ? Colors.red : color).withValues(alpha: 0.4),
              ),
            ),
            child: Center(
              child: Text(
                playing ? '${timeLeft}s' : '--',
                style: TextAppStyle.rajdhani(
                  color: isUrgent ? Colors.red : color,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Stack(
              children: [
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                AnimatedFractionallySizedBox(
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.linear,
                  widthFactor: playing ? ratio.clamp(0.0, 1.0) : 0,
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: barColor,
                      boxShadow: [
                        BoxShadow(
                          color: barColor.withValues(alpha: 0.5),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
