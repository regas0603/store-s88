import 'package:flutter/material.dart';
import '../core/app_settings.dart';
import '../core/l10n.dart';
import '../core/text_app_style.dart';
import 'home_screen.dart';

/// 3-slide first-run walkthrough. Gọi [show] lần đầu app mở.
/// Sau khi user bấm "Bắt đầu" hoặc "Bỏ qua", flag [AppSettings.hasSeenOnboarding]
/// được set → lần sau splash sẽ route thẳng vào HomeScreen.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageCtrl = PageController();
  int _page = 0;

  late final AnimationController _bgCtrl;

  @override
  void initState() {
    super.initState();
    _bgCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _bgCtrl.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await AppSettings().setHasSeenOnboarding(true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => const HomeScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  void _next() {
    if (_page >= 2) {
      _finish();
      return;
    }
    _pageCtrl.nextPage(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<_Slide> slides = <_Slide>[
      _Slide(
        icon: Icons.videogame_asset_rounded,
        color: const Color(0xFF4fc3f7),
        title: l10n.onboardingTitle1,
        body: l10n.onboardingBody1,
        art: const _BoardArt(
          rows: 3,
          pattern: <(int, int, int)>[
            (0, 0, 1),
            (1, 1, 2),
            (0, 2, 1),
            (2, 0, 2),
          ],
        ),
      ),
      _Slide(
        icon: Icons.people_alt_rounded,
        color: const Color(0xFFf48fb1),
        title: l10n.onboardingTitle2,
        body: l10n.onboardingBody2,
        art: const _TwoModesArt(),
      ),
      _Slide(
        icon: Icons.rule_rounded,
        color: const Color(0xFFFFD700),
        title: l10n.onboardingTitle3,
        body: l10n.onboardingBody3,
        art: const _WinRulesArt(),
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF070714),
      body: AnimatedBuilder(
        animation: _bgCtrl,
        builder: (BuildContext context, _) {
          return Stack(
            children: <Widget>[
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(-1.0, -1.0 + _bgCtrl.value * 0.3),
                      end: Alignment(1.0, 1.0 - _bgCtrl.value * 0.3),
                      colors: const <Color>[
                        Color(0xFF0a0a24),
                        Color(0xFF1a1a3e),
                        Color(0xFF070714),
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: <Widget>[
                    _buildTopBar(),
                    Expanded(
                      child: PageView.builder(
                        controller: _pageCtrl,
                        itemCount: slides.length,
                        onPageChanged: (int i) => setState(() => _page = i),
                        itemBuilder: (_, int i) => _SlideView(slide: slides[i]),
                      ),
                    ),
                    _buildDots(slides.length),
                    const SizedBox(height: 16),
                    _buildCta(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            l10n.appTitle,
            style: TextAppStyle.pressStart2p(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 14,
            ).copyWith(letterSpacing: 2),
          ),
          TextButton(
            onPressed: _finish,
            // Dùng ui() (Noto Sans) thay vì Rajdhani: Rajdhani cover Latin
            // Extended cơ bản nhưng một số dấu VN (ỏ, ể, ữ, ắ...) nằm ở
            // Latin Extended Additional có thể bị lệch/mỏng. Noto Sans được
            // thiết kế phủ đầy đủ tiếng Việt nên "Bỏ qua" hiển thị sạch.
            child: Text(
              l10n.onboardingSkip,
              style: TextAppStyle.ui(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 14,
                fontWeight: FontWeight.w500,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDots(int count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(count, (int i) {
        final bool active = i == _page;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 22 : 8,
          height: 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: active
                ? const Color(0xFF4fc3f7)
                : Colors.white.withValues(alpha: 0.25),
          ),
        );
      }),
    );
  }

  Widget _buildCta() {
    final bool isLast = _page >= 2;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: GestureDetector(
        onTap: _next,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: <Color>[Color(0xFF4fc3f7), Color(0xFF2196F3)],
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: const Color(0xFF4fc3f7).withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            isLast ? l10n.onboardingStart : l10n.onboardingNext,
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
    );
  }
}

class _Slide {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final Widget art;

  const _Slide({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
    required this.art,
  });
}

class _SlideView extends StatelessWidget {
  final _Slide slide;
  const _SlideView({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 16),
      child: Column(
        children: <Widget>[
          const Spacer(),
          SizedBox(
            width: 200,
            height: 200,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[
                    slide.color.withValues(alpha: 0.2),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Center(child: slide.art),
            ),
          ),
          const SizedBox(height: 32),
          // Dùng Rajdhani cho tiêu đề slide vì Press Start 2P không có
          // glyph dấu tiếng Việt (ả, ế, ị, ứ, ơ...) → text VI bị mixed font.
          // Rajdhani hỗ trợ Latin Extended đầy đủ nên tiếng Việt hiển thị đúng
          // mà vẫn giữ vibe game/condensed.
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: TextAppStyle.rajdhani(
              color: slide.color,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              shadows: <Shadow>[
                Shadow(color: slide.color.withValues(alpha: 0.5), blurRadius: 12),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            slide.body,
            textAlign: TextAlign.center,
            style: TextAppStyle.ui(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 15,
              height: 1.5,
            ),
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }
}

/// Tiny 3x3 demo board drawn with CustomPaint.
class _BoardArt extends StatelessWidget {
  final int rows;
  final List<(int, int, int)> pattern; // (row, col, player 1|2)
  const _BoardArt({required this.rows, required this.pattern});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(140, 140),
      painter: _BoardArtPainter(rows: rows, pattern: pattern),
    );
  }
}

class _BoardArtPainter extends CustomPainter {
  final int rows;
  final List<(int, int, int)> pattern;
  _BoardArtPainter({required this.rows, required this.pattern});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..strokeWidth = 1.5;
    final double cell = size.width / rows;
    for (int i = 0; i <= rows; i++) {
      canvas.drawLine(Offset(i * cell, 0), Offset(i * cell, size.height), grid);
      canvas.drawLine(Offset(0, i * cell), Offset(size.width, i * cell), grid);
    }
    for (final (int r, int c, int p) in pattern) {
      final Offset center = Offset(c * cell + cell / 2, r * cell + cell / 2);
      final Paint pieceFill = Paint()
        ..color = p == 1 ? const Color(0xFF4fc3f7) : const Color(0xFFf48fb1)
        ..style = PaintingStyle.fill;
      final Paint pieceGlow = Paint()
        ..color = pieceFill.color.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawCircle(center, cell * 0.35, pieceGlow);
      canvas.drawCircle(center, cell * 0.3, pieceFill);
    }
  }

  @override
  bool shouldRepaint(covariant _BoardArtPainter oldDelegate) => false;
}

/// Two cards side-by-side illustrating 2P vs vs AI.
class _TwoModesArt extends StatelessWidget {
  const _TwoModesArt();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        _modeTile(
          icon: Icons.people_alt_rounded,
          label: '2P',
          color: const Color(0xFFf48fb1),
        ),
        const SizedBox(width: 16),
        _modeTile(
          icon: Icons.smart_toy_rounded,
          label: 'AI',
          color: const Color(0xFF4fc3f7),
        ),
      ],
    );
  }

  Widget _modeTile({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
        boxShadow: <BoxShadow>[
          BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 12),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextAppStyle.pressStart2p(
              color: color,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

/// Three rows: 3x3 → 3-in-a-row, 9x9 → 5-in-a-row, 15x15 → 5-in-a-row.
class _WinRulesArt extends StatelessWidget {
  const _WinRulesArt();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        _rule('3×3', '3', const Color(0xFF80FFDB)),
        const SizedBox(height: 6),
        _rule('9×9', '5', const Color(0xFFFFD23F)),
        const SizedBox(height: 6),
        _rule('15×15', '5', const Color(0xFFB388FF)),
      ],
    );
  }

  Widget _rule(String size, String w, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        SizedBox(
          width: 50,
          child: Text(
            size,
            style: TextAppStyle.ui(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 12,
            ),
          ),
        ),
        Icon(Icons.arrow_forward_rounded, color: color, size: 16),
        const SizedBox(width: 6),
        Text(
          '$w',
          style: TextAppStyle.pressStart2p(
            color: color,
            fontSize: 14,
            shadows: <Shadow>[
              Shadow(color: color.withValues(alpha: 0.5), blurRadius: 8),
            ],
          ),
        ),
        const SizedBox(width: 4),
        Text(
          'in a row',
          style: TextAppStyle.ui(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
