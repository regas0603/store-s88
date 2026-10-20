import 'dart:async';
import 'package:flutter/material.dart';
import '../core/app_settings.dart';
import '../core/game_history.dart';
import '../core/l10n.dart';
import '../core/text_app_style.dart';
import 'widgets/replay_board_painter.dart';

/// Phát lại ván cờ từ [GameRecord]. Render bằng CustomPaint (không dùng Flame),
/// hỗ trợ play/pause, scrub slider, đổi tốc độ, và highlight nước cuối (win line).
class ReplayScreen extends StatefulWidget {
  final GameRecord record;

  const ReplayScreen({super.key, required this.record});

  @override
  State<ReplayScreen> createState() => _ReplayScreenState();
}

class _ReplayScreenState extends State<ReplayScreen> {
  late final List<MoveLog> _moves = widget.record.moves;
  int _currentIdx = 0; // 0 = empty; _moves.length = all played
  bool _playing = false;
  double _speed = 1.0;
  Timer? _timer;

  PieceSkin get _skin {
    // Skin tên được lưu khi chơi — resolve về enum, fallback neon nếu lỗi.
    return PieceSkin.values.firstWhere(
      (PieceSkin s) => s.name == widget.record.skinName,
      orElse: () => PieceSkin.neon,
    );
  }

  int get _boardSize => widget.record.boardSide;
  int get _winLength => widget.record.winLength;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

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
    final Duration interval = Duration(
      milliseconds: (600 / _speed).round().clamp(80, 2000),
    );
    _timer = Timer(interval, () {
      if (!mounted) return;
      if (_currentIdx >= _moves.length) {
        setState(() => _playing = false);
        return;
      }
      setState(() => _currentIdx++);
      if (_playing && _currentIdx < _moves.length) _scheduleNext();
      if (_currentIdx >= _moves.length) setState(() => _playing = false);
    });
  }

  void _reset() {
    _timer?.cancel();
    setState(() {
      _currentIdx = 0;
      _playing = false;
    });
  }

  void _seek(double v) {
    _timer?.cancel();
    setState(() {
      _currentIdx = v.round().clamp(0, _moves.length);
      _playing = false;
    });
  }

  void _setSpeed(double s) {
    setState(() => _speed = s);
    if (_playing) _scheduleNext();
  }

  /// Dựng lại trạng thái bàn cờ tại _currentIdx nước đi, áp dụng sliding-cap
  /// (nếu record có removedRow/removedCol → nghĩa là đã xoá quân cũ).
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

  /// Check winning cells khi replay đã phát hết và record là xWins/oWins.
  List<(int, int)>? _winningCells(List<List<int>> board) {
    if (_currentIdx < _moves.length) return null;
    if (widget.record.result != GameResult.xWins &&
        widget.record.result != GameResult.oWins) {
      return null;
    }
    if (_moves.isEmpty) return null;
    final MoveLog last = _moves.last;
    return _checkWinFrom(board, last.row, last.col, last.player);
  }

  List<(int, int)>? _checkWinFrom(List<List<int>> board, int row, int col, int player) {
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

  @override
  Widget build(BuildContext context) {
    final List<List<int>> board = _buildBoard();
    final (int, int)? lastMove = _currentIdx > 0 && _currentIdx <= _moves.length
        ? (_moves[_currentIdx - 1].row, _moves[_currentIdx - 1].col)
        : null;
    final List<(int, int)>? winCells = _winningCells(board);

    return Scaffold(
      backgroundColor: const Color(0xFF070714),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _buildHeader(),
            const SizedBox(height: 8),
            _buildCounter(),
            const SizedBox(height: 16),
            Expanded(
              child: Center(
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
                      child: CustomPaint(
                        painter: ReplayBoardPainter(
                          board: board,
                          boardSize: _boardSize,
                          skin: _skin,
                          lastMove: lastMove,
                          winCells: winCells,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildSlider(),
            const SizedBox(height: 12),
            _buildControls(),
            const SizedBox(height: 12),
            _buildSpeedSelector(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
          Text(
            l10n.replayTitle,
            style: TextAppStyle.pressStart2p(
              color: Colors.white,
              fontSize: 16,
            ).copyWith(letterSpacing: 2),
          ),
        ],
      ),
    );
  }

  Widget _buildCounter() {
    return Text(
      '${l10n.replayMoveCounter} $_currentIdx / ${_moves.length}',
      style: TextAppStyle.rajdhani(
        color: Colors.white.withValues(alpha: 0.7),
        fontSize: 14,
        letterSpacing: 1.5,
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
          onChanged: _moves.isEmpty ? null : _seek,
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
          label: l10n.replayRestart,
          onTap: _moves.isEmpty ? null : _reset,
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
          label: '',
          onTap: _moves.isEmpty
              ? null
              : () {
                  _timer?.cancel();
                  setState(() {
                    _currentIdx = _moves.length;
                    _playing = false;
                  });
                },
        ),
      ],
    );
  }

  Widget _iconButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.3 : 1.0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            if (label.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                label,
                style: TextAppStyle.ui(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSpeedSelector() {
    const List<double> speeds = <double>[0.5, 1.0, 2.0, 4.0];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Text(
          '${l10n.replaySpeed}:',
          style: TextAppStyle.ui(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 12,
          ),
        ),
        const SizedBox(width: 8),
        ...speeds.map((double s) {
          final bool active = (s - _speed).abs() < 0.01;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () => _setSpeed(s),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
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
                    color: active
                        ? _skin.xColor
                        : Colors.white.withValues(alpha: 0.7),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}
