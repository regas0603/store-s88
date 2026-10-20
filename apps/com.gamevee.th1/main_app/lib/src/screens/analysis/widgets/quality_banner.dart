import 'package:flutter/material.dart';

import '../../../core/game_analysis.dart';
import '../../../core/l10n.dart';
import '../../../core/quality_palette.dart';
import '../../../core/text_app_style.dart';

/// Băng hiển thị nhãn chất lượng của nước đang xem.
///
/// **Đây là nguồn đọc chính thức**, không phải bàn cờ. Bàn cờ chỉ là chỉ dẫn
/// phụ vì ở bàn 15x15 ô chỉ rộng 21dp — không huy hiệu nào đọc nổi. Băng thì
/// luôn hiện chữ + màu + ký hiệu, đọc được ở mọi kích thước bàn.
///
/// Chiều cao **cố định** kể cả khi rỗng, để bàn cờ không nhảy lên xuống khi
/// người dùng tua qua các nước.
class QualityBanner extends StatelessWidget {
  /// null = nước không được chấm điểm (nước của máy) hoặc chưa bắt đầu.
  final MoveAnalysis? analysis;

  /// Số thứ tự nước (1-based) để hiển thị.
  final int moveNumber;

  /// Toạ độ nước đã đánh.
  final int row;
  final int col;

  /// Gọi khi người dùng chạm vào băng và nước này có gợi ý nước tốt hơn.
  final VoidCallback? onTapBetter;

  /// Text hiện khi ở trạng thái rỗng.
  final String emptyText;

  static const double height = 52;

  const QualityBanner({
    super.key,
    required this.analysis,
    required this.moveNumber,
    required this.row,
    required this.col,
    this.onTapBetter,
    required this.emptyText,
  });

  @override
  Widget build(BuildContext context) {
    final MoveAnalysis? a = analysis;
    if (a == null) return _buildEmpty();

    final Color color = QualityPalette.colorOf(a.quality);
    final String glyph = QualityPalette.glyphOf(a.quality);
    final bool hasBetter = a.hasBetterMove;

    return GestureDetector(
      onTap: hasBetter ? onTapBetter : null,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: <Widget>[
            const SizedBox(width: 9),
            // Thanh dọc màu — dấu hiệu nhận biết nhanh khi tua liên tục.
            Container(
              width: 3,
              height: 34,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: QualityPalette.surfaceMarkerDisc,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                glyph,
                style: TextAppStyle.ui(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text.rich(
                    TextSpan(
                      children: <InlineSpan>[
                        TextSpan(
                          text: l10n.qualityName(a.quality.index).toUpperCase(),
                          style: TextAppStyle.rajdhani(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                            color: color,
                          ),
                        ),
                        TextSpan(
                          text:
                              ' · ${l10n.formatAnalysisMove(moveNumber, formatCellCoord(row, col))}',
                          style: TextAppStyle.ui(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (hasBetter) ...<Widget>[
                    const SizedBox(height: 3),
                    Text.rich(
                      TextSpan(
                        children: <InlineSpan>[
                          TextSpan(
                            text: '${l10n.analysisBetterMove}: ',
                            style: TextAppStyle.ui(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ),
                          TextSpan(
                            text: formatCellCoord(a.betterRow!, a.betterCol!),
                            style: TextAppStyle.ui(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: QualityPalette.better,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          const SizedBox(width: 22),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: QualityPalette.surfaceMarkerDisc,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              '–',
              style: TextAppStyle.ui(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.3),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              emptyText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextAppStyle.ui(
                fontSize: 11.5,
                color: Colors.white.withValues(alpha: 0.35),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}
