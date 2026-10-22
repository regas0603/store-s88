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
/// nhìn vào một bàn cờ đã xong mà không biết làm gì.
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
        return s.resultSolo;
      case GameMode.vsAi:
        if (result.isDraw) return s.resultDraw;
        return result.humanWon ? s.resultWin : s.resultLose;
      case GameMode.pvp:
        if (result.isDraw) return s.resultDraw;
        return s.resultPlayerWins(playerName(result.winners.first));
    }
  }

  IconData _icon() {
    switch (result.mode) {
      case GameMode.solo:
        return Icons.celebration_rounded;
      case GameMode.vsAi:
        if (result.isDraw) return Icons.handshake_rounded;
        return result.humanWon
            ? Icons.emoji_events_rounded
            : Icons.sentiment_dissatisfied_rounded;
      case GameMode.pvp:
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
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.alpha(AppTheme.sunGold, 0.20),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppTheme.alpha(AppTheme.sunGold, 0.7),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(Icons.star_rounded,
                        size: 18, color: AppTheme.sunGold),
                    const SizedBox(width: 6),
                    Text(
                      s.newRecord,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            if (result.mode == GameMode.solo)
              // Wrap chứ không Row: mức khó có ba ô, tràn ngang trên máy nhỏ.
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  _Metric(label: s.time, value: formatDuration(result.elapsed)),
                  _Metric(label: s.moves, value: '${result.moves}'),
                  if (result.trapsHit != null)
                    _Metric(
                      label: s.trapsHit,
                      value: '${result.trapsHit!.first}',
                      accent: AppTheme.trapRed,
                    ),
                ],
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  for (var i = 0; i < result.scores.length; i++) ...<Widget>[
                    if (i > 0) const SizedBox(width: 12),
                    _Metric(
                      label: playerName(i),
                      value: '${result.scores[i]}',
                      accent: AppTheme
                          .playerColors[i % AppTheme.playerColors.length],
                      footnote: result.trapsHit == null
                          ? null
                          : '${s.trapsHit}: ${result.trapsHit![i]}',
                    ),
                  ],
                ],
              ),
            const SizedBox(height: 22),
            NeonPrimaryButton(
              label: s.playAgain,
              icon: Icons.refresh_rounded,
              onPressed: () =>
                  Navigator.of(context).pop(ResultAction.playAgain),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(ResultAction.backToMenu),
              child: Text(s.backToMenu),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final Color? accent;

  /// Dòng nhỏ bên dưới số chính, ví dụ số lần dính bom ở chế độ đấu.
  final String? footnote;

  const _Metric({
    required this.label,
    required this.value,
    this.accent,
    this.footnote,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = accent ?? theme.colorScheme.primary;

    return Container(
      constraints: const BoxConstraints(minWidth: 110),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.alpha(color, 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.alpha(color, 0.4)),
      ),
      child: Column(
        children: <Widget>[
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppTheme.alpha(theme.colorScheme.onSurface, 0.65),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          if (footnote != null)
            Text(
              footnote!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppTheme.trapRed,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}
