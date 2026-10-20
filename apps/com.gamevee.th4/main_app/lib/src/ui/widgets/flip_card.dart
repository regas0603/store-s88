import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/theme.dart';
import '../../game/models/board_card.dart';
import '../../game/models/card_icon.dart';

/// Một lá bài có hiệu ứng lật 3D quanh trục Y.
///
/// Dùng [TweenAnimationBuilder] thay vì [AnimationController]: mỗi lá tự chạy
/// tới góc đích khi [BoardCard.isRevealed] đổi, nên board không cần quản lý
/// hàng chục controller và vòng đời của chúng.
class FlipCard extends StatelessWidget {
  final BoardCard card;
  final double width;
  final double height;

  /// Vừa ghép cặp xong — vẽ viền sáng theo màu người chơi.
  final Color? matchAccent;

  final VoidCallback? onTap;

  const FlipCard({
    required this.card,
    required this.width,
    required this.height,
    this.matchAccent,
    this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final revealed = card.isRevealed;

    return RepaintBoundary(
      child: GestureDetector(
        onTap: card.isSelectable ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: Semantics(
          button: card.isSelectable,
          label: revealed ? card.icon.id : 'úp',
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: revealed ? math.pi : 0),
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeInOutCubic,
            builder: (context, angle, _) {
              final showFront = angle > math.pi / 2;
              final transform = Matrix4.identity()
                ..setEntry(3, 2, 0.0012)
                ..rotateY(angle);

              return Transform(
                alignment: Alignment.center,
                transform: transform,
                child: showFront
                    ? Transform(
                        alignment: Alignment.center,
                        // Lật ngược mặt trước lại, nếu không nội dung sẽ bị soi gương.
                        transform: Matrix4.identity()..rotateY(math.pi),
                        child: _CardFront(
                          card: card,
                          width: width,
                          height: height,
                          matchAccent: matchAccent,
                        ),
                      )
                    : _CardBack(width: width, height: height),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CardBack extends StatelessWidget {
  final double width;
  final double height;

  const _CardBack({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(math.min(width, height) * 0.16),
        child: SvgPicture.asset(package: 'main_app_package', 
          CardIcons.cardBack,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _CardFront extends StatelessWidget {
  final BoardCard card;
  final double width;
  final double height;
  final Color? matchAccent;

  const _CardFront({
    required this.card,
    required this.width,
    required this.height,
    this.matchAccent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = matchAccent;
    final radius = BorderRadius.circular(math.min(width, height) * 0.16);

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFFF4F1FF) : Colors.white,
        borderRadius: radius,
        border: Border.all(
          color: accent ?? AppTheme.alpha(AppTheme.violetBright, 0.22),
          width: accent != null ? 2.6 : 1.2,
        ),
        boxShadow: <BoxShadow>[
          if (accent != null)
            BoxShadow(
              color: AppTheme.alpha(accent, 0.55),
              blurRadius: 14,
              spreadRadius: -2,
            )
          else
            BoxShadow(
              color: AppTheme.alpha(Colors.black, isDark ? 0.35 : 0.10),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(math.min(width, height) * 0.14),
        child: Opacity(
          // Cặp đã ăn mờ đi một chút để mắt tập trung vào phần bàn còn lại.
          opacity: card.matched && matchAccent == null ? 0.55 : 1,
          child: SvgPicture.asset(package: 'main_app_package', card.icon.asset, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
