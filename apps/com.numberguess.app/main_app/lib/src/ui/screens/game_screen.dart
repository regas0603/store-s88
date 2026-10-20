import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../game/engine/guess_engine.dart';
import '../../game/game_controller.dart';
import '../../game/models/game_config.dart';
import '../../l10n/strings.dart';
import '../widgets/app_background.dart';
import '../widgets/hint_panel.dart';
import '../widgets/neon_button.dart';
import '../widgets/number_pad.dart';
import '../widgets/result_sheet.dart';
import '../widgets/score_panel.dart';

/// Màn chơi chính, dùng chung cho cả hai chế độ.
///
/// Không tách thành hai màn riêng: chế độ 2 người chỉ thêm hai giai đoạn
/// (nhập số bí mật, chuyền máy) bọc quanh đúng cái vòng đoán số của chơi đơn.
/// Hai bản sao sẽ lệch nhau ngay ở lần sửa lỗi đầu tiên.
class GameScreen extends StatefulWidget {
  final GameConfig config;

  const GameScreen({required this.config, super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  /// Chờ một nhịp sau lần đoán cuối rồi mới hiện kết quả: người chơi cần kịp
  /// đọc dòng "CHÍNH XÁC!", và đến lúc đó thống kê cũng đã ghi xong nên cờ
  /// "Kỷ lục mới" hiển thị đúng.
  static const Duration _resultDelay = Duration(milliseconds: 900);

  GameController? _controller;
  bool _resultShown = false;

  /// Số đang gõ dở trên bàn phím.
  String _input = '';

  /// Người đặt số bí mật đang bật "xem lại" để kiểm tra mình gõ đúng chưa.
  bool _revealSecret = false;

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
    // setState() trong lúc build frame đầu tiên — Flutter assert ngay.
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

  int get _maxDigits => '${widget.config.range.max}'.length;

  String _playerName(int index) {
    final s = AppStrings.of(context);
    if (widget.config.mode == GameMode.solo) return s.you;
    return index == 0 ? s.player1 : s.player2;
  }

  // ------------------------------------------------------------ bàn phím số

  void _onDigit(int digit) {
    // Chặn số 0 đứng đầu: mọi khoảng đều bắt đầu từ 1 nên "05" chỉ là cách gõ
    // rối rắm của "5", và nó ăn mất một ô chữ số.
    if (_input.isEmpty && digit == 0) return;
    if (_input.length >= _maxDigits) return;
    AppScope.of(context).sound.tapFeedback();
    setState(() => _input += '$digit');
  }

  void _onBackspace() {
    if (_input.isEmpty) return;
    AppScope.of(context).sound.tapFeedback();
    setState(() => _input = _input.substring(0, _input.length - 1));
  }

  void _onClear() {
    if (_input.isEmpty) return;
    AppScope.of(context).sound.tapFeedback();
    setState(() => _input = '');
  }

  void _submitGuess() {
    final controller = _controller;
    final value = int.tryParse(_input);
    if (controller == null || value == null) return;

    final outcome = controller.submitGuess(value);
    // Giữ lại số vừa gõ khi nó bị từ chối (ngoài khoảng / trùng) để người chơi
    // chỉ phải sửa một chữ số thay vì gõ lại từ đầu.
    final keepInput = outcome == GuessOutcome.outOfRange ||
        outcome == GuessOutcome.duplicate;
    if (!keepInput) setState(() => _input = '');
  }

  void _confirmSecret() {
    final controller = _controller;
    final value = int.tryParse(_input);
    if (controller == null || value == null) return;
    if (!controller.confirmSecret(value)) return;
    setState(() {
      _input = '';
      _revealSecret = false;
    });
  }

  // ------------------------------------------------------------------ điều hướng

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
      setState(() {
        _input = '';
        _revealSecret = false;
      });
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

  String _modeTitle(AppStrings s) => switch (widget.config.mode) {
        GameMode.solo => s.modeSolo,
        GameMode.survival => s.modeSurvival,
        GameMode.duel => s.modeDuel,
      };

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final controller = _controller;

    if (controller == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

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
                _GuessStage(
                  controller: controller,
                  input: _input,
                  maxDigits: _maxDigits,
                  playerName: _playerName,
                  showTimer: AppScope.of(context).settings.value.showTimer,
                  showRangeHint:
                      AppScope.of(context).settings.value.showRangeHint,
                  onDigit: _onDigit,
                  onBackspace: _onBackspace,
                  onClear: _onClear,
                  onSubmit: _submitGuess,
                ),
                if (controller.phase == GamePhase.settingSecret)
                  _SecretStage(
                    controller: controller,
                    input: _input,
                    maxDigits: _maxDigits,
                    revealed: _revealSecret,
                    playerName: _playerName,
                    onToggleReveal: () =>
                        setState(() => _revealSecret = !_revealSecret),
                    onDigit: _onDigit,
                    onBackspace: _onBackspace,
                    onClear: _onClear,
                    onSubmit: _confirmSecret,
                  ),
                if (controller.phase == GamePhase.handoff)
                  _HandoffOverlay(
                    controller: controller,
                    playerName: _playerName,
                  ),
                if (controller.phase == GamePhase.roundCleared)
                  _RoundClearedOverlay(controller: controller),
                if (controller.phase == GamePhase.paused)
                  _PauseOverlay(
                    onResume: controller.resume,
                    onRestart: () {
                      _resultShown = false;
                      setState(() {
                        _input = '';
                        _revealSecret = false;
                      });
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

/// Màn đoán số: thống kê, gợi ý, lịch sử, ô số và bàn phím.
class _GuessStage extends StatelessWidget {
  final GameController controller;
  final String input;
  final int maxDigits;
  final String Function(int index) playerName;
  final bool showTimer;
  final bool showRangeHint;
  final ValueChanged<int> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onSubmit;

  const _GuessStage({
    required this.controller,
    required this.input,
    required this.maxDigits,
    required this.playerName,
    required this.showTimer,
    required this.showRangeHint,
    required this.onDigit,
    required this.onBackspace,
    required this.onClear,
    required this.onSubmit,
  });

  String? _errorText(AppStrings s) {
    switch (controller.lastRejection) {
      case GuessOutcome.outOfRange:
        return s.outOfRangeWarning;
      case GuessOutcome.duplicate:
        return s.duplicateWarning;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final config = controller.config;
    final isPlaying = controller.phase == GamePhase.playing;

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Column(
            children: <Widget>[
              if (config.mode.isDuel) ...<Widget>[
                Text(
                  s.turnOf(playerName(controller.guesser)),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.playerColors[
                        controller.guesser % AppTheme.playerColors.length],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Wrap(
                spacing: 10,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: <Widget>[
                  if (config.mode.isSurvival)
                    StatChip(
                      icon: Icons.local_fire_department_rounded,
                      label: s.modeSurvival,
                      value: s.survivalRound(controller.survivalRound),
                    ),
                  StatChip(
                    icon: Icons.tag_rounded,
                    label: s.rangeLabel,
                    value: '${config.range.min}–${config.range.max}',
                  ),
                  StatChip(
                    icon: Icons.format_list_numbered_rounded,
                    label: s.guessesLeft,
                    // Ngân sách đọc từ controller chứ không từ config: Sinh
                    // tồn đổi con số này sau mỗi vòng.
                    value: '${controller.guessesLeft}/${controller.guessBudget}',
                  ),
                  if (showTimer)
                    StatChip(
                      icon: Icons.timer_outlined,
                      label: s.time,
                      value: formatDuration(controller.legElapsed),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          // Căn giữa theo chiều dọc: khối gợi ý phải nằm trong tầm mắt giữa
          // thanh thống kê và bàn phím, chứ không dính lên sát mép trên.
          // Vẫn cuộn được khi chữ phóng to hoặc lịch sử dài.
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    HintPanel(
                      guess: controller.lastGuess,
                      bounds: showRangeHint
                          ? (controller.lowBound, controller.highBound)
                          : null,
                    ),
                    const SizedBox(height: 14),
                    GuessHistoryStrip(guesses: controller.history),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(
            children: <Widget>[
              NumberDisplay(
                value: input,
                placeholder: s.yourGuess,
                error: _errorText(s),
              ),
              const SizedBox(height: 12),
              NumberPad(
                maxDigits: maxDigits,
                submitLabel: s.submitGuess,
                enabled: isPlaying,
                onDigit: onDigit,
                onBackspace: onBackspace,
                onClear: onClear,
                onSubmit: input.isEmpty ? null : onSubmit,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Màn nhập số bí mật ở chế độ 2 người. Che kín màn chơi phía dưới — nếu
/// không, người đặt số nhìn thấy luôn lịch sử đoán của lượt trước.
class _SecretStage extends StatelessWidget {
  final GameController controller;
  final String input;
  final int maxDigits;
  final bool revealed;
  final String Function(int index) playerName;
  final VoidCallback onToggleReveal;
  final ValueChanged<int> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onSubmit;

  const _SecretStage({
    required this.controller,
    required this.input,
    required this.maxDigits,
    required this.revealed,
    required this.playerName,
    required this.onToggleReveal,
    required this.onDigit,
    required this.onBackspace,
    required this.onClear,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final range = controller.config.range;
    final setter = controller.setter;
    final accent =
        AppTheme.playerColors[setter % AppTheme.playerColors.length];

    final value = int.tryParse(input);
    final inRange = value != null && value >= range.min && value <= range.max;

    return Positioned.fill(
      // Nền ĐỤC hoàn toàn, không phải màu mờ: người đặt số tuyệt đối không
      // được nhìn thấy lịch sử đoán của lượt trước nằm dưới.
      child: ColoredBox(
        color: theme.brightness == Brightness.dark
            ? AppTheme.greenDeep
            : AppTheme.lightBackdrop.first,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              children: <Widget>[
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: <Widget>[
                        Icon(Icons.visibility_off_rounded,
                            size: 40, color: accent),
                        const SizedBox(height: 10),
                        Text(
                          s.setSecretTitle(playerName(setter)),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: accent,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          s.setSecretBody(
                            range.min,
                            range.max,
                            playerName(controller.guesser),
                          ),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppTheme.alpha(
                                theme.colorScheme.onSurface, 0.7),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          s.legOf(controller.config.mode.isDuel &&
                                  controller.guesser == 1
                              ? 1
                              : 2),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: AppTheme.alpha(
                                theme.colorScheme.onSurface, 0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                NumberDisplay(
                  value: input,
                  placeholder: '${range.min}–${range.max}',
                  obscured: !revealed,
                  error: input.isNotEmpty && !inRange
                      ? s.outOfRangeWarning
                      : null,
                ),
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: input.isEmpty ? null : onToggleReveal,
                  icon: Icon(
                    revealed
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 18,
                  ),
                  label: Text(revealed ? s.secretHidden : s.revealSecret),
                ),
                const SizedBox(height: 6),
                NumberPad(
                  maxDigits: maxDigits,
                  submitLabel: s.confirm,
                  onDigit: onDigit,
                  onBackspace: onBackspace,
                  onClear: onClear,
                  onSubmit: inRange ? onSubmit : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Đếm ngược chuyền máy giữa hai người.
class _HandoffOverlay extends StatelessWidget {
  final GameController controller;
  final String Function(int index) playerName;

  const _HandoffOverlay({required this.controller, required this.playerName});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final guesser = controller.guesser;
    final accent =
        AppTheme.playerColors[guesser % AppTheme.playerColors.length];

    return Positioned.fill(
      child: ColoredBox(
        color: AppTheme.greenDeep,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.swap_horiz_rounded, size: 56, color: accent),
                const SizedBox(height: 16),
                Text(
                  s.handoffTitle(playerName(guesser)),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  s.handoffBody,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.alpha(Colors.white, 0.75),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  '${controller.handoffSecondsLeft}',
                  style: theme.textTheme.displayMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 24),
                NeonPrimaryButton(
                  label: s.handoffSkip,
                  icon: Icons.play_arrow_rounded,
                  onPressed: controller.skipHandoff,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Nhịp nghỉ giữa hai vòng Sinh tồn.
///
/// Che kín màn chơi để người chơi không kịp nhìn thấy lịch sử của vòng vừa rồi
/// trộn lẫn với vòng mới. Tự biến mất sau [GameController.roundBreak], hoặc
/// sớm hơn nếu người chơi bấm nút.
class _RoundClearedOverlay extends StatelessWidget {
  final GameController controller;

  const _RoundClearedOverlay({required this.controller});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final config = controller.config;
    final nextRound = controller.survivalRound + 1;
    final nextBudget = config.survivalGuessesFor(nextRound);

    return Positioned.fill(
      child: ColoredBox(
        color: AppTheme.greenDeep,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.local_fire_department_rounded,
                  size: 56,
                  color: AppTheme.sunGold,
                ),
                const SizedBox(height: 16),
                Text(
                  s.survivalCleared,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  s.survivalRoundsCleared(controller.survivedRounds),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.alpha(Colors.white, 0.75),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  s.survivalNextRound(nextRound, nextBudget),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: AppTheme.sunGold,
                  ),
                ),
                // Chỉ báo đúng ở vòng chạm sàn: nhắc mỗi vòng sau đó thì thành
                // nhiễu, mà nhắc sớm thì người chơi chưa cần biết.
                if (nextRound == config.survivalFloorRound) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    s.survivalAtFloor,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.alpha(Colors.white, 0.7),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                NeonPrimaryButton(
                  label: s.survivalContinue,
                  icon: Icons.play_arrow_rounded,
                  onPressed: controller.skipRoundBreak,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lớp phủ khi tạm dừng. Che ĐỤC luôn màn chơi: nếu không, tạm dừng thành chỗ
/// ngồi ngắm lịch sử đoán mà đồng hồ vẫn đứng yên.
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
        color: AppTheme.greenDeep,
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
