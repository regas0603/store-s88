import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/theme.dart';
import '../../l10n/strings.dart';
import '../widgets/app_background.dart';
import '../widgets/mole_hole_view.dart';
import '../widgets/neon_button.dart';
import 'menu_screen.dart';

/// Hướng dẫn từng bước.
///
/// Hiện tự động ở lần mở app đầu tiên ([isFirstRun] = true) và mở lại được từ
/// sảnh hoặc Cài đặt. Cho phép bỏ qua ở mọi bước — ép người chơi xem hết là
/// cách nhanh nhất để họ thoát app.
class TutorialScreen extends StatefulWidget {
  final bool isFirstRun;

  const TutorialScreen({this.isFirstRun = false, super.key});

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final PageController _pageController = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final scope = AppScope.of(context);
    scope.sound.tapFeedback();
    await scope.settings.setTutorialSeen(true);
    if (!mounted) return;

    if (widget.isFirstRun) {
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const MenuScreen()),
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _next(int lastIndex) async {
    if (_page >= lastIndex) {
      await _finish();
      return;
    }
    AppScope.of(context).sound.tapFeedback();
    await _pageController.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);

    final pages = <_TutorialPageData>[
      _TutorialPageData(
        title: s.tutorial1Title,
        body: s.tutorial1Body,
        illustration: const _HolesIllustration(dazed: false),
      ),
      _TutorialPageData(
        title: s.tutorial2Title,
        body: s.tutorial2Body,
        illustration: const _HolesIllustration(dazed: true),
      ),
      _TutorialPageData(
        title: s.tutorialTrapTitle,
        body: s.tutorialTrapBody,
        illustration: const _TrapIllustration(),
      ),
      _TutorialPageData(
        title: s.tutorial3Title,
        body: s.tutorial3Body,
        illustration: const _BadgeIllustration(
          icon: Icons.bolt_rounded,
          accent: AppTheme.sunGold,
        ),
      ),
      _TutorialPageData(
        title: s.tutorial4Title,
        body: s.tutorial4Body,
        illustration: const _ModesIllustration(),
      ),
    ];

    final lastIndex = pages.length - 1;
    final isLast = _page == lastIndex;

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: TextButton(
                    onPressed: _finish,
                    child: Text(s.skip),
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: pages.length,
                  onPageChanged: (index) => setState(() => _page = index),
                  itemBuilder: (context, index) {
                    final page = pages[index];
                    // Máy nhỏ hoặc chữ to: thu nhỏ hình và cho cuộn thay vì
                    // tràn. Máy thường vẫn căn giữa như cũ nhờ minHeight.
                    return LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              SizedBox(
                                height: 180,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: page.illustration,
                                ),
                              ),
                              const SizedBox(height: 36),
                              Text(
                                page.title,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                page.body,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  height: 1.5,
                                  color: AppTheme.alpha(
                                    theme.colorScheme.onSurface,
                                    0.75,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  for (var i = 0; i < pages.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 240),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _page ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _page
                            ? theme.colorScheme.primary
                            : AppTheme.alpha(theme.colorScheme.onSurface, 0.25),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
                child: NeonPrimaryButton(
                  label: isLast ? s.startPlaying : s.next,
                  icon: isLast
                      ? Icons.play_arrow_rounded
                      : Icons.arrow_forward_rounded,
                  onPressed: () => _next(lastIndex),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TutorialPageData {
  final String title;
  final String body;
  final Widget illustration;

  const _TutorialPageData({
    required this.title,
    required this.body,
    required this.illustration,
  });
}

/// Hai hang minh hoạ: một hang trống và một con đang trồi lên. [dazed] = con
/// đó vừa bị đập trúng.
class _HolesIllustration extends StatelessWidget {
  final bool dazed;

  const _HolesIllustration({required this.dazed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const size = 124.0;

    Widget hole({required bool raised}) => DecoratedBox(
          decoration: BoxDecoration(
            color: AppTheme.panelColor(theme.colorScheme, theme.brightness),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: raised && dazed
                  ? AppTheme.neonCyan
                  : AppTheme.panelBorder(theme.colorScheme, theme.brightness),
              width: raised && dazed ? 2.5 : 1,
            ),
          ),
          child: MoleHoleView(
            width: size,
            height: size,
            raised: raised,
            dazed: raised && dazed,
            hitAccent: AppTheme.neonCyan,
          ),
        );

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        hole(raised: false),
        const SizedBox(width: 14),
        Icon(
          dazed ? Icons.gavel_rounded : Icons.touch_app_rounded,
          size: 30,
          color: dazed
              ? AppTheme.sunGold
              : AppTheme.alpha(theme.colorScheme.onSurface, 0.5),
        ),
        const SizedBox(width: 14),
        hole(raised: true),
      ],
    );
  }
}

/// Một quả bom vừa bị đập (hiện "-1") cạnh một con chuột chũi — thứ được đập.
class _TrapIllustration extends StatelessWidget {
  const _TrapIllustration();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const size = 124.0;

    Widget hole({required bool isTrap, required Color border}) => DecoratedBox(
          decoration: BoxDecoration(
            color: AppTheme.panelColor(theme.colorScheme, theme.brightness),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: border, width: 2.5),
          ),
          child: MoleHoleView(
            width: size,
            height: size,
            raised: true,
            dazed: isTrap,
            isTrap: isTrap,
          ),
        );

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            hole(isTrap: true, border: AppTheme.trapRed),
            const SizedBox(height: 6),
            const Icon(Icons.close_rounded, color: AppTheme.trapRed),
          ],
        ),
        const SizedBox(width: 24),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            hole(isTrap: false, border: AppTheme.greenSoft),
            const SizedBox(height: 6),
            const Icon(Icons.check_rounded, color: AppTheme.greenSoft),
          ],
        ),
      ],
    );
  }
}

class _BadgeIllustration extends StatelessWidget {
  final IconData icon;
  final Color accent;

  const _BadgeIllustration({required this.icon, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 150,
        height: 150,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppTheme.alpha(accent, 0.16),
          border: Border.all(color: AppTheme.alpha(accent, 0.6), width: 2),
        ),
        child: Icon(icon, size: 68, color: accent),
      ),
    );
  }
}

class _ModesIllustration extends StatelessWidget {
  const _ModesIllustration();

  @override
  Widget build(BuildContext context) {
    const items = <(IconData, Color)>[
      (Icons.person_rounded, AppTheme.neonCyan),
      (Icons.smart_toy_rounded, AppTheme.sunGold),
      (Icons.groups_rounded, AppTheme.neonPink),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (final (icon, color) in items)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Container(
              width: 86,
              height: 86,
              decoration: BoxDecoration(
                color: AppTheme.alpha(color, 0.16),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: AppTheme.alpha(color, 0.55)),
              ),
              child: Icon(icon, size: 38, color: color),
            ),
          ),
      ],
    );
  }
}
