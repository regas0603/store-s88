import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../game/models/game_config.dart';
import '../../l10n/strings.dart';
import '../../services/sound_service.dart';
import '../widgets/app_background.dart';
import '../widgets/game_setup_sheet.dart';
import '../widgets/mole_hole_view.dart';
import 'game_screen.dart';
import 'settings_screen.dart';
import 'tutorial_screen.dart';

/// Sảnh chính.
///
/// Bố cục xoay quanh "sân chơi": một dải hang có chuột chũi trồi lên thật (chạm
/// được) ở trên cùng, chơi đơn là nút lớn nhất vì là chế độ chính, hai chế độ
/// đấu là hai ô vuông cạnh nhau, thành tích là ba ô số nhỏ. Hướng dẫn và Cài
/// đặt lên thanh trên cùng cho gọn.
class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  Future<void> _openMode(BuildContext context, GameMode mode) async {
    final scope = AppScope.of(context);
    scope.sound.tapFeedback();

    final config = await GameSetupSheet.show(context, mode);
    if (config == null || !context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => GameScreen(config: config)),
    );
  }

  void _push(BuildContext context, Widget screen) {
    AppScope.of(context).sound.tapFeedback();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: Image.asset(package: 'main_app_package', 'assets/branding/app_icon.png'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s.appName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    _RoundIconButton(
                      icon: Icons.help_outline_rounded,
                      tooltip: s.howToPlay,
                      onPressed: () => _push(context, const TutorialScreen()),
                    ),
                    const SizedBox(width: 8),
                    _RoundIconButton(
                      icon: Icons.settings_rounded,
                      tooltip: s.settings,
                      onPressed: () => _push(context, const SettingsScreen()),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const _MoleYard(),
                const SizedBox(height: 18),
                _SoloHeroButton(
                  title: s.modeSolo,
                  subtitle: s.modeSoloHint,
                  onTap: () => _openMode(context, GameMode.solo),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _ModeTile(
                        icon: Icons.smart_toy_rounded,
                        title: s.modeVsAi,
                        subtitle: s.modeVsAiHint,
                        accent: AppTheme.sunGold,
                        onTap: () => _openMode(context, GameMode.vsAi),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ModeTile(
                        icon: Icons.groups_rounded,
                        title: s.modePvp,
                        subtitle: s.modePvpHint,
                        accent: AppTheme.neonPink,
                        onTap: () => _openMode(context, GameMode.pvp),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const _StatsStrip(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppTheme.panelColor(theme.colorScheme, theme.brightness),
      shape: CircleBorder(
        side: BorderSide(
          color: AppTheme.panelBorder(theme.colorScheme, theme.brightness),
        ),
      ),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, color: theme.colorScheme.primary),
      ),
    );
  }
}

/// Dải "sân cỏ" với ba hang, chuột chũi thay nhau trồi lên. Chạm trúng thì nó
/// choáng như trong ván thật — một lời mời chơi rõ hơn mọi dòng chữ.
///
/// Timer chỉ chạy khi sảnh đang hiển thị (State bị dispose khi rời màn) và mỗi
/// nhịp chỉ vẽ lại ba ô, nên không đáng kể về pin.
class _MoleYard extends StatefulWidget {
  const _MoleYard();

  @override
  State<_MoleYard> createState() => _MoleYardState();
}

class _MoleYardState extends State<_MoleYard> {
  static const int _holes = 3;
  static const Duration _beat = Duration(milliseconds: 950);

  final math.Random _random = math.Random();
  Timer? _timer;
  int _up = 1;
  int _moleId = 0;
  bool _dazed = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_beat, (_) => _popNext());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _popNext() {
    if (!mounted) return;
    setState(() {
      // Không trồi lại đúng hang cũ — trông như đứng im.
      _up = (_up + 1 + _random.nextInt(_holes - 1)) % _holes;
      _moleId++;
      _dazed = false;
    });
  }

  void _onTap(int index) {
    if (index != _up || _dazed) return;
    AppScope.of(context).sound
      ..play(Sfx.match)
      ..tapFeedback();
    setState(() => _dazed = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            AppTheme.alpha(AppTheme.greenSoft, 0.35),
            AppTheme.alpha(AppTheme.greenSoft, 0.65),
          ],
        ),
        border: Border.all(
          color: AppTheme.panelBorder(theme.colorScheme, theme.brightness),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cell = math.min(
            110.0,
            (constraints.maxWidth - 8 * (_holes - 1)) / _holes,
          );
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              for (var i = 0; i < _holes; i++)
                MoleHoleView(
                  width: cell,
                  height: cell,
                  raised: i == _up,
                  dazed: i == _up && _dazed,
                  moleId: _moleId,
                  hitAccent: AppTheme.sunGold,
                  onTap: () => _onTap(i),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Nút chơi đơn — lớn nhất màn, nền đặc màu chủ đạo.
class _SoloHeroButton extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SoloHeroButton({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final onPrimary = scheme.onPrimary;

    return Semantics(
      button: true,
      label: '$title. $subtitle',
      child: Material(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(24),
        elevation: 0,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
            child: Row(
              children: <Widget>[
                Icon(Icons.gavel_rounded, size: 34, color: onPrimary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: onPrimary,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppTheme.alpha(onPrimary, 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.alpha(onPrimary, 0.18),
                  ),
                  child: Icon(Icons.play_arrow_rounded,
                      color: onPrimary, size: 30),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ô vuông cho chế độ đấu, đặt hai ô cạnh nhau.
class _ModeTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  const _ModeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      label: '$title. $subtitle',
      child: Material(
        color: AppTheme.panelColor(theme.colorScheme, theme.brightness),
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border:
                  Border.all(color: AppTheme.alpha(accent, 0.6), width: 1.6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppTheme.alpha(accent, 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: accent, size: 24),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.alpha(theme.colorScheme.onSurface, 0.65),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ba ô thành tích xếp ngang: số ván, tỉ số với AI, kỷ lục chơi đơn hiện tại.
class _StatsStrip extends StatelessWidget {
  const _StatsStrip();

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final scope = AppScope.of(context);

    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[scope.stats, scope.settings]),
      builder: (context, _) {
        final stats = scope.stats;
        final settings = scope.settings.value;
        final record = stats.recordFor(
          GameConfig(
            mode: GameMode.solo,
            boardSize: settings.boardSize,
            boardDifficulty: settings.boardDifficulty,
          ).recordKey,
        );
        final recordHint = settings.boardDifficulty == BoardDifficulty.hard
            ? '${s.boardSizeName(settings.boardSize)} · '
                '${s.boardDifficultyName(BoardDifficulty.hard)}'
            : s.boardSizeName(settings.boardSize);

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: _StatTile(
                  icon: Icons.sports_esports_rounded,
                  label: s.gamesPlayed,
                  value: '${stats.gamesPlayed}',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatTile(
                  icon: Icons.smart_toy_outlined,
                  label: s.vsAiRecord,
                  value: '${stats.aiWins}-${stats.aiDraws}-${stats.aiLosses}',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatTile(
                  icon: Icons.emoji_events_outlined,
                  label: '${s.bestTime}\n$recordHint',
                  value: record.bestTimeMs == null
                      ? '—'
                      : formatMillis(record.bestTimeMs),
                  highlight: record.bestTimeMs != null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool highlight;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = AppTheme.alpha(theme.colorScheme.onSurface, 0.65);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppTheme.panelColor(theme.colorScheme, theme.brightness),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.panelBorder(theme.colorScheme, theme.brightness),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
                color: highlight ? theme.colorScheme.primary : null,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}
