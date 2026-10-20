import 'package:flutter/material.dart';

import '../../../core/app_settings.dart';
import '../../../core/game_analysis.dart';
import '../../../core/game_history.dart';
import '../../../core/l10n.dart';
import '../../../core/quality_palette.dart';
import '../../../core/text_app_style.dart';
import '../../../utils/date_utils.dart';

/// Dải tổng kết thu gọn (56dp) đặt ngay dưới header màn phân tích.
///
/// Cố ý chỉ 1 dòng: màn hình phân tích đã phải nhét thêm băng chất lượng và
/// biểu đồ, không còn chỗ cho bản đầy đủ. Chạm vào để mở bottom sheet chi tiết.
class AccuracyStrip extends StatelessWidget {
  final GameAnalysis analysis;
  final bool isPvp;
  final VoidCallback onTap;

  static const double height = 56;

  const AccuracyStrip({
    super.key,
    required this.analysis,
    required this.isPvp,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Map<MoveQuality, int> counts = analysis.counts;
    final int acc = analysis.accuracyX;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: QualityPalette.surfaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: QualityPalette.strokeHairline),
        ),
        child: Row(
          children: <Widget>[
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // PvP hiện cả hai bên: hai người cùng xem một màn hình, chỉ
                // hiện một bên sẽ thành tranh chấp.
                Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: '$acc%',
                        style: TextAppStyle.rajdhani(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          height: 1.0,
                          color: QualityPalette.accuracyColor(acc),
                        ),
                      ),
                      if (isPvp)
                        TextSpan(
                          text: ' / ${analysis.accuracyO}%',
                          style: TextAppStyle.rajdhani(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            height: 1.0,
                            color: QualityPalette.accuracyColor(
                                analysis.accuracyO),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isPvp
                      ? '${l10n.analysisAccuracy}  X / O'
                      : l10n.analysisAccuracy,
                  style: TextAppStyle.ui(
                    fontSize: 9,
                    letterSpacing: 0.8,
                    color: Colors.white.withValues(alpha: 0.42),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),
            Container(
                width: 1, height: 30, color: QualityPalette.strokeHairline),
            const SizedBox(width: 14),
            Expanded(
              child: Wrap(
                spacing: 9,
                runSpacing: 2,
                children: MoveQuality.values.map((MoveQuality q) {
                  return Text(
                    '${QualityPalette.glyphOf(q)}${counts[q] ?? 0}',
                    style: TextAppStyle.ui(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: QualityPalette.colorOf(q),
                    ),
                  );
                }).toList(),
              ),
            ),
            if (analysis.turningPointIndex >= 0)
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    l10n.analysisTurningPoint,
                    style: TextAppStyle.ui(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.42),
                    ),
                  ),
                  Text(
                    '#${analysis.turningPointIndex + 1}',
                    style: TextAppStyle.ui(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet tổng kết đầy đủ.
Future<void> showAccuracySheet(
  BuildContext context, {
  required GameAnalysis analysis,
  required GameRecord record,
  required VoidCallback onShare,
}) {
  final bool isPvp = record.mode == GameMode.twoPlayers;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (BuildContext ctx) => _AccuracySheet(
      analysis: analysis,
      record: record,
      isPvp: isPvp,
      onShare: onShare,
    ),
  );
}

class _AccuracySheet extends StatelessWidget {
  final GameAnalysis analysis;
  final GameRecord record;
  final bool isPvp;
  final VoidCallback onShare;

  const _AccuracySheet({
    required this.analysis,
    required this.record,
    required this.isPvp,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final Map<MoveQuality, int> counts = analysis.counts;
    final PieceSkin skin = PieceSkin.values.firstWhere(
      (PieceSkin s) => s.name == record.skinName,
      orElse: () => PieceSkin.neon,
    );

    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: QualityPalette.surfaceCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.only(top: 10, bottom: 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              if (isPvp)
                _buildPvpHeader(skin)
              else
                _buildSoloHeader(analysis.accuracyX),
              _divider(),
              ...MoveQuality.values.map((MoveQuality q) => _QualityRow(
                    quality: q,
                    count: counts[q] ?? 0,
                  )),
              _divider(),
              if (analysis.turningPointIndex >= 0)
                _kv(
                  l10n.analysisTurningPoint,
                  _turningPointLabel(),
                ),
              _kv(
                l10n.analysisAnalyzedAt,
                formatDateTimeShort(analysis.analyzedAt),
              ),
              if (record.result == GameResult.timeout)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      l10n.analysisTimeoutNote,
                      style: TextAppStyle.ui(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ),
              _divider(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: GestureDetector(
                  onTap: () {
                    Navigator.of(context).pop();
                    onShare();
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color:
                              QualityPalette.brilliant.withValues(alpha: 0.4)),
                      color: QualityPalette.brilliant.withValues(alpha: 0.08),
                    ),
                    child: Text(
                      l10n.analysisShareSummary,
                      textAlign: TextAlign.center,
                      style: TextAppStyle.rajdhani(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.6,
                        color: QualityPalette.brilliant,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Text(
                  l10n.analysisDisclaimer,
                  style: TextAppStyle.ui(
                    fontSize: 10.5,
                    height: 1.6,
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _turningPointLabel() {
    final int i = analysis.turningPointIndex;
    if (i < 0 || i >= record.moves.length) return '—';
    final MoveLog m = record.moves[i];
    return l10n.formatAnalysisMove(i + 1, formatCellCoord(m.row, m.col));
  }

  Widget _buildSoloHeader(int acc) {
    return Column(
      children: <Widget>[
        Text(
          '$acc%',
          style: TextAppStyle.rajdhani(
            fontSize: 44,
            fontWeight: FontWeight.w700,
            height: 1.0,
            color: QualityPalette.accuracyColor(acc),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          l10n.analysisAccuracy,
          style: TextAppStyle.ui(
            fontSize: 11,
            letterSpacing: 1.4,
            color: Colors.white.withValues(alpha: 0.45),
          ),
        ),
      ],
    );
  }

  /// PvP: hai cột song song. Hai người cùng ngồi xem một màn hình, cho chọn
  /// một bên sẽ thành tranh chấp.
  Widget _buildPvpHeader(PieceSkin skin) {
    Widget col(String label, int acc, Color markColor) => Expanded(
          child: Column(
            children: <Widget>[
              Text(
                label,
                style: TextAppStyle.ui(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: markColor,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$acc%',
                style: TextAppStyle.rajdhani(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                  color: QualityPalette.accuracyColor(acc),
                ),
              ),
            ],
          ),
        );

    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            col(l10n.analysisPlayerX, analysis.accuracyX, skin.xColor),
            Container(
                width: 1, height: 44, color: QualityPalette.strokeHairline),
            col(l10n.analysisPlayerO, analysis.accuracyO, skin.oColor),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          l10n.analysisAccuracy,
          style: TextAppStyle.ui(
            fontSize: 11,
            letterSpacing: 1.4,
            color: Colors.white.withValues(alpha: 0.45),
          ),
        ),
      ],
    );
  }

  Widget _divider() => Container(
        height: 1,
        margin: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        color: QualityPalette.strokeHairline,
      );

  Widget _kv(String k, String v) => SizedBox(
        height: 30,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: <Widget>[
              Text(
                k,
                style: TextAppStyle.ui(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
              const Spacer(),
              Text(
                v,
                style: TextAppStyle.ui(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
      );
}

class _QualityRow extends StatelessWidget {
  final MoveQuality quality;
  final int count;

  const _QualityRow({required this.quality, required this.count});

  @override
  Widget build(BuildContext context) {
    final Color color = QualityPalette.colorOf(quality);
    return SizedBox(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 20,
              child: Text(
                QualityPalette.glyphOf(quality),
                textAlign: TextAlign.center,
                style: TextAppStyle.ui(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.qualityName(quality.index),
                style: TextAppStyle.ui(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ),
            Text(
              '$count',
              style: TextAppStyle.ui(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet "Cách đọc phân tích".
///
/// Cần thiết vì hệ 5 nhãn và biểu đồ lợi thế là từ vựng mới với người chơi
/// caro phổ thông — khác cờ vua, họ không quen khái niệm "blunder". Không có
/// màn giải thích, phần lớn sẽ chỉ liếc con số % rồi thoát.
Future<void> showHowToReadSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (BuildContext ctx) => SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: QualityPalette.surfaceCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                l10n.analysisHowToRead,
                style: TextAppStyle.rajdhani(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              ...MoveQuality.values.map((MoveQuality q) {
                final Color color = QualityPalette.colorOf(q);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: QualityPalette.surfaceMarkerDisc,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: color, width: 1.2),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          QualityPalette.glyphOf(q),
                          style: TextAppStyle.ui(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: color,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              l10n.qualityName(q.index),
                              style: TextAppStyle.ui(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: color,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              l10n.qualityDesc(q.index),
                              style: TextAppStyle.ui(
                                fontSize: 12,
                                height: 1.5,
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 4),
              _HelpParagraph(text: l10n.analysisChartHelp),
              _HelpParagraph(text: l10n.analysisBetterHelp),
              _HelpParagraph(text: l10n.analysisDisclaimer),
              const SizedBox(height: 18),
              GestureDetector(
                onTap: () => Navigator.of(ctx).pop(),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: QualityPalette.brilliant.withValues(alpha: 0.12),
                    border: Border.all(
                        color: QualityPalette.brilliant.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    l10n.analysisGotIt,
                    textAlign: TextAlign.center,
                    style: TextAppStyle.rajdhani(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.6,
                      color: QualityPalette.brilliant,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _HelpParagraph extends StatelessWidget {
  final String text;

  const _HelpParagraph({required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          text,
          style: TextAppStyle.ui(
            fontSize: 12,
            height: 1.6,
            color: Colors.white.withValues(alpha: 0.55),
          ),
        ),
      );
}
