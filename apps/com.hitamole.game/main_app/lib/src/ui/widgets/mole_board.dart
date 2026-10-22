import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../game/models/game_config.dart';
import '../../game/models/mole_hole.dart';
import 'mole_hole_view.dart';

/// Lưới hang chuột chũi.
///
/// Bàn **không cuộn**: mọi hang phải nhìn thấy cùng lúc, nếu không người chơi
/// không thể phản xạ kịp. Vì vậy kích thước ô được tính ngược từ không gian
/// còn lại thay vì dùng `GridView` với aspect ratio cố định.
class MoleBoard extends StatelessWidget {
  static const double _gap = 10;
  static const double _cellAspect = 1.0; // cao / rộng

  final List<MoleHole> holes;
  final BoardSize boardSize;
  final bool interactive;
  final void Function(int index) onTap;

  const MoleBoard({
    required this.holes,
    required this.boardSize,
    required this.interactive,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = boardSize.columns;
        final rows = boardSize.rows;

        final maxCellWidth =
            (constraints.maxWidth - _gap * (columns - 1)) / columns;
        final maxCellHeight =
            (constraints.maxHeight - _gap * (rows - 1)) / rows;

        final cellHeight = math.max(
          40.0,
          math.min(maxCellWidth * _cellAspect, maxCellHeight),
        );
        final cellWidth = math.max(40.0, math.min(maxCellWidth, cellHeight * 1.15));

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
                        _buildCell(
                          theme,
                          row * columns + col,
                          cellWidth,
                          cellHeight,
                        ),
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

  Widget _buildCell(ThemeData theme, int index, double width, double height) {
    if (index >= holes.length) {
      return SizedBox(width: width, height: height);
    }
    final hole = holes[index];
    final owner = hole.hitBy;

    // DecoratedBox chứ không phải Container: Container tự cộng độ dày viền vào
    // padding, làm mỗi ô to hơn kích thước đã tính và tràn lưới (4 cột = 8px).
    return DecoratedBox(
      key: ValueKey<int>(hole.index),
      decoration: BoxDecoration(
        color: AppTheme.panelColor(theme.colorScheme, theme.brightness),
        borderRadius: BorderRadius.circular(math.min(width, height) * 0.2),
        border: Border.all(
          color: AppTheme.panelBorder(theme.colorScheme, theme.brightness),
        ),
      ),
      child: MoleHoleView(
        width: width,
        height: height,
        raised: hole.isRaised,
        dazed: hole.state == HoleState.hit,
        icon: hole.icon,
        isTrap: hole.isTrap,
        moleId: hole.moleId,
        hitAccent: owner == null
            ? null
            : AppTheme.playerColors[owner % AppTheme.playerColors.length],
        onTap: () => onTap(hole.index),
      ),
    );
  }
}
