import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../game/game_controller.dart';
import '../../game/models/game_config.dart';
import '../../l10n/strings.dart';
import 'neon_button.dart';

/// Người chơi chọn gì sau khi kết thúc ván.
enum ResultAction { playAgain, backToMenu }

/// Bảng kết quả cuối ván.
///
/// Dùng bottom sheet không đóng được bằng cách vuốt/chạm ra ngoài: người chơi
/// phải chọn rõ ràng chơi tiếp hay về sảnh, tránh trường hợp lỡ tay đóng rồi
/// nhìn vào một màn hình đã xong mà không biết làm gì.
class ResultSheet extends StatelessWidget {
  final GameResult result;
  final String Function(int playerIndex) playerName;

  const ResultSheet({
    required this.result,
    required this.playerName,
    super.key,
  });

  static Future<ResultAction?> show(
    BuildContext context, {
    required GameResult result,
    required String Function(int playerIndex) playerName,
  }) {
    return showModalBottomSheet<ResultAction>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ResultSheet(result: result, playerName: playerName),
    );
  }

  String _title(AppStrings s) {
    switch (result.mode) {
      case GameMode.solo:
        return result.soloSolved ? s.resultSolved : s.resultFailed;
      case GameMode.survival:
        return s.survivalResultTitle;
      case GameMode.duel:
        if (result.isDraw) return s.resultDraw;
        return s.resultPlayerWins(playerName(result.winners.first));
    }
  }

  IconData _icon() {
    switch (result.mode) {
      case GameMode.solo:
        return result.soloSolved
            ? Icons.celebration_rounded
            : Icons.sentiment_dissatisfied_rounded;
      case GameMode.survival:
        // Qua được vòng nào cũng là thành tích, nên không dùng mặt buồn.
        return result.survivedRounds > 0
            ? Icons.local_fire_department_rounded
            : Icons.sentiment_dissatisfied_rounded;
      case GameMode.duel:
        return result.isDraw
            ? Icons.handshake_rounded
            : Icons.emoji_events_rounded;
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
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
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
            children: <Widget>[
              Icon(_icon(), size: 48, color: theme.colorScheme.primary),
              const SizedBox(height: 10),
              Text(
                _title(s),
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (result.isNewRecord) ...<Widget>[
                const SizedBox(height: 10),
                const _RecordBadge(),
              ],
              const SizedBox(height: 18),
              switch (result.mode) {
                GameMode.solo => _SoloSummary(result: result),
                GameMode.survival => _SurvivalSummary(result: result),
                GameMode.duel =>
                  _DuelSummary(result: result, playerName: playerName),
              },
              const SizedBox(height: 24),
              NeonPrimaryButton(
                label: s.playAgain,
                icon: Icons.refresh_rounded,
                onPressed: () =>
                    Navigator.of(context).pop(ResultAction.playAgain),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () =>
                    Navigator.of(context).pop(ResultAction.backToMenu),
                icon: const Icon(Icons.home_rounded),
                label: Text(s.backToMenu),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordBadge extends StatelessWidget {
  const _RecordBadge();

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.alpha(AppTheme.sunGold, 0.20),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.alpha(AppTheme.sunGold, 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.star_rounded, size: 18, color: AppTheme.sunGold),
          const SizedBox(width: 6),
          Text(
            s.newRecord,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SoloSummary extends StatelessWidget {
  final GameResult result;

  const _SoloSummary({required this.result});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final round = result.rounds.first;

    return Column(
      children: <Widget>[
        Text(
          s.secretWas(round.secret),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            _Metric(label: s.time, value: formatDuration(result.elapsed)),
            _Metric(
              label: s.guessesUsed,
              value: '${round.guessesUsed}',
              accent: round.solved ? null : AppTheme.trapRed,
            ),
          ],
        ),
      ],
    );
  }
}

/// Tóm tắt một ván Sinh tồn: chuỗi vòng đạt được là con số lớn nhất, mọi thứ
/// khác chỉ là chú thích.
class _SurvivalSummary extends StatelessWidget {
  final GameResult result;

  const _SurvivalSummary({required this.result});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final cleared = result.survivedRounds;
    final best = result.previousBestStreak;

    return Column(
      children: <Widget>[
        Text(
          '$cleared',
          style: theme.textTheme.displayMedium?.copyWith(
            fontWeight: FontWeight.w900,
            color: cleared > 0
                ? theme.colorScheme.primary
                : AppTheme.alpha(theme.colorScheme.onSurface, 0.45),
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
        Text(
          cleared == 0 ? s.survivalResultNone : s.survivalRoundsCleared(cleared),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: AppTheme.alpha(theme.colorScheme.onSurface, 0.7),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${s.survivalDiedOnRound(cleared + 1)} · '
          '${s.secretWas(result.rounds.first.secret)}',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppTheme.alpha(theme.colorScheme.onSurface, 0.65),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            _Metric(label: s.time, value: formatDuration(result.elapsed)),
            // Kỷ lục cũ chỉ có nghĩa khi ván này KHÔNG phá được nó — phá rồi
            // thì huy hiệu "Kỷ lục mới!" phía trên đã nói hết.
            if (best != null && !result.isNewRecord)
              _Metric(label: s.bestStreak, value: '$best'),
          ],
        ),
      ],
    );
  }
}

class _DuelSummary extends StatelessWidget {
  final GameResult result;
  final String Function(int playerIndex) playerName;

  const _DuelSummary({required this.result, required this.playerName});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);

    return Column(
      children: <Widget>[
        for (final round in result.rounds) ...<Widget>[
          if (round.player != result.rounds.first.player)
            const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.alpha(_accent(round.player), 0.12),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppTheme.alpha(
                  _accent(round.player),
                  result.winners.contains(round.player) ? 0.85 : 0.25,
                ),
                width: result.winners.contains(round.player) ? 2 : 1,
              ),
            ),
            child: Row(
              children: <Widget>[
                if (result.winners.contains(round.player) && !result.isDraw)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(Icons.emoji_events_rounded,
                        size: 20, color: AppTheme.sunGold),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        playerName(round.player),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        s.secretWas(round.secret),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppTheme.alpha(
                              theme.colorScheme.onSurface, 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  round.solved ? s.guessCount(round.guessesUsed) : s.didNotSolve,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: round.solved
                        ? _accent(round.player)
                        : AppTheme.trapRed,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Color _accent(int player) =>
      AppTheme.playerColors[player % AppTheme.playerColors.length];
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final Color? accent;

  const _Metric({required this.label, required this.value, this.accent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.alpha(
          accent ?? theme.colorScheme.primary,
          0.12,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: <Widget>[
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
              color: accent ?? theme.colorScheme.primary,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppTheme.alpha(theme.colorScheme.onSurface, 0.65),
            ),
          ),
        ],
      ),
    );
  }
}
