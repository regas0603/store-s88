import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Thẻ điểm của một người chơi trong chế độ đấu.
///
/// Người đang tới lượt được viền sáng + nền đậm hơn. Đây là tín hiệu quan trọng
/// nhất ở chế độ 2 người chung máy — không có nó người chơi hay lật nhầm lượt.
class PlayerScoreCard extends StatelessWidget {
  final String name;
  final int score;
  final bool isActive;
  final Color accent;
  final String? status;

  const PlayerScoreCard({
    required this.name,
    required this.score,
    required this.isActive,
    required this.accent,
    this.status,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.alpha(accent, isActive ? 0.20 : 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.alpha(accent, isActive ? 0.85 : 0.22),
          width: isActive ? 2 : 1,
        ),
        boxShadow: isActive
            ? <BoxShadow>[
                BoxShadow(
                  color: AppTheme.alpha(accent, 0.35),
                  blurRadius: 16,
                  spreadRadius: -4,
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              color: AppTheme.alpha(theme.colorScheme.onSurface, 0.75),
            ),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                '$score',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
              const SizedBox(width: 6),
              if (status != null)
                Expanded(
                  child: Text(
                    status!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.alpha(theme.colorScheme.onSurface, 0.6),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Một ô thống kê nhỏ (thời gian / lượt / cặp còn lại).
class StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const StatChip({
    required this.icon,
    required this.label,
    required this.value,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.panelColor(theme.colorScheme, theme.brightness),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.panelBorder(theme.colorScheme, theme.brightness),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppTheme.alpha(theme.colorScheme.onSurface, 0.6),
                ),
              ),
              Text(
                value,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
