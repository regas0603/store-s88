import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../game/game_controller.dart';
import '../../game/models/game_config.dart';
import '../../l10n/strings.dart';
import '../widgets/app_background.dart';
import '../widgets/game_board.dart';
import '../widgets/neon_button.dart';
import '../widgets/result_sheet.dart';
import '../widgets/score_panel.dart';

/// Màn chơi chính, dùng chung cho cả ba chế độ.
///
/// Không tách thành ba màn riêng: khác biệt giữa các chế độ chỉ nằm ở phần
/// header (thẻ điểm hay thống kê) và ở việc ai được chạm — toàn bộ phần còn lại
/// giống hệt nhau. Ba bản sao sẽ lệch nhau ngay ở lần sửa lỗi đầu tiên.
class GameScreen extends StatefulWidget {
  final GameConfig config;

  const GameScreen({required this.config, super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  /// Chờ một nhịp sau khi lật cặp cuối rồi mới hiện kết quả: người chơi cần
  /// thấy lá cuối cùng khớp, và kịp lúc đó thống kê cũng đã ghi xong nên cờ
  /// "Kỷ lục mới" hiển thị chính xác.
  static const Duration _resultDelay = Duration(milliseconds: 700);

  GameController? _controller;
  bool _resultShown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;

    final scope = AppScope.of(context);
    final controller = GameController(
      config: widget.config,
      sound: scope.sound,
      stats: scope.stats,
    )..addListener(_onControllerChanged);
    _controller = controller;

    // start() phát notifyListeners ngay lập tức. Gọi thẳng ở đây sẽ là
    // setState() trong lúc build frame đầu tiên — Flutter assert ngay. Đẩy sang
    // sau frame đầu: người chơi thấy bàn úp đúng một frame rồi mới vào giai
    // đoạn xem trước.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      controller.start();
    });
  }

  @override
  void dispose() {
    _controller
      ?..removeListener(_onControllerChanged)
      ..dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});

    if (_controller?.phase == GamePhase.finished && !_resultShown) {
      _resultShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showResult());
    }
  }

  String _playerName(int index) {
    final s = AppStrings.of(context);
    switch (widget.config.mode) {
      case GameMode.solo:
        return s.you;
      case GameMode.vsAi:
        return index == 0 ? s.you : s.ai;
      case GameMode.pvp:
        return index == 0 ? s.player1 : s.player2;
    }
  }

  Future<void> _showResult() async {
    await Future<void>.delayed(_resultDelay);
    if (!mounted) return;

    final result = _controller?.result;
    if (result == null) return;

    final action = await ResultSheet.show(
      context,
      result: result,
      playerName: _playerName,
    );
    if (!mounted) return;

    if (action == ResultAction.playAgain) {
      _resultShown = false;
      _controller?.restart();
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _confirmQuit() async {
    final s = AppStrings.of(context);
    final controller = _controller;
    if (controller == null) return;

    final wasPlaying = controller.phase != GamePhase.paused &&
        controller.phase != GamePhase.finished;
    if (wasPlaying) controller.pause();

    final shouldQuit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.quitTitle),
        content: Text(s.quitBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.quit),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (shouldQuit == true) {
      Navigator.of(context).pop();
    } else if (wasPlaying) {
      controller.resume();
    }
  }

  String _modeTitle(AppStrings s) {
    switch (widget.config.mode) {
      case GameMode.solo:
        return s.modeSolo;
      case GameMode.vsAi:
        return s.modeVsAi;
      case GameMode.pvp:
        return s.modePvp;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final scope = AppScope.of(context);
    final controller = _controller;

    if (controller == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final showTimer = scope.settings.value.showTimer;
    final isPaused = controller.phase == GamePhase.paused;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _confirmQuit();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(_modeTitle(s)),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: _confirmQuit,
          ),
          actions: <Widget>[
            IconButton(
              tooltip: s.paused,
              icon: const Icon(Icons.pause_rounded),
              onPressed: controller.phase == GamePhase.finished
                  ? null
                  : controller.pause,
            ),
          ],
        ),
        body: AppBackground(
          child: SafeArea(
            child: Stack(
              children: <Widget>[
                Column(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                      child: _Header(
                        controller: controller,
                        playerName: _playerName,
                        showTimer: showTimer,
                      ),
                    ),
                    _StatusLine(controller: controller),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        child: GameBoard(
                          cards: controller.cards,
                          boardSize: widget.config.boardSize,
                          justMatched: controller.justMatched,
                          matchOwners: <int?>[
                            for (final card in controller.cards) card.matchedBy,
                          ],
                          interactive: controller.acceptsInput,
                          onTap: controller.onCardTap,
                        ),
                      ),
                    ),
                  ],
                ),
                if (isPaused)
                  _PauseOverlay(
                    onResume: controller.resume,
                    onRestart: () {
                      _resultShown = false;
                      controller.restart();
                    },
                    onQuit: _confirmQuit,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Phần trên bàn cờ: thẻ điểm (chế độ đấu) hoặc thống kê (chơi đơn).
class _Header extends StatelessWidget {
  final GameController controller;
  final String Function(int index) playerName;
  final bool showTimer;

  const _Header({
    required this.controller,
    required this.playerName,
    required this.showTimer,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    if (!controller.config.mode.isTurnBased) {
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.center,
        children: <Widget>[
          if (showTimer)
            StatChip(
              icon: Icons.timer_outlined,
              label: s.time,
              value: formatDuration(controller.elapsed),
            ),
          StatChip(
            icon: Icons.touch_app_outlined,
            label: s.moves,
            value: '${controller.moves}',
          ),
          StatChip(
            icon: Icons.style_outlined,
            label: s.pairsLeft,
            value: '${controller.pairsLeft}',
          ),
        ],
      );
    }

    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            for (var i = 0; i < controller.scores.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: PlayerScoreCard(
                  name: playerName(i),
                  score: controller.scores[i],
                  isActive: controller.currentPlayer == i &&
                      controller.phase != GamePhase.finished,
                  accent:
                      AppTheme.playerColors[i % AppTheme.playerColors.length],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: <Widget>[
            if (showTimer)
              StatChip(
                icon: Icons.timer_outlined,
                label: s.time,
                value: formatDuration(controller.elapsed),
              ),
            StatChip(
              icon: Icons.style_outlined,
              label: s.pairsLeft,
              value: '${controller.pairsLeft}',
            ),
          ],
        ),
      ],
    );
  }
}

/// Dòng trạng thái: đếm ngược xem trước / AI đang nghĩ / tới lượt ai.
class _StatusLine extends StatelessWidget {
  final GameController controller;

  const _StatusLine({required this.controller});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);

    String? text;
    Color color = theme.colorScheme.primary;

    switch (controller.phase) {
      case GamePhase.peeking:
        text = '${s.memorize} ${controller.peekSecondsLeft}';
        color = AppTheme.sunGold;
        break;
      case GamePhase.aiTurn:
        text = s.aiThinking;
        color = AppTheme.playerColors[1];
        break;
      case GamePhase.idle:
      case GamePhase.awaitingSecond:
      case GamePhase.resolving:
        if (controller.config.mode.isTurnBased) {
          final index = controller.currentPlayer;
          color = AppTheme.playerColors[index % AppTheme.playerColors.length];
          text = controller.config.mode == GameMode.vsAi && index == 0
              ? s.yourTurn
              : s.turnOf(_nameFor(context, index));
        }
        break;
      case GamePhase.paused:
      case GamePhase.finished:
        text = null;
        break;
    }

    return SizedBox(
      height: 34,
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: text == null
              ? const SizedBox.shrink()
              : Text(
                  text,
                  key: ValueKey<String>(text),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }

  String _nameFor(BuildContext context, int index) {
    final s = AppStrings.of(context);
    switch (controller.config.mode) {
      case GameMode.solo:
        return s.you;
      case GameMode.vsAi:
        return index == 0 ? s.you : s.ai;
      case GameMode.pvp:
        return index == 0 ? s.player1 : s.player2;
    }
  }
}

/// Lớp phủ khi tạm dừng. Che luôn bàn cờ — nếu không, tạm dừng trở thành mẹo
/// gian lận: cứ pause rồi ngồi ngắm các lá đang ngửa bao lâu tuỳ thích.
class _PauseOverlay extends StatelessWidget {
  final VoidCallback onResume;
  final VoidCallback onRestart;
  final VoidCallback onQuit;

  const _PauseOverlay({
    required this.onResume,
    required this.onRestart,
    required this.onQuit,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);

    return Positioned.fill(
      child: ColoredBox(
        color: AppTheme.alpha(AppTheme.violetDeep, 0.92),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.pause_circle_filled_rounded,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  s.paused,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 28),
                NeonPrimaryButton(
                  label: s.resume,
                  icon: Icons.play_arrow_rounded,
                  onPressed: onResume,
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: onRestart,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(s.restart),
                ),
                TextButton.icon(
                  onPressed: onQuit,
                  icon: const Icon(Icons.logout_rounded),
                  label: Text(s.quit),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
