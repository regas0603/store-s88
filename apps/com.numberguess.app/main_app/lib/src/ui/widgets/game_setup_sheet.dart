import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/theme.dart';
import '../../game/models/game_config.dart';
import '../../l10n/strings.dart';
import 'neon_button.dart';

/// Bảng thiết lập nhanh trước khi vào ván.
///
/// Lựa chọn ở đây được ghi luôn vào Cài đặt, nên lần sau mở ra đã đúng thói
/// quen của người chơi — không bắt họ chỉnh lại mỗi ván.
class GameSetupSheet extends StatefulWidget {
  final GameMode mode;

  const GameSetupSheet({required this.mode, super.key});

  static Future<GameConfig?> show(BuildContext context, GameMode mode) {
    return showModalBottomSheet<GameConfig>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GameSetupSheet(mode: mode),
    );
  }

  @override
  State<GameSetupSheet> createState() => _GameSetupSheetState();
}

class _GameSetupSheetState extends State<GameSetupSheet> {
  late GuessRange _range;
  late GuessDifficulty _difficulty;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final settings = AppScope.of(context).settings.value;
    _range = settings.range;
    _difficulty = settings.difficulty;
  }

  Future<void> _start() async {
    final scope = AppScope.of(context);
    scope.sound.tapFeedback();

    await scope.settings.setRange(_range);
    await scope.settings.setDifficulty(_difficulty);
    if (!mounted) return;

    Navigator.of(context).pop(
      GameConfig(
        mode: widget.mode,
        range: _range,
        difficulty: _difficulty,
        handoffSeconds: scope.settings.value.handoffSeconds,
      ),
    );
  }

  String _modeTitle(AppStrings s) => switch (widget.mode) {
        GameMode.solo => s.modeSolo,
        GameMode.survival => s.modeSurvival,
        GameMode.duel => s.modeDuel,
      };

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.sheetDark : Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: AppTheme.panelBorder(theme.colorScheme, theme.brightness),
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.alpha(theme.colorScheme.onSurface, 0.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _modeTitle(s),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 20),

              _SectionLabel(s.rangeLabel),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final range in GuessRange.values)
                    ChoiceChip(
                      selected: _range == range,
                      onSelected: (_) => setState(() => _range = range),
                      label: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(s.rangeName(range)),
                          Text(
                            s.rangeSpan(range),
                            style: theme.textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 20),
              _SectionLabel(s.difficultyLabel),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final level in GuessDifficulty.values)
                    ChoiceChip(
                      selected: _difficulty == level,
                      onSelected: (_) => setState(() => _difficulty = level),
                      label: Text(s.difficultyName(level)),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                s.difficultyDetail(_difficulty, _range),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppTheme.alpha(theme.colorScheme.onSurface, 0.65),
                ),
              ),

              // Sinh tồn diễn giải độ khó khác hẳn: con số ở trên là ngân sách
              // của VÒNG ĐẦU, không phải của cả ván. Nói rõ ngay đây, trước
              // khi người chơi bấm Bắt đầu.
              if (widget.mode.isSurvival) ...<Widget>[
                const SizedBox(height: 10),
                _SurvivalNote(range: _range, difficulty: _difficulty),
              ],

              const SizedBox(height: 26),
              NeonPrimaryButton(
                label: s.start,
                icon: Icons.play_arrow_rounded,
                onPressed: _start,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Giải thích luật Sinh tồn bằng chính các con số của cấu hình đang chọn.
class _SurvivalNote extends StatelessWidget {
  final GuessRange range;
  final GuessDifficulty difficulty;

  const _SurvivalNote({required this.range, required this.difficulty});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final config = GameConfig(
      mode: GameMode.survival,
      range: range,
      difficulty: difficulty,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.alpha(AppTheme.sunGold, 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.alpha(AppTheme.sunGold, 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.local_fire_department_rounded,
            size: 20,
            color: AppTheme.sunGold,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              s.survivalSetupDetail(
                difficulty.maxGuessesFor(range),
                range.minHalvingGuesses,
                config.survivalFloorRound,
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppTheme.alpha(theme.colorScheme.onSurface, 0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        letterSpacing: 1.1,
        fontWeight: FontWeight.w700,
        color: AppTheme.alpha(theme.colorScheme.onSurface, 0.6),
      ),
    );
  }
}
