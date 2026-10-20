import 'package:flutter/material.dart';

import '../../core/game_analysis.dart';
import '../../core/game_analysis_service.dart';
import '../../core/game_history.dart';
import '../../core/l10n.dart';
import '../../core/quality_palette.dart';
import '../../core/text_app_style.dart';

/// Chạy phân tích cho [record] và hiện dialog tiến độ.
///
/// Trả về [GameAnalysis] khi xong, null khi người dùng huỷ hoặc gặp lỗi.
/// Kết quả **đã được lưu** vào [GameHistory] trước khi trả về.
Future<GameAnalysis?> runAnalysisWithDialog(
  BuildContext context,
  GameRecord record,
) async {
  if (!record.canAnalyze) return null;
  return showDialog<GameAnalysis?>(
    context: context,
    // Bắt buộc bấm Huỷ: chạm ra ngoài mà mất tiến độ đang chạy là hành vi tệ.
    barrierDismissible: false,
    builder: (BuildContext ctx) => _AnalysisProgressDialog(record: record),
  );
}

class _AnalysisProgressDialog extends StatefulWidget {
  final GameRecord record;

  const _AnalysisProgressDialog({required this.record});

  @override
  State<_AnalysisProgressDialog> createState() =>
      _AnalysisProgressDialogState();
}

class _AnalysisProgressDialogState extends State<_AnalysisProgressDialog> {
  late final GameAnalysisService _service = GameAnalysisService();
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _failed = false);
    GameAnalysis? result;
    try {
      result = await _service.analyze(widget.record);
    } catch (_) {
      result = null;
    }
    if (!mounted) return;
    if (result == null) {
      // Huỷ cũng đi qua nhánh này — phân biệt bằng cờ isRunning đã bị tắt khi
      // cancel(). Ở đây chỉ cần: nếu widget còn sống mà không có kết quả thì
      // coi là lỗi và cho người dùng thử lại.
      setState(() => _failed = true);
      return;
    }

    // Lưu ngay để lần sau mở không phải tính lại.
    final GameRecord updated = widget.record.copyWithAnalysis(result);
    await GameHistory().updateRecord(updated);

    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  void _cancel() {
    _service.cancel();
    Navigator.of(context).pop(null);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
        decoration: BoxDecoration(
          color: QualityPalette.surfaceCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: QualityPalette.strokeHairline),
        ),
        child: _failed ? _buildError() : _buildProgress(),
      ),
    );
  }

  Widget _buildProgress() {
    return ValueListenableBuilder<AnalysisProgress>(
      valueListenable: _service.progress,
      builder: (BuildContext context, AnalysisProgress p, _) {
        final bool almost = p.value >= 0.95;
        final String subtitle;
        switch (p.phase) {
          case AnalysisPhase.shallow:
            subtitle = l10n.formatAnalysisProgress(p.current, p.total);
            break;
          case AnalysisPhase.deep:
            subtitle = l10n.analysisPhaseDeep;
            break;
          case AnalysisPhase.finishing:
            subtitle = l10n.analysisPhaseFinishing;
            break;
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: 88,
              height: 88,
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  SizedBox(
                    width: 88,
                    height: 88,
                    child: CircularProgressIndicator(
                      // Giá trị THẬT, không phải spinner vô hạn — người dùng
                      // cần biết còn bao lâu.
                      value: p.value,
                      strokeWidth: 6,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          QualityPalette.brilliant),
                    ),
                  ),
                  Text(
                    '${(p.value * 100).round()}%',
                    style: TextAppStyle.rajdhani(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              l10n.analysisRunning,
              textAlign: TextAlign.center,
              style: TextAppStyle.rajdhani(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.8,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextAppStyle.ui(
                fontSize: 11.5,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 20),
            Opacity(
              opacity: almost ? 0.4 : 1.0,
              child: _button(
                label: l10n.analysisCancel,
                onTap: _cancel,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildError() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(Icons.error_outline_rounded,
            size: 40, color: QualityPalette.blunder),
        const SizedBox(height: 14),
        Text(
          l10n.analysisErrorTitle,
          textAlign: TextAlign.center,
          style: TextAppStyle.ui(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 20),
        Row(
          children: <Widget>[
            Expanded(
              child: _button(
                label: l10n.analysisRetry,
                onTap: _start,
                filled: true,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _button(
                label: l10n.analysisClose,
                onTap: () => Navigator.of(context).pop(null),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _button({
    required String label,
    required VoidCallback onTap,
    bool filled = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        // 48dp: đạt chuẩn vùng chạm tối thiểu.
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: filled
              ? QualityPalette.brilliant.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.04),
          border: Border.all(
            color: filled
                ? QualityPalette.brilliant.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.15),
          ),
        ),
        child: Text(
          label,
          style: TextAppStyle.ui(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: filled
                ? QualityPalette.brilliant
                : Colors.white.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}
