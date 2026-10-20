import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../core/game_history.dart';
import '../core/game_snapshot.dart';
import '../core/l10n.dart';
import 'achievements_screen.dart';
import '../core/text_app_style.dart';
import '../core/app_settings.dart';
import '../game/caro_game.dart';
import 'game_screen.dart';
import 'settings_screen.dart';
import 'history_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _bgCtrl;
  late Future<String> _versionTextFuture;

  @override
  void initState() {
    super.initState();
    _bgCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
    _versionTextFuture = _loadVersionText();

    AppSettings().addListener(_onSettingsChanged);
  }

  Future<String> _loadVersionText() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      final String buildSuffix = info.buildNumber.isEmpty
          ? ''
          : '+${info.buildNumber}';
      return 'v${info.version}$buildSuffix';
    } catch (_) {
      return 'v—';
    }
  }

  void _onSettingsChanged() {
    l10n.setLanguage(AppSettings().language);
    setState(() {});
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    AppSettings().removeListener(_onSettingsChanged);
    super.dispose();
  }

  /// US-003: kiểm tra snapshot đang dở trước khi start game mới.
  ///
  /// Logic ưu tiên:
  /// - Có snapshot + mode khớp (cùng vsAI) → hỏi user Tiếp tục / Bỏ ván.
  /// - Có snapshot nhưng khác mode → hỏi user có muốn hủy ván cũ không trước
  ///   khi vào mode mới (tránh mất progress không chủ ý).
  /// - Không có snapshot → vào thẳng.
  Future<void> _startGame(bool vsAI) async {
    final GameSnapshot? snap = await GameSnapshotStore().load();
    if (!mounted) return;

    if (snap != null) {
      final bool sameMode = (snap.mode == GameMode.vsAI) == vsAI;
      if (sameMode) {
        final _ResumeChoice? choice = await _showResumeDialog(snap);
        if (!mounted) return;
        if (choice == null)
          return; // user dismiss (barrier/back) → không làm gì
        if (choice == _ResumeChoice.resume) {
          _openGameWithSnapshot(snap);
          return;
        }
        if (choice == _ResumeChoice.discard) {
          await GameSnapshotStore().clear();
          if (!mounted) return;
        }
        // rơi xuống case start fresh
      } else {
        // Mode khác — cảnh báo user sẽ mất ván cũ nếu tiếp tục
        final bool ok = await _showDifferentModeWarning(snap);
        if (!mounted) return;
        if (!ok) return;
        await GameSnapshotStore().clear();
        if (!mounted) return;
      }
    }

    _openNewGame(vsAI);
  }

  void _openNewGame(bool vsAI) {
    final game = CaroGame(vsAI: vsAI);
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => GameScreen(game: game, vsAI: vsAI),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  void _openGameWithSnapshot(GameSnapshot snap) {
    final bool vsAI = snap.mode == GameMode.vsAI;
    final CaroGame game = CaroGame(
      vsAI: vsAI,
      resumeBoardSide: snap.boardSide,
      resumeWinLength: snap.winLength,
    );
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) =>
            _ResumedGameScreenWrapper(game: game, vsAI: vsAI, snapshot: snap),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  Future<_ResumeChoice?> _showResumeDialog(GameSnapshot snap) {
    return showDialog<_ResumeChoice>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext ctx) {
        final int moveCount = snap.moves.length;
        return AlertDialog(
          backgroundColor: const Color(0xFF1a1a3e),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            l10n.resumeTitle,
            style: TextAppStyle.ui(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.resumeBody,
                style: TextAppStyle.ui(fontSize: 14, color: Colors.white70),
              ),
              const SizedBox(height: 12),
              _ResumePreviewRow(
                label: l10n.resumeMode,
                value: snap.mode == GameMode.vsAI ? l10n.vsAI : l10n.twoPlayers,
              ),
              const SizedBox(height: 4),
              _ResumePreviewRow(
                label: l10n.resumeBoard,
                value: '${snap.boardSide}×${snap.boardSide}',
              ),
              const SizedBox(height: 4),
              _ResumePreviewRow(label: l10n.resumeMoves, value: '$moveCount'),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, _ResumeChoice.discard),
              child: Text(
                l10n.resumeDiscard,
                style: const TextStyle(color: Color(0xFFFF8A80)),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, _ResumeChoice.resume),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4fc3f7),
                foregroundColor: Colors.black87,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                l10n.resumeContinue,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _showDifferentModeWarning(GameSnapshot snap) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a3e),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          l10n.resumeOtherModeTitle,
          style: TextAppStyle.ui(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        content: Text(
          l10n.resumeOtherModeBody,
          style: TextAppStyle.ui(fontSize: 14, color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              l10n.cancel,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF8A80),
              foregroundColor: Colors.black87,
            ),
            child: Text(
              l10n.resumeDiscardAndStart,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070714),
      body: AnimatedBuilder(
        animation: _bgCtrl,
        builder: (_, child) => Stack(
          children: [
            // Animated gradient bg
            Positioned.fill(
              child: CustomPaint(painter: _HomeBgPainter(_bgCtrl.value)),
            ),
            child!,
          ],
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top bar: settings + history
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _IconBtn(
                      icon: Icons.history_rounded,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const HistoryScreen(),
                        ),
                      ),
                    ),
                    _IconBtn(
                      icon: Icons.settings_rounded,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Logo
              _AnimatedLogo(),
              const SizedBox(height: 24),
              // Title
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [
                    Color(0xFF4fc3f7),
                    Color(0xFF81d4fa),
                    Color(0xFFb3e5fc),
                  ],
                ).createShader(bounds),
                child: Text(
                  l10n.appTitle,
                  style:
                      TextAppStyle.sfProWithCjkFallback(
                        fontSize: 28,
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                        height: 1.05,
                      ).copyWith(
                        shadows: const [
                          Shadow(color: Color(0xFF4fc3f7), blurRadius: 20),
                        ],
                      ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.tagline,
                style: TextAppStyle.rajdhani(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 12,
                  letterSpacing: 6,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              // Menu buttons
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    _MenuButton(
                      icon: '👥',
                      label: l10n.twoPlayers,
                      subtitle: l10n.twoPlayersSub,
                      color: const Color(0xFF4fc3f7),
                      onTap: () => _startGame(false),
                    ),
                    const SizedBox(height: 14),
                    _MenuButton(
                      icon: '🤖',
                      label: l10n.vsAI,
                      subtitle: l10n.vsAISub,
                      color: const Color(0xFFf48fb1),
                      onTap: () => _startGame(true),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _SmallBtn(
                            icon: Icons.emoji_events_rounded,
                            label: l10n.achievementsTitle,
                            color: const Color(0xFFFFD700),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AchievementsScreen(),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _SmallBtn(
                            icon: Icons.history_rounded,
                            label: l10n.history,
                            color: const Color(0xFFB388FF),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const HistoryScreen(),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _SmallBtn(
                            icon: Icons.settings_rounded,
                            label: l10n.settings,
                            color: const Color(0xFF80FFDB),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const SettingsScreen(),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              FutureBuilder<String>(
                future: _versionTextFuture,
                builder: (BuildContext context, AsyncSnapshot<String> snap) {
                  final String label = snap.data ?? 'v…';
                  return Text(
                    label,
                    style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 10,
                      letterSpacing: 2,
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ResumeChoice { resume, discard }

/// Wrapper chèn giữa HomeScreen → GameScreen: sau khi GameWidget load xong
/// (board component đã mounted), apply snapshot. Tránh race condition khi
/// applySnapshot chạy trước khi BoardComponent sẵn sàng.
class _ResumedGameScreenWrapper extends StatefulWidget {
  final CaroGame game;
  final bool vsAI;
  final GameSnapshot snapshot;
  const _ResumedGameScreenWrapper({
    required this.game,
    required this.vsAI,
    required this.snapshot,
  });

  @override
  State<_ResumedGameScreenWrapper> createState() =>
      _ResumedGameScreenWrapperState();
}

class _ResumedGameScreenWrapperState extends State<_ResumedGameScreenWrapper> {
  bool _applied = false;

  @override
  void initState() {
    super.initState();
    // Đợi một post-frame để GameWidget mount CaroGame.onLoad, sau đó apply.
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyWhenReady());
  }

  Future<void> _applyWhenReady() async {
    // Poll đến khi BoardComponent đã được add (CaroGame.onLoad chạy xong).
    for (int i = 0; i < 40 && !_applied; i++) {
      try {
        widget.game.applySnapshot(widget.snapshot);
        _applied = true;
        break;
      } catch (_) {
        // Chưa sẵn sàng — chờ frame kế
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GameScreen(game: widget.game, vsAI: widget.vsAI);
  }
}

/// Row nhỏ trong Resume dialog: label + value.
class _ResumePreviewRow extends StatelessWidget {
  final String label;
  final String value;
  const _ResumePreviewRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextAppStyle.ui(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextAppStyle.ui(
            fontSize: 13,
            color: const Color(0xFF4fc3f7),
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _HomeBgPainter extends CustomPainter {
  final double t;
  _HomeBgPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    // Animated radial gradient orbs
    final p1 = Paint()
      ..shader =
          RadialGradient(
            colors: [
              const Color(0xFF1565c0).withValues(alpha: 0.3),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(
                size.width * 0.2 + t * size.width * 0.1,
                size.height * 0.3,
              ),
              radius: size.width * 0.5,
            ),
          );
    canvas.drawCircle(
      Offset(size.width * 0.2 + t * size.width * 0.1, size.height * 0.3),
      size.width * 0.5,
      p1,
    );

    final p2 = Paint()
      ..shader =
          RadialGradient(
            colors: [
              const Color(0xFF880e4f).withValues(alpha: 0.2),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(
                size.width * 0.8 - t * size.width * 0.1,
                size.height * 0.7,
              ),
              radius: size.width * 0.4,
            ),
          );
    canvas.drawCircle(
      Offset(size.width * 0.8 - t * size.width * 0.1, size.height * 0.7),
      size.width * 0.4,
      p2,
    );
  }

  @override
  bool shouldRepaint(_HomeBgPainter old) => old.t != t;
}

class _AnimatedLogo extends StatefulWidget {
  @override
  State<_AnimatedLogo> createState() => _AnimatedLogoState();
}

class _AnimatedLogoState extends State<_AnimatedLogo>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final g = _ctrl.value;
        return Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                Color.lerp(
                  const Color(0xFF0d47a1),
                  const Color(0xFF1976d2),
                  g,
                )!,
                const Color(0xFF070714),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4fc3f7).withValues(alpha: 0.2 + g * 0.3),
                blurRadius: 25 + g * 15,
                spreadRadius: 3 + g * 5,
              ),
            ],
          ),
          child: const Center(
            child: Text('✕○', style: TextStyle(fontSize: 32)),
          ),
        );
      },
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.15),
            width: 1,
          ),
          color: Colors.white.withValues(alpha: 0.05),
        ),
        child: Icon(icon, color: Colors.white.withValues(alpha: 0.6), size: 22),
      ),
    );
  }
}

class _MenuButton extends StatefulWidget {
  final String icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _MenuButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  State<_MenuButton> createState() => _MenuButtonState();
}

class _MenuButtonState extends State<_MenuButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 80),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.color.withValues(alpha: 0.4),
              width: 1.5,
            ),
            gradient: LinearGradient(
              colors: [
                widget.color.withValues(alpha: 0.12),
                widget.color.withValues(alpha: 0.04),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Row(
            children: [
              // Text(widget.icon, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.label,
                    style: TextAppStyle.rajdhani(
                      color: widget.color,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      letterSpacing: 2,
                    ),
                  ),
                  Text(
                    widget.subtitle,
                    style: TextAppStyle.ui(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Icon(
                Icons.arrow_forward_ios,
                color: widget.color.withValues(alpha: 0.6),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _SmallBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
          color: color.withValues(alpha: 0.07),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextAppStyle.rajdhani(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
