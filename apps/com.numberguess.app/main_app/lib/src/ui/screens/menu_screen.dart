import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../game/models/game_config.dart';
import '../../l10n/strings.dart';
import '../widgets/app_background.dart';
import '../widgets/game_setup_sheet.dart';
import 'game_screen.dart';
import 'settings_screen.dart';
import 'tutorial_screen.dart';

/// Sảnh chính.
///
/// Bố cục xoay quanh một khối số đang quay — nói ngay "game này là về con số"
/// mà không cần một dòng chữ nào. Chơi đơn là nút lớn nhất vì là chế độ chính,
/// chế độ 2 người là ô bên dưới, thành tích là ba ô số nhỏ. Hướng dẫn và Cài
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
                const _MysteryNumber(),
                const SizedBox(height: 18),
                _SoloHeroButton(
                  title: s.modeSolo,
                  subtitle: s.modeSoloHint,
                  onTap: () => _openMode(context, GameMode.solo),
                ),
                const SizedBox(height: 12),
                _SurvivalTile(
                  onTap: () => _openMode(context, GameMode.survival),
                ),
                const SizedBox(height: 12),
                _ModeTile(
                  title: s.modeDuel,
                  subtitle: s.modeDuelHint,
                  icon: Icons.groups_rounded,
                  accent: AppTheme.neonPink,
                  onTap: () => _openMode(context, GameMode.duel),
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

/// Khối "số bí mật" ở đầu sảnh: ba ô chữ số quay số như máy xổ, kèm mũi tên
/// cao hơn/thấp hơn nhấp nháy.
///
/// Timer chỉ chạy khi sảnh đang hiển thị (State bị dispose khi rời màn) và mỗi
/// nhịp chỉ vẽ lại bốn widget nhỏ, nên không đáng kể về pin.
class _MysteryNumber extends StatefulWidget {
  const _MysteryNumber();

  @override
  State<_MysteryNumber> createState() => _MysteryNumberState();
}

class _MysteryNumberState extends State<_MysteryNumber> {
  static const Duration _beat = Duration(milliseconds: 420);
  static const int _digits = 3;

  final math.Random _random = math.Random();
  Timer? _timer;
  List<int> _value = <int>[7, 4, 2];
  bool _up = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_beat, (_) {
      if (!mounted) return;
      setState(() {
        _value = <int>[for (var i = 0; i < _digits; i++) _random.nextInt(10)];
        _up = _random.nextBool();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final accent = _up ? AppTheme.sunGold : AppTheme.neonCyan;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            AppTheme.alpha(AppTheme.greenSoft, 0.28),
            AppTheme.alpha(AppTheme.greenSoft, 0.55),
          ],
        ),
        border: Border.all(
          color: AppTheme.panelBorder(theme.colorScheme, theme.brightness),
        ),
      ),
      child: Column(
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              for (var i = 0; i < _digits; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: 10),
                _DigitTile(digit: _value[i]),
              ],
            ],
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Row(
              key: ValueKey<bool>(_up),
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  _up
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  color: accent,
                  size: 20,
                ),
                const SizedBox(width: 6),
                Text(
                  _up ? s.hintHigher : s.hintLower,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: accent,
                    letterSpacing: 1,
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

class _DigitTile extends StatelessWidget {
  final int digit;

  const _DigitTile({required this.digit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 66,
      height: 84,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.alpha(AppTheme.greenDeep, 0.55),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.alpha(AppTheme.mint, 0.35)),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.4),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: Text(
          '$digit',
          key: ValueKey<int>(digit),
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w900,
            color: AppTheme.mint,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
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
                Icon(Icons.psychology_alt_rounded, size: 34, color: onPrimary),
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

/// Ô chế độ 2 người — nhẹ hơn nút chơi đơn nhưng vẫn rộng cả hàng, vì nó là
/// chế độ thứ hai chứ không phải một tuỳ chọn phụ.
/// Ô Sinh tồn. Khoe luôn kỷ lục chuỗi ngay trên ô: đó là con số duy nhất của
/// chế độ này, mà thanh thành tích bên dưới lại chỉ nói chuyện chơi đơn.
class _SurvivalTile extends StatelessWidget {
  final VoidCallback onTap;

  const _SurvivalTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final scope = AppScope.of(context);

    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[scope.stats, scope.settings]),
      builder: (context, _) {
        final settings = scope.settings.value;
        final best = scope.stats
            .recordFor(
              GameConfig(
                mode: GameMode.survival,
                range: settings.range,
                difficulty: settings.difficulty,
              ).recordKey,
            )
            .bestStreak;

        return _ModeTile(
          title: s.modeSurvival,
          subtitle: best == null
              ? s.modeSurvivalHint
              : '${s.bestStreak}: ${s.survivalRoundsCleared(best)}',
          icon: Icons.local_fire_department_rounded,
          accent: AppTheme.sunGold,
          onTap: onTap,
        );
      },
    );
  }
}

/// Ô chế độ phụ, xếp dưới nút Chơi một mình. Dùng chung cho mọi chế độ không
/// phải chế độ chính — khác nhau mỗi màu nhấn và biểu tượng.
class _ModeTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  const _ModeTile({
    required this.title,
    required this.subtitle,
    required this.icon,
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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border:
                  Border.all(color: AppTheme.alpha(accent, 0.6), width: 1.6),
            ),
            child: Row(
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
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppTheme.alpha(
                              theme.colorScheme.onSurface, 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppTheme.alpha(theme.colorScheme.onSurface, 0.4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ba ô thành tích xếp ngang: số ván, tỉ lệ đoán ra, kỷ lục của cấu hình đang
/// chọn.
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
            range: settings.range,
            difficulty: settings.difficulty,
          ).recordKey,
        );
        final recordHint = '${s.rangeSpan(settings.range)} · '
            '${s.difficultyName(settings.difficulty)}';

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
                  icon: Icons.check_circle_outline_rounded,
                  label: s.solvedRatio,
                  value: '${stats.solved}/${stats.solved + stats.unsolved}',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatTile(
                  icon: Icons.emoji_events_outlined,
                  label: '${s.bestGuesses}\n$recordHint',
                  value: record.bestGuesses == null
                      ? '—'
                      : '${record.bestGuesses}',
                  hint: record.bestTimeMs == null
                      ? null
                      : formatMillis(record.bestTimeMs),
                  highlight: record.bestGuesses != null,
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
  final String? hint;
  final bool highlight;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.hint,
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text(
                  value,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: highlight ? theme.colorScheme.primary : null,
                  ),
                ),
                if (hint != null) ...<Widget>[
                  const SizedBox(width: 4),
                  Text(
                    hint!,
                    style: theme.textTheme.labelSmall?.copyWith(color: muted),
                  ),
                ],
              ],
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
