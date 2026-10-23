import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../game/models/card_icon.dart';

/// Một hang với con chuột chũi (hoặc nhân vật) trồi lên / thụt xuống.
///
/// Nhận toàn giá trị thô chứ không nhận model, để màn Hướng dẫn dựng được hình
/// minh hoạ mà không cần một ván chơi thật.
///
/// Dùng [TweenAnimationBuilder] thay vì [AnimationController]: mỗi hang tự chạy
/// tới vị trí đích khi [raised] đổi, nên bàn không cần quản lý hàng chục
/// controller và vòng đời của chúng.
class MoleHoleView extends StatelessWidget {
  static const Color _holeColor = Color(0xFF1A0F2E);
  static const Color _dirtDark = Color(0xFF5B3A24);
  static const Color _dirtLight = Color(0xFF8A5A36);

  final double width;
  final double height;

  /// Con trong hang đang ở trên mặt đất.
  final bool raised;

  /// Vừa bị đập trúng — mắt choáng + hiệu ứng "+1".
  final bool dazed;

  /// Nhân vật trồi lên. null = chuột chũi cổ điển.
  final CardIcon? icon;

  /// Thứ trồi lên là bom bẫy (bỏ qua [icon]). Bị đập thì hiện "-1" thay vì "+1".
  final bool isTrap;

  /// Màu người vừa đập trúng.
  final Color? hitAccent;

  /// Định danh con hiện tại — đổi thì hiệu ứng "+1" chạy lại.
  final int moleId;

  final VoidCallback? onTap;

  const MoleHoleView({
    required this.width,
    required this.height,
    required this.raised,
    this.dazed = false,
    this.icon,
    this.isTrap = false,
    this.hitAccent,
    this.moleId = 0,
    this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final size = math.min(width, height);
    final holeWidth = width * 0.84;
    final holeHeight = size * 0.3;
    // Tâm hang nằm ở 78% chiều cao ô; con vật "đứng" ở đó và bị cắt phía dưới.
    final holeCenterY = height * 0.78;
    final moleWidth = size * 0.62;
    final moleHeight = size * 0.66;

    return RepaintBoundary(
      child: GestureDetector(
        // onTapDown thay vì onTap: game phản xạ không thể chờ nhấc ngón tay.
        onTapDown: onTap == null ? null : (_) => onTap!(),
        behavior: HitTestBehavior.opaque,
        child: Semantics(
          button: onTap != null,
          label: raised ? (isTrap ? 'bomb' : 'mole') : 'hole',
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                // Miệng hang (phần tối phía sau con vật).
                Positioned(
                  left: (width - holeWidth) / 2,
                  top: holeCenterY - holeHeight / 2,
                  width: holeWidth,
                  height: holeHeight,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      color: _holeColor,
                      borderRadius:
                          BorderRadius.all(Radius.elliptical(200, 100)),
                    ),
                  ),
                ),
                // Con vật, bị cắt ở tâm hang nên trông như chui lên từ dưới đất.
                Positioned(
                  left: 0,
                  top: 0,
                  width: width,
                  height: holeCenterY,
                  child: ClipRect(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(end: raised ? 1 : 0),
                      duration: Duration(milliseconds: raised ? 130 : 190),
                      curve: raised ? Curves.easeOutBack : Curves.easeIn,
                      builder: (context, t, child) {
                        return Stack(
                          clipBehavior: Clip.none,
                          children: <Widget>[
                            Positioned(
                              left: (width - moleWidth) / 2,
                              top: holeCenterY - moleHeight * t,
                              width: moleWidth,
                              height: moleHeight,
                              child: child!,
                            ),
                          ],
                        );
                      },
                      child: isTrap
                          ? _Bomb(exploded: dazed)
                          : _Critter(icon: icon, dazed: dazed),
                    ),
                  ),
                ),
                // Mép đất phía trước che chân con vật.
                Positioned(
                  left: (width - holeWidth) / 2 - size * 0.04,
                  top: holeCenterY,
                  width: holeWidth + size * 0.08,
                  height: holeHeight * 0.62,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[_dirtLight, _dirtDark],
                      ),
                      borderRadius: BorderRadius.vertical(
                        bottom: Radius.elliptical(200, 80),
                        top: Radius.elliptical(200, 30),
                      ),
                    ),
                  ),
                ),
                if (dazed)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: holeCenterY - moleHeight - size * 0.12,
                    child: _HitBurst(
                      key: ValueKey<int>(moleId),
                      accent: isTrap
                          ? AppTheme.trapRed
                          : (hitAccent ?? AppTheme.sunGold),
                      label: isTrap ? '-1' : '+1',
                      decoration:
                          isTrap ? Icons.dangerous_rounded : Icons.star_rounded,
                      decorationColor:
                          isTrap ? AppTheme.trapRed : AppTheme.sunGold,
                      size: size,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Nhân vật trong hang: chuột chũi vẽ tay hoặc icon của bộ đã chọn.
class _Critter extends StatelessWidget {
  final CardIcon? icon;
  final bool dazed;

  const _Critter({required this.icon, required this.dazed});

  @override
  Widget build(BuildContext context) {
    final current = icon;
    final Widget body = current == null
        ? CustomPaint(painter: _MolePainter(dazed: dazed))
        // Neo đáy rồi đẩy xuống một chút để nhân vật bị miệng hang cắt chân,
        // giống chuột chũi vẽ tay. Căn theo đỉnh sẽ làm icon lơ lửng phía trên
        // hang — lộ rõ nhất ở nhóm đồ vật/trái cây vì PNG emoji chừa sẵn lề
        // trong suốt quanh hình.
        : Align(
            alignment: Alignment.bottomCenter,
            child: FractionalTranslation(
              translation: const Offset(0, 0.1),
              child: Image.asset(
                current.asset,
                package: 'main_app_package',
                fit: BoxFit.contain,
                // Con chỉ ở trên mặt đất dưới một giây: lọc mượt khi thu nhỏ
                // đáng giá hơn vài micro-giây tiết kiệm được.
                filterQuality: FilterQuality.medium,
              ),
            ),
          );

    // Bị đập thì bẹp xuống một chút.
    return AnimatedScale(
      scale: dazed ? 0.9 : 1,
      alignment: Alignment.bottomCenter,
      duration: const Duration(milliseconds: 90),
      child: body,
    );
  }
}

/// Chuột chũi cổ điển. Vẽ tay để không phải thêm asset và giấy phép mới.
class _MolePainter extends CustomPainter {
  final bool dazed;

  const _MolePainter({required this.dazed});

  static const Color _fur = Color(0xFF8B5A3C);
  static const Color _furShade = Color(0xFF6E442B);
  static const Color _face = Color(0xFFD8AE85);
  static const Color _nose = Color(0xFFFF7FA8);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Thân: khối bo tròn phía trên, kéo dài xuống dưới vùng bị cắt.
    final body = RRect.fromRectAndCorners(
      Rect.fromLTWH(w * 0.08, h * 0.04, w * 0.84, h * 1.1),
      topLeft: Radius.circular(w * 0.42),
      topRight: Radius.circular(w * 0.42),
    );
    canvas.drawRRect(body, Paint()..color = _fur);
    canvas.drawRRect(
      body.deflate(w * 0.01),
      Paint()
        ..color = _furShade
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.03,
    );

    // Mặt.
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.56), width: w * 0.6, height: h * 0.5),
      Paint()..color = _face,
    );

    // Má hồng.
    final blush = Paint()..color = AppTheme.alpha(_nose, 0.45);
    canvas.drawCircle(Offset(w * 0.28, h * 0.5), w * 0.07, blush);
    canvas.drawCircle(Offset(w * 0.72, h * 0.5), w * 0.07, blush);

    // Mắt.
    final eyeY = h * 0.34;
    final eyeDx = w * 0.15;
    if (dazed) {
      final stroke = Paint()
        ..color = Colors.black87
        ..strokeWidth = w * 0.035
        ..strokeCap = StrokeCap.round;
      final r = w * 0.05;
      for (final x in <double>[w * 0.5 - eyeDx, w * 0.5 + eyeDx]) {
        canvas
          ..drawLine(Offset(x - r, eyeY - r), Offset(x + r, eyeY + r), stroke)
          ..drawLine(Offset(x - r, eyeY + r), Offset(x + r, eyeY - r), stroke);
      }
    } else {
      final eye = Paint()..color = Colors.black87;
      final shine = Paint()..color = Colors.white;
      for (final x in <double>[w * 0.5 - eyeDx, w * 0.5 + eyeDx]) {
        canvas
          ..drawCircle(Offset(x, eyeY), w * 0.055, eye)
          ..drawCircle(
              Offset(x + w * 0.018, eyeY - w * 0.018), w * 0.018, shine);
      }
    }

    // Mũi.
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.47), width: w * 0.17, height: w * 0.12),
      Paint()..color = _nose,
    );

    // Răng cửa.
    final tooth = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.455, h * 0.53, w * 0.09, h * 0.08),
      Radius.circular(w * 0.015),
    );
    canvas.drawRRect(tooth, Paint()..color = Colors.white);
    canvas.drawLine(
      Offset(w * 0.5, h * 0.53),
      Offset(w * 0.5, h * 0.61),
      Paint()
        ..color = AppTheme.alpha(Colors.black, 0.25)
        ..strokeWidth = w * 0.01,
    );

    // Hai bàn tay bám mép hang.
    final paw = Paint()..color = _face;
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.24, h * 0.9), width: w * 0.22, height: h * 0.14),
      paw,
    );
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(w * 0.76, h * 0.9), width: w * 0.22, height: h * 0.14),
      paw,
    );
  }

  @override
  bool shouldRepaint(_MolePainter oldDelegate) => oldDelegate.dazed != dazed;
}

/// Bom bẫy. Vẽ tay như chuột chũi; viền đỏ nhấp nháy để người chơi phân biệt
/// được ngay cả khi liếc nhanh — chỉ khác hình dạng thôi là chưa đủ.
class _Bomb extends StatelessWidget {
  final bool exploded;

  const _Bomb({required this.exploded});

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: exploded ? 1.12 : 1,
      alignment: Alignment.bottomCenter,
      duration: const Duration(milliseconds: 90),
      child: CustomPaint(painter: _BombPainter(exploded: exploded)),
    );
  }
}

class _BombPainter extends CustomPainter {
  final bool exploded;

  const _BombPainter({required this.exploded});

  static const Color _shell = Color(0xFF2B2B33);
  static const Color _shellLight = Color(0xFF55555F);
  static const Color _fuse = Color(0xFFC9A66B);
  static const Color _spark = Color(0xFFFFB13B);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w * 0.5, h * 0.62);
    final radius = math.min(w, h) * 0.36;

    // Quầng đỏ cảnh báo phía sau.
    canvas.drawCircle(
      center,
      radius * 1.18,
      Paint()..color = AppTheme.alpha(AppTheme.trapRed, exploded ? 0.65 : 0.35),
    );

    // Thân bom.
    canvas.drawCircle(
        center, radius, Paint()..color = exploded ? AppTheme.trapRed : _shell);
    canvas.drawCircle(
      center.translate(-radius * 0.35, -radius * 0.35),
      radius * 0.22,
      Paint()..color = AppTheme.alpha(Colors.white, 0.25),
    );

    // Nắp ngòi.
    final capRect = Rect.fromCenter(
      center: Offset(w * 0.5, center.dy - radius * 0.98),
      width: radius * 0.5,
      height: radius * 0.3,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(capRect, Radius.circular(radius * 0.06)),
      Paint()..color = _shellLight,
    );

    // Ngòi cong.
    final fuseStart = Offset(w * 0.5, capRect.top);
    final fuseEnd = Offset(w * 0.5 + radius * 0.5, capRect.top - radius * 0.45);
    final fuse = Path()
      ..moveTo(fuseStart.dx, fuseStart.dy)
      ..quadraticBezierTo(
        w * 0.5 + radius * 0.05,
        fuseEnd.dy,
        fuseEnd.dx,
        fuseEnd.dy,
      );
    canvas.drawPath(
      fuse,
      Paint()
        ..color = _fuse
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.1
        ..strokeCap = StrokeCap.round,
    );

    // Tia lửa đầu ngòi.
    canvas
      ..drawCircle(fuseEnd, radius * 0.16, Paint()..color = _spark)
      ..drawCircle(fuseEnd, radius * 0.07, Paint()..color = Colors.white);

    // Dấu chấm than trên thân — đọc được cả khi không phân biệt được màu.
    final mark = Paint()
      ..color = Colors.white
      ..strokeWidth = radius * 0.16
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(
        center.translate(0, -radius * 0.45),
        center.translate(0, radius * 0.12),
        mark,
      )
      ..drawCircle(center.translate(0, radius * 0.42), radius * 0.09,
          Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_BombPainter oldDelegate) =>
      oldDelegate.exploded != exploded;
}

/// "+1" (hoặc "-1" khi dính bom) bay lên khi đập trúng.
class _HitBurst extends StatelessWidget {
  final Color accent;
  final String label;
  final IconData decoration;
  final Color decorationColor;
  final double size;

  const _HitBurst({
    required this.accent,
    required this.label,
    required this.decoration,
    required this.decorationColor,
    required this.size,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOut,
        builder: (context, t, _) {
          return Opacity(
            opacity: (1 - t * 0.6).clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, -size * 0.12 * t),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(decoration, size: size * 0.16, color: decorationColor),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: size * 0.2,
                      fontWeight: FontWeight.w900,
                      color: accent,
                      shadows: const <Shadow>[
                        Shadow(color: Colors.black54, blurRadius: 4),
                      ],
                    ),
                  ),
                  Icon(decoration, size: size * 0.16, color: decorationColor),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
