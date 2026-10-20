import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../game/models/game_config.dart';
import '../../l10n/strings.dart';
import '../widgets/app_background.dart';
import '../widgets/game_setup_sheet.dart';
import '../widgets/neon_button.dart';
import 'game_screen.dart';
import 'settings_screen.dart';
import 'tutorial_screen.dart';

/// Sảnh chính: ba chế độ chơi, lối vào Cài đặt và Hướng dẫn, thành tích tóm tắt.
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

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final scope = AppScope.of(context);

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const SizedBox(height: 18),
                Row(
                  children: <Widget>[
                    SizedBox(
                      width: 54,
                      height: 54,
                      child: Image.asset(package: 'main_app_package', 'assets/branding/app_icon.png'),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            s.appName,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            s.tagline,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppTheme.alpha(
                                theme.colorScheme.onSurface,
                                0.65,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: s.settings,
                      onPressed: () {
                        scope.sound.tapFeedback();
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const SettingsScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.settings_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: <Widget>[
                      NeonMenuButton(
                        icon: Icons.person_rounded,
                        title: s.modeSolo,
                        subtitle: s.modeSoloHint,
                        accent: AppTheme.neonCyan,
                        onTap: () => _openMode(context, GameMode.solo),
                      ),
                      const SizedBox(height: 14),
                      NeonMenuButton(
                        icon: Icons.smart_toy_rounded,
                        title: s.modeVsAi,
                        subtitle: s.modeVsAiHint,
                        accent: AppTheme.sunGold,
                        onTap: () => _openMode(context, GameMode.vsAi),
                      ),
                      const SizedBox(height: 14),
                      NeonMenuButton(
                        icon: Icons.groups_rounded,
                        title: s.modePvp,
                        subtitle: s.modePvpHint,
                        accent: AppTheme.neonPink,
                        onTap: () => _openMode(context, GameMode.pvp),
                      ),
                      const SizedBox(height: 22),
                      const _StatsCard(),
                      const SizedBox(height: 14),
                      Center(
                        child: TextButton.icon(
                          onPressed: () {
                            scope.sound.tapFeedback();
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const TutorialScreen(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.help_outline_rounded),
                          label: Text(s.howToPlay),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
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

/// Tóm tắt thành tích: số ván đã chơi, tỉ số với AI, kỷ lục chơi đơn hiện tại.
class _StatsCard extends StatelessWidget {
  const _StatsCard();

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final scope = AppScope.of(context);

    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[scope.stats, scope.settings]),
      builder: (context, _) {
        final stats = scope.stats;
        final boardSize = scope.settings.value.boardSize;
        final record = stats.recordFor(
          GameConfig(mode: GameMode.solo, boardSize: boardSize).recordKey,
        );

        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppTheme.panelColor(theme.colorScheme, theme.brightness),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: AppTheme.panelBorder(theme.colorScheme, theme.brightness),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    s.gamesPlayed,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppTheme.alpha(theme.colorScheme.onSurface, 0.7),
                    ),
                  ),
                  Text(
                    '${stats.gamesPlayed}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    s.vsAiRecord,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppTheme.alpha(theme.colorScheme.onSurface, 0.7),
                    ),
                  ),
                  Text(
                    '${stats.aiWins} · ${stats.aiDraws} · ${stats.aiLosses}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '${s.bestTime} · ${s.boardSizeName(boardSize)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppTheme.alpha(theme.colorScheme.onSurface, 0.7),
                      ),
                    ),
                  ),
                  Text(
                    record.bestTimeMs == null
                        ? s.noRecordYet
                        : formatMillis(record.bestTimeMs),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: record.bestTimeMs == null
                          ? AppTheme.alpha(theme.colorScheme.onSurface, 0.5)
                          : theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
