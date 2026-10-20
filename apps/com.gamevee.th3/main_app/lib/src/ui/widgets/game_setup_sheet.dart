import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/theme.dart';
import '../../game/models/card_icon.dart';
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
  late BoardSize _boardSize;
  late AiDifficulty _difficulty;
  late CardCategory? _category;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final settings = AppScope.of(context).settings.value;
    _boardSize = settings.boardSize;
    _difficulty = settings.aiDifficulty;
    _category = settings.cardCategory;
  }

  Future<void> _start() async {
    final scope = AppScope.of(context);
    scope.sound.tapFeedback();

    await scope.settings.setBoardSize(_boardSize);
    await scope.settings.setCardCategory(_category);
    if (widget.mode == GameMode.vsAi) {
      await scope.settings.setAiDifficulty(_difficulty);
    }
    if (!mounted) return;

    Navigator.of(context).pop(
      GameConfig(
        mode: widget.mode,
        boardSize: _boardSize,
        aiDifficulty: _difficulty,
        category: _category,
        peekSeconds: scope.settings.value.peekSeconds,
      ),
    );
  }

  String _modeTitle(AppStrings s) {
    switch (widget.mode) {
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF241B52) : Colors.white,
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

              _SectionLabel(s.boardSizeLabel),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final size in BoardSize.values)
                    ChoiceChip(
                      selected: _boardSize == size,
                      onSelected: (_) => setState(() => _boardSize = size),
                      label: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(s.boardSizeName(size)),
                          Text(
                            s.boardSizeDetail(size),
                            style: theme.textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                ],
              ),

              if (widget.mode == GameMode.vsAi) ...<Widget>[
                const SizedBox(height: 20),
                _SectionLabel(s.difficultyLabel),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final level in AiDifficulty.values)
                      ChoiceChip(
                        selected: _difficulty == level,
                        onSelected: (_) => setState(() => _difficulty = level),
                        label: Text(s.difficultyName(level)),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  s.difficultyDetail(_difficulty),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.alpha(theme.colorScheme.onSurface, 0.65),
                  ),
                ),
              ],

              const SizedBox(height: 20),
              _SectionLabel(s.cardThemeLabel),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  ChoiceChip(
                    selected: _category == null,
                    onSelected: (_) => setState(() => _category = null),
                    label: Text(s.allThemes),
                  ),
                  for (final category in CardCategory.values)
                    ChoiceChip(
                      selected: _category == category,
                      onSelected: (_) => setState(() => _category = category),
                      label: Text(s.categoryName(category)),
                    ),
                ],
              ),
              if (_category != null &&
                  CardIcons.availableCount(_category) < _boardSize.pairs)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    s.isEnglish
                        ? 'This set has fewer icons than the board needs — the rest will be mixed in from other sets.'
                        : 'Chủ đề này ít icon hơn số cặp của bàn — phần thiếu sẽ được bù từ chủ đề khác.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.alpha(theme.colorScheme.onSurface, 0.65),
                    ),
                  ),
                ),

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
