import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/theme.dart';
import '../../game/models/card_icon.dart';
import '../../l10n/strings.dart';
import '../widgets/app_background.dart';
import 'menu_screen.dart';
import 'tutorial_screen.dart';

/// Màn hình mở đầu.
///
/// Ngoài việc tạo nhận diện, splash còn che khoảng thời gian giải mã lần đầu
/// các PNG nhân vật. Warm cache ngay tại đây thì con đầu tiên trồi lên ở ván
/// đầu không bị khựng.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _minimumDisplay = Duration(milliseconds: 1700);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  Timer? _navigationTimer;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _navigationTimer = Timer(_minimumDisplay, _goNext);
    WidgetsBinding.instance.addPostFrameCallback((_) => _warmUpSvgCache());
  }

  /// Nạp trước icon của bộ nhân vật đang chọn (chuột chũi cổ điển thì vẽ tay,
  /// không cần nạp gì).
  void _warmUpSvgCache() {
    if (!mounted) return;
    final category = AppScope.of(context).settings.value.cardCategory;
    if (category == null) return;
    for (final icon in CardIcons.byCategory(category)) {
      precacheImage(AssetImage(icon.asset, package: 'main_app_package'), context).ignore();
    }
  }

  void _goNext() {
    if (_navigated || !mounted) return;
    _navigated = true;

    final seenTutorial = AppScope.of(context).settings.value.tutorialSeen;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 420),
        pageBuilder: (_, _, _) => seenTutorial
            ? const MenuScreen()
            : const TutorialScreen(isFirstRun: true),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);

    final fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    final scale = Tween<double>(begin: 0.82, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    return Scaffold(
      body: AppBackground(
        child: Center(
          child: FadeTransition(
            opacity: fade,
            child: ScaleTransition(
              scale: scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    width: 132,
                    height: 132,
                    child: Image.asset(package: 'main_app_package', 'assets/branding/app_icon.png'),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    s.appName,
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    s.tagline,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppTheme.alpha(theme.colorScheme.onSurface, 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
