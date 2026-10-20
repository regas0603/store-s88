import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_settings.dart';
import '../../core/game_analysis.dart';
import '../../core/game_history.dart';
import '../../core/l10n.dart';
import '../../core/quality_palette.dart';
import '../../core/text_app_style.dart';
import '../widgets/replay_board_painter.dart';
import 'analysis_progress_dialog.dart';
import 'widgets/accuracy_summary.dart';
import 'widgets/advantage_chart.dart';
import 'widgets/quality_banner.dart';

/// Màn hình xem lại ván có chấm điểm từng nước (US-005).
///
/// Mở rộng ý tưởng của `ReplayScreen` thay vì làm màn hình hoàn toàn mới:
/// replay và phân tích là cùng một tương tác (tua qua các nước trên bàn cờ),
/// tách ra sẽ nhân đôi logic dựng bàn và điều khiển tua.
class AnalysisReplayScreen extends StatefulWidget {
  final GameRecord record;
  final GameAnalysis analysis;

  const AnalysisReplayScreen({
    super.key,
    required this.record,
    required this.analysis,
  });

  @override
  State<AnalysisReplayScreen> createState() => _AnalysisReplayScreenState();
}

class _AnalysisReplayScreenState extends State<AnalysisReplayScreen>
    with SingleTickerProviderStateMixin {
  late GameRecord _record = widget.record;
  late GameAnalysis _analysis = widget.analysis;

  late final List<MoveLog> _moves = _record.moves;
  int _currentIdx = 0;
  bool _playing = false;
  double _speed = 1.0;
  Timer? _timer;

  /// Nhấp nháy vòng "nước tốt hơn". 1400ms/chu kỳ — chậm có chủ đích, nhanh
  /// hơn sẽ gây khó chịu và là rủi ro với người nhạy ánh sáng.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  PieceSkin get _skin => PieceSkin.values.firstWhere(
        (PieceSkin s) => s.name == _record.skinName,
        orElse: () => PieceSkin.neon,
      );

  int get _boardSize => _record.boardSide;
  int get _winLength => _record.winLength;
  bool get _isPvp => _record.mode == GameMode.twoPlayers;

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  // ─── Điều khiển tua ────────────────────────────────────────────────────

  void _togglePlay() {
    setState(() => _playing = !_playing);
    if (_playing) {
      if (_currentIdx >= _moves.length) _currentIdx = 0;
      _scheduleNext();
    } else {
      _timer?.cancel();
    }
  }

  void _scheduleNext() {
    _timer?.cancel();
    final Duration interval =
        Duration(milliseconds: (600 / _speed).round().clamp(80, 2000));
    _timer = Timer(interval, () {
      if (!mounted) return;
      if (_currentIdx >= _moves.length) {
        setState(() => _playing = false);
        return;
      }
      setState(() => _currentIdx++);
      if (_playing && _currentIdx < _moves.length) {
        _scheduleNext();
      } else {
        setState(() => _playing = false);
      }
    });
  }

  void _seek(int index) {
    _timer?.cancel();
    setState(() {
      _currentIdx = index.clamp(0, _moves.length);
      _playing = false;
    });
  }

  // ─── Dựng bàn cờ ───────────────────────────────────────────────────────

  List<List<int>> _buildBoard() {
    final List<List<int>> board = List<List<int>>.generate(
      _boardSize,
      (_) => List<int>.filled(_boardSize, 0),
    );
    for (int i = 0; i < _currentIdx && i < _moves.length; i++) {
      final MoveLog m = _moves[i];
      if (m.removedRow != null && m.removedCol != null) {
        board[m.removedRow!][m.removedCol!] = 0;
      }
      board[m.row][m.col] = m.player;
    }
    return board;
  }

  List<(int, int)>? _winningCells(List<List<int>> board) {
    if (_currentIdx < _moves.length) return null;
    if (_record.result != GameResult.xWins &&
        _record.result != GameResult.oWins) {
      return null;
    }
    if (_moves.isEmpty) return null;
    final MoveLog last = _moves.last;
    return _checkWinFrom(board, last.row, last.col, last.player);
  }

  List<(int, int)>? _checkWinFrom(
      List<List<int>> board, int row, int col, int player) {
    const List<(int, int)> dirs = <(int, int)>[(0, 1), (1, 0), (1, 1), (1, -1)];
    for (final (int dr, int dc) in dirs) {
      final List<(int, int)> cells = <(int, int)>[(row, col)];
      for (int i = 1; i < _winLength; i++) {
        final int nr = row + dr * i, nc = col + dc * i;
        if (nr < 0 || nr >= _boardSize || nc < 0 || nc >= _boardSize) break;
        if (board[nr][nc] == player) {
          cells.add((nr, nc));
        } else {
          break;
        }
      }
      for (int i = 1; i < _winLength; i++) {
        final int nr = row - dr * i, nc = col - dc * i;
        if (nr < 0 || nr >= _boardSize || nc < 0 || nc >= _boardSize) break;
        if (board[nr][nc] == player) {
          cells.add((nr, nc));
        } else {
          break;
        }
      }
      if (cells.length >= _winLength) return cells;
    }
    return null;
  }

  // ─── Dữ liệu phân tích của nước đang xem ───────────────────────────────

  int? get _currentMoveIndex =>
      (_currentIdx > 0 && _currentIdx <= _moves.length) ? _currentIdx - 1 : null;

  MoveAnalysis? get _currentAnalysis {
    final int? i = _currentMoveIndex;
    if (i == null) return null;
    if (!_analysis.isScored(i)) return null;
    if (i >= _analysis.moveAnalyses.length) return null;
    return _analysis.moveAnalyses[i];
  }

  /// Nhãn theo ô cho chế độ huy hiệu — chỉ những nước đã hiện trên bàn.
  Map<int, MoveQuality> get _cellQualities {
    final Map<int, MoveQuality> out = <int, MoveQuality>{};
    for (int i = 0; i < _currentIdx && i < _moves.length; i++) {
      if (!_analysis.isScored(i)) continue;
      if (i >= _analysis.moveAnalyses.length) continue;
      final MoveLog m = _moves[i];
      out[m.row * _boardSize + m.col] = _analysis.moveAnalyses[i].quality;
    }
    return out;
  }

  // ─── Hành động ─────────────────────────────────────────────────────────

  Future<void> _reanalyzeDeep() async {
    final GameAnalysis? fresh = await runAnalysisWithDialog(context, _record);
    if (fresh == null || !mounted) return;
    setState(() {
      _analysis = fresh;
      _record = _record.copyWithAnalysis(fresh);
    });
  }

  Future<void> _share() async {
    try {
      final String base = l10n.shareMessage(
        vsAI: _record.mode == GameMode.vsAI,
        result: _record.result,
        totalMoves: _record.totalMoves,
        durationSecs: _record.durationSecs,
        boardSide: _record.boardSide,
        winLength: _record.winLength,
      );
      final String text =
          '$base\n${l10n.formatAccuracyLine(_analysis.accuracyX)}';
      // Dùng đúng API mà result_screen.dart đang dùng (share_plus 10.1.2),
      // không đổi sang SharePlus.instance để tránh lệch phiên bản.
      await Share.share(text, subject: l10n.shareSubject);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.shareError)),
      );
    }
  }

  /// Chạm vào băng chất lượng -> làm nổi ô "nước tốt hơn" một nhịp rõ rệt.
  ///
  /// Vòng gợi ý đã hiển thị sẵn ở nước đang xem, nên không cần nhảy đi đâu cả;
  /// việc cần làm là kéo mắt người dùng về đúng ô đó. Reset chu kỳ nhấp nháy
  /// khiến vòng sáng bừng lên từ đầu, kèm một nhịp haptic để xác nhận cú chạm.
  void _jumpToBetterMove() {
    final MoveAnalysis? cur = _currentAnalysis;
    if (cur == null || !cur.hasBetterMove) return;
    _timer?.cancel();
    if (_playing) setState(() => _playing = false);
    HapticFeedback.selectionClick();
    if (!MediaQuery.of(context).disableAnimations) {
      _pulse
        ..reset()
        ..repeat(reverse: true);
    }
  }

  void _openSpeedMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            color: QualityPalette.surfaceCard,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                l10n.analysisSpeed,
                style: TextAppStyle.ui(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: <double>[0.5, 1.0, 2.0, 4.0].map((double s) {
                  final bool active = (s - _speed).abs() < 0.01;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _speed = s);
                          if (_playing) _scheduleNext();
                          Navigator.of(ctx).pop();
                        },
                        child: Container(
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: active
                                ? _skin.xColor.withValues(alpha: 0.2)
                                : Colors.white.withValues(alpha: 0.05),
                            border: Border.all(
                              color: active
                                  ? _skin.xColor
                                  : Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          child: Text(
                            '${s}x',
                            style: TextAppStyle.rajdhani(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: active
                                  ? _skin.xColor
                                  : Colors.white.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final List<List<int>> board = _buildBoard();
    final int? mi = _currentMoveIndex;
    final (int, int)? lastMove =
        mi == null ? null : (_moves[mi].row, _moves[mi].col);
    final List<(int, int)>? winCells = _winningCells(board);
    final MoveAnalysis? cur = _currentAnalysis;

    final (int, int)? betterCell =
        (cur != null && cur.hasBetterMove) ? (cur.betterRow!, cur.betterCol!) : null;

    // Người dùng tắt animation ở cấp hệ thống -> không nhấp nháy, thay bằng
    // vòng nét đứt tĩnh (alpha cố định).
    final bool reduceMotion = MediaQuery.of(context).disableAnimations;

    return Scaffold(
      backgroundColor: QualityPalette.surfaceScreen,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: <Widget>[
              _buildHeader(),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: AccuracyStrip(
                  analysis: _analysis,
                  isPvp: _isPvp,
                  onTap: () => showAccuracySheet(
                    context,
                    analysis: _analysis,
                    record: _record,
                    onShare: _share,
                  ),
                ),
              ),
              if (_analysis.isShallow) _buildShallowWarning(),
              const SizedBox(height: 14),
              _buildBoardArea(board, lastMove, winCells, cur, betterCell,
                  reduceMotion, context),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: QualityBanner(
                  analysis: cur,
                  moveNumber: (mi ?? 0) + 1,
                  row: mi == null ? -1 : _moves[mi].row,
                  col: mi == null ? -1 : _moves[mi].col,
                  onTapBetter: _jumpToBetterMove,
                  emptyText: mi == null
                      ? l10n.analysisStartHint
                      : l10n.analysisAiMove,
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: AdvantageChart(
                  analysis: _analysis,
                  skin: _skin,
                  currentIndex: _currentIdx,
                  onSeek: _seek,
                ),
              ),
              const SizedBox(height: 13),
              Text(
                '${l10n.replayMoveCounter} $_currentIdx / ${_moves.length}',
                style: TextAppStyle.rajdhani(
                  fontSize: 14,
                  letterSpacing: 1.5,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
              _buildSlider(),
              const SizedBox(height: 12),
              _buildControls(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 8, 0),
      child: Row(
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Text(
              l10n.analysisTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextAppStyle.rajdhani(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
                color: Colors.white,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.speed_rounded,
                color: Colors.white.withValues(alpha: 0.55)),
            onPressed: _openSpeedMenu,
            tooltip: l10n.analysisSpeed,
          ),
          IconButton(
            icon: Icon(Icons.info_outline_rounded,
                color: Colors.white.withValues(alpha: 0.55)),
            onPressed: () => showHowToReadSheet(context),
            tooltip: l10n.analysisHowToRead,
          ),
        ],
      ),
    );
  }

  /// Chip cảnh báo khi phải cắt pass đào sâu. Cố ý KHÔNG ẩn đi — minh bạch
  /// quan trọng hơn việc tránh làm người dùng lo.
  Widget _buildShallowWarning() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: QualityPalette.inaccuracy.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.speed_rounded,
                      size: 14, color: QualityPalette.inaccuracy),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.analysisShallowWarning,
                      style: TextAppStyle.ui(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: QualityPalette.inaccuracy,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _reanalyzeDeep,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.18)),
              ),
              child: Text(
                l10n.analysisRedoDeep,
                style: TextAppStyle.ui(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoardArea(
    List<List<int>> board,
    (int, int)? lastMove,
    List<(int, int)>? winCells,
    MoveAnalysis? cur,
    (int, int)? betterCell,
    bool reduceMotion,
    BuildContext context,
  ) {
    // Dựng MỘT LẦN ở đây, không gọi trong closure của AnimatedBuilder: getter
    // này duyệt toàn bộ nước đã đánh và cấp phát Map mới, mà closure chạy lại
    // mỗi khung hình của hiệu ứng nhấp nháy.
    final Map<int, MoveQuality> qualities = _cellQualities;
    // Giới hạn 42% chiều cao màn hình để 3 khối mới (thẻ tổng kết, băng chất
    // lượng, biểu đồ) vẫn còn chỗ trên máy nhỏ.
    final double maxSide = MediaQuery.of(context).size.height * 0.42;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSide),
        child: AspectRatio(
          aspectRatio: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    AppSettings().boardBackground.colorA,
                    AppSettings().boardBackground.colorB,
                  ],
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: _skin.xColor.withValues(alpha: 0.15),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (BuildContext context, _) {
                    final double pulseValue = reduceMotion
                        ? 1.0
                        : 0.45 + 0.55 * Curves.easeInOut.transform(_pulse.value);
                    return CustomPaint(
                      painter: ReplayBoardPainter(
                        board: board,
                        boardSize: _boardSize,
                        skin: _skin,
                        lastMove: lastMove,
                        winCells: winCells,
                        lastMoveQuality: cur?.quality,
                        cellQualities: qualities,
                        betterCell: betterCell,
                        betterPulse: pulseValue,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSlider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SliderTheme(
        data: SliderThemeData(
          trackHeight: 4,
          activeTrackColor: _skin.xColor,
          inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
          thumbColor: _skin.xColor,
          overlayColor: _skin.xColor.withValues(alpha: 0.2),
        ),
        child: Slider(
          min: 0,
          max: _moves.length.toDouble(),
          value: _currentIdx.toDouble().clamp(0, _moves.length.toDouble()),
          onChanged:
              _moves.isEmpty ? null : (double v) => _seek(v.round()),
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        _iconButton(
          icon: Icons.refresh_rounded,
          onTap: _moves.isEmpty ? null : () => _seek(0),
        ),
        const SizedBox(width: 24),
        GestureDetector(
          onTap: _moves.isEmpty ? null : _togglePlay,
          child: Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: <Color>[
                  _skin.xColor,
                  _skin.xColor.withValues(alpha: 0.7),
                ],
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                    color: _skin.xColor.withValues(alpha: 0.4), blurRadius: 16),
              ],
            ),
            child: Icon(
              _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.black87,
              size: 36,
            ),
          ),
        ),
        const SizedBox(width: 24),
        _iconButton(
          icon: Icons.skip_next_rounded,
          onTap: _moves.isEmpty ? null : () => _seek(_moves.length),
        ),
      ],
    );
  }

  Widget _iconButton({required IconData icon, required VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.3 : 1.0,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.08),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}
