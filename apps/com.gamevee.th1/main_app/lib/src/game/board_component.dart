import 'dart:math';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import '../core/app_settings.dart';
import 'caro_game.dart';

// ─── BoardComponent ───────────────────────────────────────────────────────────

class BoardComponent extends PositionComponent with TapCallbacks {
  final CaroGame game;

  double _cellSize = 0;
  double _boardPixelSize = 0;

  // Public getters — luôn tính từ kích thước hiện tại
  double get cellSize => _cellSize;
  double get offsetX => (game.size.x - _boardPixelSize) / 2;
  double get offsetY => (game.size.y - _boardPixelSize) / 2;

  final Map<String, PieceComponent> _pieces = {};
  final List<WinLineComponent> _winLines = [];

  BoardComponent({required this.game});

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    // Tính kích thước ô dựa trên cạnh nhỏ hơn, trừ padding
    final available = min(size.x, size.y) - 16;
    _cellSize = available / game.boardSize;
    _boardPixelSize = _cellSize * game.boardSize;
    this.size = Vector2(size.x, size.y);
    position = Vector2.zero();

    // Cập nhật vị trí TẤT CẢ pieces và win lines khi resize
    for (final piece in _pieces.values) {
      piece.syncLayout();
    }
    for (final line in _winLines) {
      line.syncLayout();
    }
  }

  // ─── Render grid ───────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas) {
    _drawBackground(canvas);
    _drawGrid(canvas);
    _drawStarPoints(canvas);
  }

  void _drawBackground(Canvas canvas) {
    final ox = offsetX;
    final oy = offsetY;
    final BoardBackground bg = AppSettings().boardBackground;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [bg.colorA, bg.colorB],
      ).createShader(
          Rect.fromLTWH(ox, oy, _boardPixelSize, _boardPixelSize));

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(ox - 4, oy - 4, _boardPixelSize + 8, _boardPixelSize + 8),
        const Radius.circular(12),
      ),
      paint,
    );

    final skin = AppSettings().skin;
    final borderPaint = Paint()
      ..color = Color.lerp(bg.colorA, skin.xColor, 0.35)!.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(ox - 4, oy - 4, _boardPixelSize + 8, _boardPixelSize + 8),
        const Radius.circular(12),
      ),
      borderPaint,
    );
  }

  void _drawGrid(Canvas canvas) {
    final ox = offsetX;
    final oy = offsetY;
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 0.7;
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..strokeWidth = 1.5;

    for (int i = 0; i <= game.boardSize; i++) {
      final isEdge = i == 0 || i == game.boardSize;
      final p = isEdge ? borderPaint : linePaint;
      // Vertical
      canvas.drawLine(
        Offset(ox + i * _cellSize, oy),
        Offset(ox + i * _cellSize, oy + _boardPixelSize),
        p,
      );
      // Horizontal
      canvas.drawLine(
        Offset(ox, oy + i * _cellSize),
        Offset(ox + _boardPixelSize, oy + i * _cellSize),
        p,
      );
    }
  }

  void _drawStarPoints(Canvas canvas) {
    final int n = game.boardSize;
    if (n < 7) {
      return;
    }
    final ox = offsetX;
    final oy = offsetY;
    final skin = AppSettings().skin;
    final Paint paint = Paint()..color = skin.xColor.withValues(alpha: 0.4);
    final List<(int, int)> stars = _starIntersections(n);
    for (final (int row, int col) in stars) {
      canvas.drawCircle(
        Offset(
          ox + (col + 0.5) * _cellSize,
          oy + (row + 0.5) * _cellSize,
        ),
        3,
        paint,
      );
    }
  }

  /// Hoshi-style star points; empty for small or even sizes.
  static List<(int, int)> _starIntersections(int n) {
    if (n < 7 || n.isEven) {
      return const <(int, int)>[];
    }
    final int a = (n - 1) ~/ 4;
    final int b = (n - 1) ~/ 2;
    return <(int, int)>[
      (a, a),
      (a, n - 1 - a),
      (n - 1 - a, a),
      (n - 1 - a, n - 1 - a),
      (b, b),
    ];
  }

  // ─── Tap detection ─────────────────────────────────────────────────────────

  @override
  bool onTapDown(TapDownEvent event) {
    if (_cellSize <= 0) return true;
    final ox = offsetX;
    final oy = offsetY;
    final lx = event.localPosition.x;
    final ly = event.localPosition.y;

    // Tính ô được tap
    final col = ((lx - ox) / _cellSize).floor();
    final row = ((ly - oy) / _cellSize).floor();

    if (row >= 0 &&
        row < game.boardSize &&
        col >= 0 &&
        col < game.boardSize) {
      game.handleTap(row, col);
    }
    return true;
  }

  // ─── Piece management ──────────────────────────────────────────────────────

  void addPiece(int row, int col, int player) {
    final key = '$row,$col';
    final piece = PieceComponent(
      row: row,
      col: col,
      player: player,
      board: this,
    );
    _pieces[key] = piece;
    add(piece);
  }

  void removePiece(int row, int col) {
    final key = '$row,$col';
    final piece = _pieces.remove(key);
    piece?.removeFromParent();
  }

  void highlightWin(List<Point<int>> cells) {
    final line = WinLineComponent(cells: cells, board: this);
    _winLines.add(line);
    add(line);
    for (final piece in _pieces.values) {
      if (cells.any((c) => c.x == piece.row && c.y == piece.col)) {
        piece.startWinAnimation();
      }
    }
  }

  void resetAnimations() {
    for (final piece in _pieces.values) {
      piece.removeFromParent();
    }
    _pieces.clear();
    for (final line in _winLines) {
      line.removeFromParent();
    }
    _winLines.clear();
  }
}

// ─── PieceComponent ───────────────────────────────────────────────────────────

class PieceComponent extends PositionComponent {
  final int row;
  final int col;
  final int player;
  final BoardComponent board; // tham chiếu board để lấy layout động

  double _scale = 0;
  double _rotation = 0;
  bool _animating = true;
  bool _winning = false;
  double _winPulse = 0;
  bool _winPulseUp = true;
  double _elapsed = 0;
  static const _dropDuration = 0.22;

  PieceComponent({
    required this.row,
    required this.col,
    required this.player,
    required this.board,
  });

  @override
  Future<void> onLoad() async {
    syncLayout();
  }

  /// Gọi khi board resize để cập nhật position/size
  void syncLayout() {
    final cs = board.cellSize;
    final ox = board.offsetX;
    final oy = board.offsetY;
    size = Vector2(cs, cs);
    position = Vector2(ox + col * cs, oy + row * cs);
  }

  @override
  void update(double dt) {
    if (_animating) {
      _elapsed += dt;
      final t = (_elapsed / _dropDuration).clamp(0.0, 1.0);
      _scale = _easeOutBack(t);
      _rotation = (1 - t) * 0.4;
      if (t >= 1.0) _animating = false;
    }
    if (_winning) {
      const speed = 3.0;
      if (_winPulseUp) {
        _winPulse += dt * speed;
        if (_winPulse >= 1) {
          _winPulse = 1;
          _winPulseUp = false;
        }
      } else {
        _winPulse -= dt * speed;
        if (_winPulse <= 0) {
          _winPulse = 0;
          _winPulseUp = true;
        }
      }
    }
  }

  double _easeOutBack(double t) {
    const c1 = 1.70158, c3 = c1 + 1;
    return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2);
  }

  void startWinAnimation() => _winning = true;

  @override
  void render(Canvas canvas) {
    if (_scale <= 0) return;
    final cs = board.cellSize;
    final skin = AppSettings().skin;
    // Bán kính vẽ dựa trên cellSize hiện tại (động)
    final r = (cs / 2) * 0.78;

    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);
    canvas.rotate(_rotation);
    canvas.scale(_scale);

    if (player == 1) {
      _drawX(canvas, r * 0.65, skin.xColor, _winning, _winPulse);
    } else {
      _drawO(canvas, r * 0.72, skin.oColor, _winning, _winPulse);
    }
    canvas.restore();
  }

  void _drawX(Canvas canvas, double r, Color color, bool winning, double pulse) {
    final c = winning ? Color.lerp(color, Colors.white, pulse * 0.5)! : color;
    final glowPaint = Paint()
      ..color = c.withValues(alpha: 0.3 + (winning ? pulse * 0.3 : 0))
      ..strokeWidth = (r * 0.55) + (winning ? pulse * 4 : 0)
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    final mainPaint = Paint()
      ..color = c
      ..strokeWidth = r * 0.45
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final p in [glowPaint, mainPaint]) {
      canvas.drawLine(Offset(-r, -r), Offset(r, r), p);
      canvas.drawLine(Offset(r, -r), Offset(-r, r), p);
    }
  }

  void _drawO(Canvas canvas, double r, Color color, bool winning, double pulse) {
    final c = winning ? Color.lerp(color, Colors.white, pulse * 0.5)! : color;
    final glowPaint = Paint()
      ..color = c.withValues(alpha: 0.3 + (winning ? pulse * 0.3 : 0))
      ..strokeWidth = (r * 0.45) + (winning ? pulse * 4 : 0)
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    final mainPaint = Paint()
      ..color = c
      ..strokeWidth = r * 0.38
      ..style = PaintingStyle.stroke;
    for (final p in [glowPaint, mainPaint]) {
      canvas.drawCircle(Offset.zero, r, p);
    }
  }
}

// ─── WinLineComponent ─────────────────────────────────────────────────────────

class WinLineComponent extends PositionComponent {
  final List<Point<int>> cells;
  final BoardComponent board;

  double _progress = 0;
  double _glow = 0;
  bool _glowUp = true;

  WinLineComponent({required this.cells, required this.board});

  @override
  Future<void> onLoad() async {
    syncLayout();
  }

  void syncLayout() {
    // WinLine không dùng position component — vẽ trực tiếp từ board offsets
    size = Vector2(board.game.size.x, board.game.size.y);
    position = Vector2.zero();
  }

  @override
  void update(double dt) {
    _progress = (_progress + dt * 3).clamp(0.0, 1.0);
    if (_glowUp) {
      _glow += dt * 2;
      if (_glow >= 1) {
        _glow = 1;
        _glowUp = false;
      }
    } else {
      _glow -= dt * 2;
      if (_glow <= 0.3) {
        _glow = 0.3;
        _glowUp = true;
      }
    }
  }

  @override
  void render(Canvas canvas) {
    if (cells.length < 2) return;
    // Lấy layout động từ board
    final cs = board.cellSize;
    final ox = board.offsetX;
    final oy = board.offsetY;

    final sorted = List<Point<int>>.from(cells)
      ..sort((a, b) => a.x != b.x ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
    final start = sorted.first;
    final end = sorted.last;

    // Tọa độ trung tâm ô
    final sx = ox + (start.y + 0.5) * cs;
    final sy = oy + (start.x + 0.5) * cs;
    final ex = ox + (end.y + 0.5) * cs;
    final ey = oy + (end.x + 0.5) * cs;

    final cx = sx + (ex - sx) * _progress;
    final cy = sy + (ey - sy) * _progress;

    canvas.drawLine(
      Offset(sx, sy),
      Offset(cx, cy),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.4 * _glow)
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawLine(
      Offset(sx, sy),
      Offset(cx, cy),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9 * _glow)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }
}
