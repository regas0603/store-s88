import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/game_analysis.dart';
import '../core/game_history.dart';
import '../core/quality_palette.dart';
import 'analysis/analysis_progress_dialog.dart';
import 'analysis/analysis_replay_screen.dart';
import '../core/l10n.dart';
import '../core/text_app_style.dart';

class ResultScreen extends StatefulWidget {
  final GameResult result;
  final bool vsAI;
  final int totalMoves;
  final int durationSecs;
  final int boardSide;
  final int winLength;
  final VoidCallback onPlayAgain;
  final VoidCallback onHome;

  const ResultScreen({
    super.key,
    required this.result,
    required this.vsAI,
    required this.totalMoves,
    required this.durationSecs,
    required this.boardSide,
    required this.winLength,
    required this.onPlayAgain,
    required this.onHome,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen>
    with TickerProviderStateMixin {
  late AnimationController _entryCtrl;
  late AnimationController _particleCtrl;
  late AnimationController _pulseCtrl;

  late Animation<double> _scale;
  late Animation<double> _fade;

  // Snapshot target — RepaintBoundary wraps the main card.
  final GlobalKey _shareKey = GlobalKey();
  bool _sharing = false;

  /// Record của chính ván vừa kết thúc.
  ///
  /// `CaroGame._saveHistory()` chèn record mới vào đầu danh sách TRƯỚC khi màn
  /// kết quả hiện ra, nên bản ghi đầu tiên chính là ván này. Vẫn đối chiếu vài
  /// trường để chắc chắn — nếu lệch thì ẩn nút thay vì mở nhầm ván khác.
  ///
  /// CACHE lại, không tính trong build: màn này có 3 AnimationController nên
  /// build chạy ~60 lần/giây, mà `GameHistory().records` trả về bản sao
  /// unmodifiable của tối đa 100 record — tính lại mỗi khung hình là lãng phí.
  GameRecord? _cachedRecord;

  GameRecord? _resolveRecord() {
    final List<GameRecord> all = GameHistory().records;
    if (all.isEmpty) return null;
    final GameRecord r = all.first;
    final bool matches = r.result == widget.result &&
        r.totalMoves == widget.totalMoves &&
        r.boardSide == widget.boardSide &&
        (r.mode == GameMode.vsAI) == widget.vsAI;
    return matches ? r : null;
  }

  GameRecord? get _record => _cachedRecord;

  Future<void> _onAnalyse() async {
    final GameRecord? rec = _record;
    if (rec == null) return;
    GameAnalysis? analysis = rec.analysis;
    GameRecord target = rec;
    if (analysis == null) {
      analysis = await runAnalysisWithDialog(context, rec);
      if (analysis == null || !mounted) return;
      target = rec.copyWithAnalysis(analysis);
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AnalysisReplayScreen(record: target, analysis: analysis!),
      ),
    );
    if (mounted) setState(() => _cachedRecord = _resolveRecord());
  }

  /// Nút thể outlined, KHÔNG phải filled — để không cạnh tranh với CTA chính
  /// là "Chơi lại". Màu dùng [QualityPalette.brilliant] cố định thay vì
  /// `_mainColor` (đổi theo thắng/thua/hoà): nút này là lối vào một tính năng,
  /// không phải phản hồi kết quả, nên cần danh tính màu ổn định.
  Widget _buildAnalyseButton() {
    final GameRecord? rec = _record;
    final bool done = rec?.hasAnalysis ?? false;
    return GestureDetector(
      onTap: _onAnalyse,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: QualityPalette.brilliant.withValues(alpha: 0.45)),
          color: QualityPalette.brilliant.withValues(alpha: 0.08),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.insights_rounded,
                size: 16, color: QualityPalette.brilliant),
            const SizedBox(width: 8),
            Text(
              done ? l10n.analysisViewButton : l10n.analysisButton,
              style: TextAppStyle.rajdhani(
                color: QualityPalette.brilliant,
                fontWeight: FontWeight.bold,
                fontSize: 14,
                letterSpacing: 2,
              ),
            ),
            if (done && rec != null) ...<Widget>[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(7),
                  color: QualityPalette.brilliant.withValues(alpha: 0.16),
                ),
                child: Text(
                  '${rec.analysis!.accuracyX}%',
                  style: TextAppStyle.rajdhani(
                    color: QualityPalette.brilliant,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _cachedRecord = _resolveRecord();

    _entryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _particleCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 3))
      ..repeat();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);

    _scale = CurvedAnimation(parent: _entryCtrl, curve: Curves.elasticOut);
    _fade = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);

    _entryCtrl.forward();
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _particleCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Color get _mainColor {
    switch (widget.result) {
      case GameResult.xWins: return const Color(0xFF4fc3f7);
      case GameResult.oWins: return const Color(0xFFf48fb1);
      case GameResult.draw: return const Color(0xFFFFD700);
      case GameResult.timeout: return Colors.orange;
    }
  }

  String get _resultTitle {
    switch (widget.result) {
      case GameResult.xWins:
        return widget.vsAI ? l10n.youWin : l10n.xWins;
      case GameResult.oWins:
        return widget.vsAI ? l10n.aiWins : l10n.oWins;
      case GameResult.draw:
        return l10n.draw;
      case GameResult.timeout:
        return l10n.timeout;
    }
  }

  String get _durationText {
    final m = widget.durationSecs ~/ 60;
    final s = widget.durationSecs % 60;
    if (m == 0) return '${s}s';
    return '${m}m ${s}s';
  }

  Future<void> _onShare() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      // Chờ 1 frame để RepaintBoundary chắc chắn đã layout + paint.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;

      final BuildContext? ctx = _shareKey.currentContext;
      if (ctx == null) throw StateError('share boundary context is null');
      final RenderObject? renderObj = ctx.findRenderObject();
      if (renderObj is! RenderRepaintBoundary) {
        throw StateError('share boundary render object is ${renderObj.runtimeType}');
      }
      final RenderRepaintBoundary boundary = renderObj;

      final double pixelRatio = MediaQuery.of(context).devicePixelRatio;
      final ui.Image image =
          await boundary.toImage(pixelRatio: pixelRatio * 1.2);
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) {
        throw StateError('share toByteData returned null');
      }
      final Uint8List pngBytes = byteData.buffer.asUint8List();

      final Directory tempDir = await getTemporaryDirectory();
      final String fname =
          'caro_result_${DateTime.now().millisecondsSinceEpoch}.png';
      final File file = File('${tempDir.path}/$fname');
      await file.writeAsBytes(pngBytes, flush: true);

      final String message = l10n.shareMessage(
        vsAI: widget.vsAI,
        result: widget.result,
        totalMoves: widget.totalMoves,
        durationSecs: widget.durationSecs,
        boardSide: widget.boardSide,
        winLength: widget.winLength,
      );

      // Popover anchor bắt buộc trên iPad — iPhone thì share_plus tự chọn.
      final RenderBox? box = context.findRenderObject() as RenderBox?;
      final Rect sharePositionOrigin = box != null
          ? (box.localToGlobal(Offset.zero) & box.size)
          : Rect.fromLTWH(0, 0,
              MediaQuery.of(context).size.width,
              MediaQuery.of(context).size.height / 2);

      final ShareResult result = await Share.shareXFiles(
        <XFile>[XFile(file.path, mimeType: 'image/png')],
        subject: l10n.shareSubject,
        text: message,
        sharePositionOrigin: sharePositionOrigin,
      );

      if (kDebugMode) {
        debugPrint('[Share] status=${result.status} raw=${result.raw}');
      }

      // status dismissed = user đóng share sheet → không phải lỗi, không show snack.
      if (!mounted) return;
      if (result.status == ShareResultStatus.unavailable) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.shareError)),
        );
      }
    } catch (e, st) {
      // Log error ra console để debug thực sự, thay vì chỉ hiện snackbar chung.
      debugPrint('[Share] FAILED: $e');
      debugPrintStack(stackTrace: st, label: 'share_error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(kDebugMode ? 'Share failed: $e' : l10n.shareError),
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.85),
      child: AnimatedBuilder(
        animation: Listenable.merge([_entryCtrl, _particleCtrl, _pulseCtrl]),
        builder: (_, __) {
          return Stack(
            children: [
              // Particle burst
              if (widget.result != GameResult.draw &&
                  widget.result != GameResult.timeout)
                ..._buildParticles(),
              // Main card wrapped in RepaintBoundary → source for Share snapshot
              Center(
                child: FadeTransition(
                  opacity: _fade,
                  child: ScaleTransition(
                    scale: _scale,
                    child: RepaintBoundary(
                      key: _shareKey,
                      child: Container(
                        width: min(MediaQuery.of(context).size.width - 48, 340),
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF1a1a3e),
                              Color(0xFF0d0d22),
                            ],
                          ),
                          border: Border.all(
                              color: _mainColor.withValues(alpha: 0.4),
                              width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: _mainColor.withValues(
                                  alpha: 0.15 + _pulseCtrl.value * 0.1),
                              blurRadius: 40 + _pulseCtrl.value * 20,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Big emoji
                            Container(
                              width: 90,
                              height: 90,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _mainColor.withValues(alpha: 0.1),
                                border: Border.all(
                                    color: _mainColor.withValues(alpha: 0.5),
                                    width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: _mainColor.withValues(
                                        alpha: 0.2 + _pulseCtrl.value * 0.2),
                                    blurRadius: 20,
                                    spreadRadius: 3,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  l10n.resultListMark(widget.result),
                                  style: TextAppStyle.ui(
                                    fontSize: 42,
                                    fontWeight: FontWeight.bold,
                                    color: _mainColor,
                                  ).copyWith(
                                    shadows: [
                                      Shadow(
                                        color: _mainColor,
                                        blurRadius:
                                            15 + _pulseCtrl.value * 10,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              _resultTitle,
                              textAlign: TextAlign.center,
                              style: TextAppStyle.pressStart2p(
                                color: _mainColor,
                                fontSize: 18,
                                shadows: [
                                  Shadow(
                                      color: _mainColor.withValues(alpha: 0.6),
                                      blurRadius: 10)
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              l10n.formatHistoryBoardLine(
                                  widget.boardSide, widget.winLength),
                              textAlign: TextAlign.center,
                              style: TextAppStyle.ui(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 20),
                            // Stats
                            _StatRow(
                              icon: Icons.grid_on,
                              label: l10n.totalMoves,
                              value: '${widget.totalMoves}',
                              color: _mainColor,
                            ),
                            const SizedBox(height: 8),
                            _StatRow(
                              icon: Icons.timer_outlined,
                              label: l10n.duration,
                              value: _durationText,
                              color: _mainColor,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Buttons outside the RepaintBoundary so they don't appear in the snapshot
              Positioned(
                left: 0,
                right: 0,
                bottom: 32,
                child: Center(
                  child: FadeTransition(
                    opacity: _fade,
                    child: SizedBox(
                      width: min(MediaQuery.of(context).size.width - 48, 340),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          GestureDetector(
                            onTap: widget.onPlayAgain,
                            child: Container(
                              width: double.infinity,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                gradient: LinearGradient(
                                  colors: [
                                    _mainColor,
                                    _mainColor.withValues(alpha: 0.7)
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                      color:
                                          _mainColor.withValues(alpha: 0.3),
                                      blurRadius: 12)
                                ],
                              ),
                              child: Text(
                                l10n.playAgain,
                                textAlign: TextAlign.center,
                                style: TextAppStyle.rajdhani(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  letterSpacing: 3,
                                ),
                              ),
                            ),
                          ),
                          if (_record?.canAnalyze ?? false) ...<Widget>[
                            const SizedBox(height: 10),
                            _buildAnalyseButton(),
                          ],
                          const SizedBox(height: 10),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: GestureDetector(
                                  onTap: _sharing ? null : _onShare,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                          color: _mainColor.withValues(
                                              alpha: 0.4)),
                                      color:
                                          _mainColor.withValues(alpha: 0.08),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: <Widget>[
                                        _sharing
                                            ? SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  valueColor:
                                                      AlwaysStoppedAnimation<
                                                          Color>(_mainColor),
                                                ),
                                              )
                                            : Icon(Icons.ios_share_rounded,
                                                size: 16, color: _mainColor),
                                        const SizedBox(width: 8),
                                        Text(
                                          l10n.shareButton,
                                          style: TextAppStyle.rajdhani(
                                            color: _mainColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            letterSpacing: 2,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: GestureDetector(
                                  onTap: widget.onHome,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                          color: Colors.white.withValues(
                                              alpha: 0.15)),
                                      color: Colors.white.withValues(
                                          alpha: 0.04),
                                    ),
                                    child: Text(
                                      l10n.backHome,
                                      textAlign: TextAlign.center,
                                      style: TextAppStyle.rajdhani(
                                        color: Colors.white.withValues(
                                            alpha: 0.8),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildParticles() {
    final size = MediaQuery.of(context).size;
    final rng = Random(0);
    return List.generate(20, (i) {
      final angle = (i / 20) * 2 * pi;
      final speed = 80 + rng.nextDouble() * 120;
      final progress = (_particleCtrl.value + i / 20) % 1.0;
      final x = size.width / 2 + cos(angle) * speed * progress;
      final y = size.height / 2 + sin(angle) * speed * progress - 200 * progress * progress;
      final opacity = (1 - progress).clamp(0.0, 1.0);
      return Positioned(
        left: x - 4,
        top: y - 4,
        child: Opacity(
          opacity: opacity,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i % 2 == 0 ? _mainColor : Colors.white,
              boxShadow: [BoxShadow(color: _mainColor, blurRadius: 4)],
            ),
          ),
        ),
      );
    });
  }
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.white.withValues(alpha: 0.04),
      ),
      child: Row(
        children: [
          Icon(icon, color: color.withValues(alpha: 0.6), size: 18),
          const SizedBox(width: 10),
          Text(
              label,
              style: TextAppStyle.ui(
                  color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
          const Spacer(),
          Text(
              value,
              style: TextAppStyle.rajdhani(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16)),
        ],
      ),
    );
  }
}
