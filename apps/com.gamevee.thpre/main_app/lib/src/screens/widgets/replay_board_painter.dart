import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/app_settings.dart';
import '../../core/game_analysis.dart';
import '../../core/quality_palette.dart';

/// Vẽ bàn cờ cho màn phát lại và màn phân tích.
///
/// Tách khỏi `replay_screen.dart` khi thêm US-005: file đó đã 505 dòng, gộp
/// thêm lớp vẽ nhãn chất lượng sẽ vượt 900 dòng.
///
/// Khi các tham số phân tích để null, painter vẽ y hệt hành vi cũ.
class ReplayBoardPainter extends CustomPainter {
  final List<List<int>> board;
  final int boardSize;
  final PieceSkin skin;
  final (int, int)? lastMove;
  final List<(int, int)>? winCells;

  // ── Lớp phân tích (US-005) ──

  /// Nhãn của nước vừa đánh. Dùng cho chế độ vòng (ô nhỏ).
  final MoveQuality? lastMoveQuality;

  /// Nhãn theo ô, key = row * boardSize + col. Dùng cho chế độ huy hiệu.
  final Map<int, MoveQuality>? cellQualities;

  /// Ô mà engine đề xuất đáng lẽ nên đánh.
  final (int, int)? betterCell;

  /// 0..1 — điều khiển độ mờ nhấp nháy của vòng "nước tốt hơn".
  final double betterPulse;

  ReplayBoardPainter({
    required this.board,
    required this.boardSize,
    required this.skin,
    this.lastMove,
    this.winCells,
    this.lastMoveQuality,
    this.cellQualities,
    this.betterCell,
    this.betterPulse = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double cell = size.width / boardSize;

    _paintGrid(canvas, size, cell);
    _paintWinHighlight(canvas, cell);
    _paintPieces(canvas, cell);
    _paintQualityMarks(canvas, cell);
    _paintBetterMove(canvas, cell);
  }

  // ─────────────────────────────────────────────────────────────────────────

  void _paintGrid(Canvas canvas, Size size, double cell) {
    final Paint gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1.0;
    for (int i = 0; i <= boardSize; i++) {
      canvas.drawLine(
          Offset(i * cell, 0), Offset(i * cell, size.height), gridPaint);
      canvas.drawLine(
          Offset(0, i * cell), Offset(size.width, i * cell), gridPaint);
    }
  }

  void _paintWinHighlight(Canvas canvas, double cell) {
    final List<(int, int)>? cells = winCells;
    if (cells == null) return;
    final Paint winPaint = Paint()
      ..color = Colors.yellowAccent.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    for (final (int r, int c) in cells) {
      canvas.drawRect(Rect.fromLTWH(c * cell, r * cell, cell, cell), winPaint);
    }
  }

  void _paintPieces(Canvas canvas, double cell) {
    for (int r = 0; r < boardSize; r++) {
      for (int c = 0; c < boardSize; c++) {
        final int p = board[r][c];
        if (p == 0) continue;
        final Offset center = Offset(c * cell + cell / 2, r * cell + cell / 2);
        final Color color = p == 1 ? skin.xColor : skin.oColor;
        final bool isLast =
            lastMove != null && lastMove!.$1 == r && lastMove!.$2 == c;

        final Paint glow = Paint()
          ..color = color.withValues(alpha: isLast ? 0.8 : 0.4)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, isLast ? 10 : 6);
        canvas.drawCircle(center, cell * 0.35, glow);

        final Paint fill = Paint()
          ..color = color
          ..style = PaintingStyle.fill;
        canvas.drawCircle(center, cell * 0.32, fill);

        final Paint inner = Paint()
          ..color = Colors.white.withValues(alpha: 0.25)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(
          center.translate(-cell * 0.08, -cell * 0.08),
          cell * 0.1,
          inner,
        );

        // Vòng nước cuối. Ở chế độ vòng, màu vòng chính là nhãn chất lượng.
        if (isLast) {
          final MoveQuality? q =
              cell < QualityPalette.badgeModeMinCell ? lastMoveQuality : null;
          if (q != null) {
            _strokeQualityRing(canvas, center, cell, q);
          } else {
            final Paint ring = Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = max(1.5, cell * 0.04);
            canvas.drawCircle(center, cell * 0.4, ring);
          }
        }
      }
    }
  }

  /// Vòng chất lượng 3 lớp: hào tối dày → màu → viền tối trong và ngoài.
  ///
  /// Hào tối là bắt buộc, không phải trang trí. Skin `fire` có quân X màu cam
  /// #FF6B35 cách màu "Sai lầm" #FB923C chỉ ΔE = 28.9 — thiếu hào tối thì
  /// quầng sáng của quân và vòng hoà vào nhau thành một khối.
  ///
  /// Bán kính 0.45 (không phải 0.40): ở 0.40 khoảng hở với mép quân chỉ còn
  /// 1.9dp trên bàn 15x15, không đủ cho hào tối hiện ra.
  void _strokeQualityRing(
      Canvas canvas, Offset center, double cell, MoveQuality q) {
    final double rr = cell * 0.45;
    final double w = max(1.8, cell * 0.055);
    final Color color = QualityPalette.colorOf(q);
    final bool dashed = QualityPalette.dashedFor(q);

    // Lớp 1 — hào tối dày ở dưới.
    canvas.drawCircle(
      center,
      rr,
      Paint()
        ..color = QualityPalette.haloDark
        ..style = PaintingStyle.stroke
        ..strokeWidth = w + 3,
    );

    // Lớp 2 — màu chất lượng.
    final Paint colorPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w;
    if (dashed) {
      _drawDashedCircle(canvas, center, rr, colorPaint,
          dash: max(3.0, cell * 0.14), gap: max(2.0, cell * 0.09));
    } else {
      canvas.drawCircle(center, rr, colorPaint);
    }

    // Lớp 3 — viền tối mảnh cả trong lẫn ngoài.
    final Paint edge = Paint()
      ..color = QualityPalette.haloDark
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, rr + w / 2 + 0.8, edge);
    canvas.drawCircle(center, rr - w / 2 - 0.8, edge);
  }

  /// Huy hiệu ở góc ô — chỉ dùng khi ô đủ rộng.
  void _paintQualityMarks(Canvas canvas, double cell) {
    if (cell < QualityPalette.badgeModeMinCell) return;
    final Map<int, MoveQuality>? marks = cellQualities;
    if (marks == null || marks.isEmpty) return;

    final double d = min(18.0, cell * 0.46);
    marks.forEach((int key, MoveQuality q) {
      final int r = key ~/ boardSize;
      final int c = key % boardSize;
      if (r < 0 || r >= boardSize || c < 0 || c >= boardSize) return;
      if (board[r][c] == 0) return; // quân đã bị sliding-cap đẩy ra

      final Offset center = Offset(c * cell + cell / 2, r * cell + cell / 2);
      final Offset badge = center.translate(cell * 0.34, -cell * 0.34);
      final Color color = QualityPalette.colorOf(q);

      canvas.drawCircle(
        badge,
        d / 2,
        Paint()
          ..color = QualityPalette.surfaceMarkerDisc
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        badge,
        d / 2,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      _drawGlyph(canvas, badge, QualityPalette.glyphOf(q), d * 0.55, color);
    });
  }

  void _paintBetterMove(Canvas canvas, double cell) {
    final (int, int)? bc = betterCell;
    if (bc == null) return;
    final Offset center =
        Offset(bc.$2 * cell + cell / 2, bc.$1 * cell + cell / 2);
    final double rr = cell * 0.38;
    final double w = max(1.5, cell * 0.045);
    final double alpha = betterPulse.clamp(0.0, 1.0);

    canvas.drawCircle(
      center,
      rr,
      Paint()
        ..color = QualityPalette.haloDark
        ..style = PaintingStyle.stroke
        ..strokeWidth = w + 2,
    );
    _drawDashedCircle(
      canvas,
      center,
      rr,
      Paint()
        ..color = QualityPalette.better.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w,
      dash: max(3.0, cell * 0.14),
      gap: max(2.0, cell * 0.09),
    );
    _drawGlyph(canvas, center, '◎', cell * 0.3,
        QualityPalette.better.withValues(alpha: alpha * 0.7));
  }

  // ── Tiện ích vẽ ──

  void _drawDashedCircle(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint, {
    required double dash,
    required double gap,
  }) {
    final double circumference = 2 * pi * radius;
    if (circumference <= 0) return;
    final double step = dash + gap;
    final int count = max(1, (circumference / step).floor());
    final double sweep = 2 * pi / count;
    final double dashSweep = sweep * (dash / step);
    final Rect rect = Rect.fromCircle(center: center, radius: radius);
    for (int i = 0; i < count; i++) {
      canvas.drawArc(rect, i * sweep, dashSweep, false, paint);
    }
  }

  void _drawGlyph(
      Canvas canvas, Offset center, String glyph, double size, Color color) {
    if (size < 5) return;
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: glyph,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w800,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    tp.paint(canvas, center.translate(-tp.width / 2, -tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant ReplayBoardPainter old) {
    return old.board != board ||
        old.lastMove != lastMove ||
        old.winCells != winCells ||
        old.lastMoveQuality != lastMoveQuality ||
        old.cellQualities != cellQualities ||
        old.betterCell != betterCell ||
        old.betterPulse != betterPulse ||
        old.skin != skin;
  }
}
