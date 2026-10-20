import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Nền gradient dùng cho mọi màn hình, kèm hai quầng sáng neon mờ.
///
/// Dùng [DecoratedBox] tĩnh thay vì animation: nền chuyển động liên tục sẽ đốt
/// GPU suốt ván chơi và làm phân tán chú ý khỏi lá bài.
class AppBackground extends StatelessWidget {
  final Widget child;

  const AppBackground({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final colors = AppTheme.backdropFor(brightness);
    final isDark = brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            top: -120,
            right: -90,
            child: _Glow(
              color: AppTheme.neonPink,
              opacity: isDark ? 0.24 : 0.16,
            ),
          ),
          Positioned(
            bottom: -140,
            left: -110,
            child: _Glow(
              color: AppTheme.neonCyan,
              opacity: isDark ? 0.20 : 0.14,
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  final Color color;
  final double opacity;

  const _Glow({required this.color, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: 300,
        height: 300,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[
              AppTheme.alpha(color, opacity),
              AppTheme.alpha(color, 0),
            ],
          ),
        ),
      ),
    );
  }
}
