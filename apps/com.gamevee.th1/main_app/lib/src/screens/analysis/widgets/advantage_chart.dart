import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/app_settings.dart';
import '../../../core/game_analysis.dart';
import '../../../core/quality_palette.dart';

/// Biểu đồ lợi thế toàn ván — chạm hoặc kéo để nhảy tới nước tương ứng.
///
/// Vẽ bằng [CustomPainter], không thêm package chart nào: giữ tính năng thuần
/// Dart để còn patch được qua Shorebird.
class AdvantageChart extends StatelessWidget {
  final GameAnalysis analysis;
  final PieceSkin skin;

  /// 0 = chưa đánh nước nào, moves.length = đã hết ván.
  final int currentIndex;

  final ValueChanged<int> onSeek;

  static const double height = 64;

  const AdvantageChart({
    super.key,
    required this.analysis,
    required this.skin,
    required this.currentIndex,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    final int n = analysis.moveAnalyses.length;
    if (n == 0) return const SizedBox(height: height);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        void handle(Offset local) {
          final double w = c.maxWidth;
          if (w <= 0) return;
          final int idx = ((local.dx / w) * n).round().clamp(0, n);
          onSeek(idx);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (TapDownDetails d) => handle(d.localPosition),
          onHorizontalDragUpdate: (DragUpdateDetails d) =>
              handle(d.localPosition),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: height,
              color: QualityPalette.surfaceChart,
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _AdvantageChartPainter(
                        analysis: analysis,
                        xColor: skin.xColor,
                        oColor: skin.oColor,
                        currentIndex: currentIndex.clamp(0, n),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 5,
                    top: 3,
                    bottom: 3,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        _axisLabel('+1'),
                        _axisLabel('0'),
                        _axisLabel('−1'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _axisLabel(String t) => Text(
        t,
        style: TextStyle(
          fontSize: 9,
          color: Colors.white.withValues(alpha: 0.4),
          height: 1.0,
        ),
      );
}

class _AdvantageChartPainter extends CustomPainter {
  final GameAnalysis analysis;
  final Color xColor;
  final Color oColor;
  final int currentIndex;

  _AdvantageChartPainter({
    required this.analysis,
    required this.xColor,
    required this.oColor,
    required this.currentIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final List<MoveAnalysis> ms = analysis.moveAnalyses;
    final int n = ms.length;
    if (n == 0) return;

    final double mid = size.height / 2;
    final double step = n > 1 ? size.width / (n - 1) : size.width;
    double yOf(double v) => mid - v * (mid - 6);
    double advAt(int i) => ms[i].advantageMilli / 1000.0;

    // ── Vùng lợi thế ──
    // Dùng chính màu quân X/O thay vì màu cố định: người chơi đã quen X là màu
    // này suốt ván, nên "vùng trên = tôi đang thắng thế" đọc được ngay. Đây là
    // ngoại lệ có chủ ý của quy tắc đế tối — vùng chart là mảng lớn, tương phản
    // không phải vấn đề, và nó không mang mã hoá chất lượng.
    void area(bool positive, Color color) {
      final Path path = Path()..moveTo(0, mid);
      for (int i = 0; i < n; i++) {
        final double v = advAt(i);
        final double clamped = positive ? max(0.0, v) : min(0.0, v);
        path.lineTo(i * step, yOf(clamped));
      }
      path.lineTo(size.width, mid);
      path.close();
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.35));
    }

    area(true, xColor);
    area(false, oColor);

    // ── Vạch dọc đánh dấu nước xấu ──
    // Cho phép quét mắt thấy ngay "chỗ nào hỏng" mà không cần tua từng nước.
    for (final int i in analysis.scoredIndexes) {
      if (i < 0 || i >= n) continue;
      final MoveQuality q = ms[i].quality;
      if (!q.isBad) continue;
      final double x = i * step;
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x, yOf(advAt(i))),
        Paint()
          ..color = QualityPalette.colorOf(q).withValues(alpha: 0.45)
          ..strokeWidth = 1,
      );
    }

    // ── Đường cong ──
    final Path curve = Path();
    for (int i = 0; i < n; i++) {
      final double x = i * step, y = yOf(advAt(i));
      if (i == 0) {
        curve.moveTo(x, y);
      } else {
        curve.lineTo(x, y);
      }
    }
    canvas.drawPath(
      curve,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // ── Đường 0 ──
    canvas.drawLine(
      Offset(0, mid),
      Offset(size.width, mid),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..strokeWidth = 1,
    );

    // ── Điểm bước ngoặt ──
    final int tp = analysis.turningPointIndex;
    if (tp >= 0 && tp < n) {
      final Offset p = Offset(tp * step, yOf(advAt(tp)));
      canvas.drawCircle(
        p,
        4.5,
        Paint()
          ..color = QualityPalette.haloDark
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5,
      );
      canvas.drawCircle(
        p,
        4.5,
        Paint()
          ..color = QualityPalette.blunder
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    // ── Con trỏ nước hiện tại ──
    final int ci = currentIndex.clamp(0, n - 1);
    final double cx = ci * step;
    canvas.drawLine(
      Offset(cx, 0),
      Offset(cx, size.height),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      Offset(cx, yOf(advAt(ci))),
      3,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _AdvantageChartPainter old) =>
      old.currentIndex != currentIndex ||
      old.analysis != analysis ||
      old.xColor != xColor ||
      old.oColor != oColor;
}
