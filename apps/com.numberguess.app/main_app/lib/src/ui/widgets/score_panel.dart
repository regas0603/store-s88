import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Một ô thống kê nhỏ (khoảng số / lượt còn lại / thời gian).
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
