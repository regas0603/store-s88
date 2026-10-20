import 'dart:math';
import 'package:flutter/material.dart';
import '../core/achievements.dart';
import '../core/app_settings.dart';
import '../core/text_app_style.dart';
import '../core/l10n.dart';
import '../core/game_history.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _waveCtrl;
  late AnimationController _titleCtrl;
  late AnimationController _glowCtrl;
  late Animation<double> _titleFade;
  late Animation<double> _titleSlide;
  late Animation<double> _glow;

  bool _ready = false;

  @override
  void initState() {
    super.initState();

    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _titleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _titleFade = CurvedAnimation(parent: _titleCtrl, curve: Curves.easeOut);
    _titleSlide = Tween(begin: 60.0, end: 0.0).animate(
      CurvedAnimation(parent: _titleCtrl, curve: Curves.easeOutCubic),
    );
    _glow = CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut);

    _init();
  }

  Future<void> _init() async {
    await Future.wait([
      AppSettings().load(),
      GameHistory().load(),
      AchievementStore().load(), // US-004
    ]);

    l10n.setLanguage(AppSettings().language);

    // Start title animation after short delay
    await Future.delayed(const Duration(milliseconds: 400));
    _titleCtrl.forward();

    // Navigate after 3.2s
    await Future.delayed(const Duration(milliseconds: 2800));
    if (mounted) {
      setState(() => _ready = true);
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) {
        final bool seen = AppSettings().hasSeenOnboarding;
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) =>
                seen ? const HomeScreen() : const OnboardingScreen(),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _waveCtrl.dispose();
    _titleCtrl.dispose();
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070714),
      body: Stack(
        children: [
          // Starfield background
          _StarfieldBg(),
          // Wave layers at bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: _waveCtrl,
              builder: (_, __) => _WavePainter(progress: _waveCtrl.value),
            ),
          ),
          // Center content
          Center(
            child: AnimatedBuilder(
              animation: Listenable.merge([_titleCtrl, _glowCtrl]),
              builder: (_, __) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo icon with glow
                    Transform.translate(
                      offset: Offset(0, _titleSlide.value * 0.5),
                      child: Opacity(
                        opacity: _titleFade.value,
                        child: _LogoIcon(glowAnim: _glow),
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Main Title with wave letter animation
                    _WaveTitle(
                      text: 'CARO',
                      progress: _titleCtrl.value,
                      glow: _glow.value,
                    ),
                    const SizedBox(height: 10),
                    // Subtitle
                    Transform.translate(
                      offset: Offset(0, _titleSlide.value),
                      child: Opacity(
                        opacity: (_titleFade.value - 0.3).clamp(0.0, 1.0),
                        child: Text(
                          l10n.tagline,
                          style: TextAppStyle.rajdhani(
                            color:
                                const Color(0xFF4fc3f7).withValues(alpha: 0.5),
                            fontSize: 14,
                            letterSpacing: 8,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 60),
                    // Loading dots
                    Opacity(
                      opacity: (_titleFade.value - 0.5).clamp(0.0, 1.0),
                      child: _LoadingDots(glow: _glow.value),
                    ),
                  ],
                );
              },
            ),
          ),
          // Fade out overlay
          if (_ready)
            AnimatedOpacity(
              opacity: _ready ? 1 : 0,
              duration: const Duration(milliseconds: 400),
              child: Container(color: const Color(0xFF070714)),
            ),
        ],
      ),
    );
  }
}

// ─── Logo Icon ────────────────────────────────────────────────────────────────

class _LogoIcon extends StatelessWidget {
  final Animation<double> glowAnim;
  const _LogoIcon({required this.glowAnim});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: glowAnim,
      builder: (_, __) {
        final glow = glowAnim.value;
        return Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                Color.lerp(
                    const Color(0xFF1565c0), const Color(0xFF4fc3f7), glow)!,
                const Color(0xFF0d1b4d),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color:
                    const Color(0xFF4fc3f7).withValues(alpha: 0.3 + glow * 0.3),
                blurRadius: 30 + glow * 20,
                spreadRadius: 5 + glow * 5,
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // X
              Positioned(
                left: 18,
                top: 18,
                child: CustomPaint(
                  size: const Size(28, 28),
                  painter: _XPainter(
                    color: const Color(0xFF4fc3f7),
                    glow: glow,
                  ),
                ),
              ),
              // O
              Positioned(
                right: 14,
                bottom: 14,
                child: CustomPaint(
                  size: const Size(30, 30),
                  painter: _OPainter(
                    color: const Color(0xFFf48fb1),
                    glow: glow,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _XPainter extends CustomPainter {
  final Color color;
  final double glow;
  _XPainter({required this.color, required this.glow});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.3 + glow * 0.2)
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
      ..style = PaintingStyle.stroke;
    for (final p in [glowPaint, paint]) {
      canvas.drawLine(Offset.zero, Offset(size.width, size.height), p);
      canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), p);
    }
  }

  @override
  bool shouldRepaint(_XPainter old) => old.glow != glow;
}

class _OPainter extends CustomPainter {
  final Color color;
  final double glow;
  _OPainter({required this.color, required this.glow});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 2;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.3 + glow * 0.2)
      ..strokeWidth = 8
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, r, glowPaint);
    canvas.drawCircle(center, r, paint);
  }

  @override
  bool shouldRepaint(_OPainter old) => old.glow != glow;
}

// ─── Wave Title ───────────────────────────────────────────────────────────────

class _WaveTitle extends StatelessWidget {
  final String text;
  final double progress;
  final double glow;

  const _WaveTitle(
      {required this.text, required this.progress, required this.glow});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: text.split('').asMap().entries.map((e) {
        final i = e.key;
        final char = e.value;
        final delay = i * 0.08;
        final charProg = ((progress - delay) / (1 - delay)).clamp(0.0, 1.0);
        final waveOffset = sin(progress * 2 * pi - i * 0.5) * 4;

        return Transform.translate(
          offset: Offset(0, -waveOffset),
          child: Opacity(
            opacity: charProg,
            child: Transform.translate(
              offset: Offset(0, (1 - charProg) * 30),
              child: ShaderMask(
                shaderCallback: (bounds) => LinearGradient(
                  colors: [
                    Color.lerp(
                        const Color(0xFF4fc3f7), Colors.white, glow * 0.3)!,
                    Color.lerp(const Color(0xFF81d4fa), const Color(0xFFb3e5fc),
                        glow * 0.2)!,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ).createShader(bounds),
                child: Text(
                  char == ' ' ? ' ' : char,
                  style: TextAppStyle.pressStart2p(
                    fontSize: char == ' ' ? 10 : 36,
                    color: Colors.white,
                    shadows: [
                      Shadow(
                        color: const Color(0xFF4fc3f7)
                            .withValues(alpha: 0.5 + glow * 0.3),
                        blurRadius: 15 + glow * 10,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Loading Dots ─────────────────────────────────────────────────────────────

class _LoadingDots extends StatelessWidget {
  final double glow;
  const _LoadingDots({required this.glow});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final phase = (glow + i * 0.33) % 1.0;
        final size = 4.0 + phase * 4;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF4fc3f7).withValues(alpha: 0.3 + phase * 0.7),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4fc3f7).withValues(alpha: phase * 0.5),
                blurRadius: 8,
              ),
            ],
          ),
        );
      }),
    );
  }
}

// ─── Wave Painter ─────────────────────────────────────────────────────────────

class _WavePainter extends StatelessWidget {
  final double progress;
  const _WavePainter({required this.progress});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: CustomPaint(
        painter: _WaveCustomPainter(progress: progress),
        size: Size(MediaQuery.of(context).size.width, 200),
      ),
    );
  }
}

class _WaveCustomPainter extends CustomPainter {
  final double progress;
  _WaveCustomPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    _drawWave(canvas, size, progress, const Color(0xFF4fc3f7), 0.06, 30, 60);
    _drawWave(
        canvas, size, progress + 0.3, const Color(0xFF1565c0), 0.04, 20, 40);
    _drawWave(
        canvas, size, progress + 0.6, const Color(0xFFf48fb1), 0.03, 15, 80);
  }

  void _drawWave(Canvas canvas, Size size, double phase, Color color,
      double opacity, double amplitude, double yOffset) {
    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(0, size.height);

    for (double x = 0; x <= size.width; x++) {
      final y = yOffset +
          sin((x / size.width * 2 * pi) + phase * 2 * pi) * amplitude +
          sin((x / size.width * 4 * pi) + phase * 2 * pi * 1.5) *
              amplitude *
              0.5;
      path.lineTo(x, size.height - y);
    }

    path.lineTo(size.width, size.height);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WaveCustomPainter old) => old.progress != progress;
}

// ─── Starfield ────────────────────────────────────────────────────────────────

class _StarfieldBg extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final rng = Random(42);
    return CustomPaint(
      size: size,
      painter: _StarPainter(
        stars: List.generate(
          60,
          (_) => Offset(
              rng.nextDouble() * size.width, rng.nextDouble() * size.height),
        ),
        sizes: List.generate(60, (_) => rng.nextDouble() * 2 + 0.5),
      ),
    );
  }
}

class _StarPainter extends CustomPainter {
  final List<Offset> stars;
  final List<double> sizes;
  _StarPainter({required this.stars, required this.sizes});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.4);
    for (int i = 0; i < stars.length; i++) {
      canvas.drawCircle(stars[i], sizes[i], paint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
