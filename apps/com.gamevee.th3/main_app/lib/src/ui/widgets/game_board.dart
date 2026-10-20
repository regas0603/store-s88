import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../game/models/board_card.dart';
import '../../game/models/game_config.dart';
import 'flip_card.dart';

/// Lưới lá bài.
///
/// Bàn cờ **không cuộn**: toàn bộ lá phải nhìn thấy cùng lúc, nếu không trò
/// chơi trí nhớ mất ý nghĩa. Vì vậy kích thước lá được tính ngược từ không gian
/// còn lại thay vì dùng `GridView` với aspect ratio cố định.
class GameBoard extends StatelessWidget {
  static const double _gap = 8;
  static const double _cardAspect = 1.32; // cao / rộng

  final List<BoardCard> cards;
  final BoardSize boardSize;
  final Set<int> justMatched;
  final List<int?> matchOwners;
  final bool interactive;
  final void Function(int index) onTap;

  const GameBoard({
    required this.cards,
    required this.boardSize,
    required this.justMatched,
    required this.matchOwners,
    required this.interactive,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = boardSize.columns;
        final rows = boardSize.rows;

        final maxCardWidth =
            (constraints.maxWidth - _gap * (columns - 1)) / columns;
        final maxCardHeight =
            (constraints.maxHeight - _gap * (rows - 1)) / rows;

        // Lưới luôn phủ hết chiều ngang; chiều cao lá giữ tỉ lệ chuẩn nếu đủ
        // chỗ, nếu không thì co lại cho vừa (lá sẽ thấp hơn một chút).
        final cardWidth = math.max(24.0, maxCardWidth);
        final cardHeight =
            math.max(24.0, math.min(cardWidth * _cardAspect, maxCardHeight));

        return Center(
          child: IgnorePointer(
            ignoring: !interactive,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (var row = 0; row < rows; row++) ...<Widget>[
                  if (row > 0) const SizedBox(height: _gap),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      for (var col = 0; col < columns; col++) ...<Widget>[
                        if (col > 0) const SizedBox(width: _gap),
                        _buildCard(row * columns + col, cardWidth, cardHeight),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCard(int index, double width, double height) {
    if (index >= cards.length) {
      return SizedBox(width: width, height: height);
    }
    final card = cards[index];
    final owner = matchOwners.length > index ? matchOwners[index] : null;

    return FlipCard(
      key: ValueKey<int>(card.index),
      card: card,
      width: width,
      height: height,
      matchAccent: justMatched.contains(card.index)
          ? AppTheme.playerColors[(owner ?? 0) % AppTheme.playerColors.length]
          : null,
      onTap: () => onTap(card.index),
    );
  }
}
