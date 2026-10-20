import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/app_scope.dart';
import '../../core/theme.dart';
import '../../game/models/card_icon.dart';
import '../../l10n/strings.dart';
import '../widgets/app_background.dart';
import '../widgets/neon_button.dart';
import 'menu_screen.dart';

/// Hướng dẫn 4 bước.
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
        illustration: const _CardPairIllustration(
          leftIconId: null,
          rightIconId: 'cat',
        ),
      ),
      _TutorialPageData(
        title: s.tutorial2Title,
        body: s.tutorial2Body,
        illustration: const _CardPairIllustration(
          leftIconId: 'cat',
          rightIconId: 'cat',
          matched: true,
        ),
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          SizedBox(height: 180, child: page.illustration),
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

/// Hai lá bài minh hoạ. [leftIconId] null nghĩa là lá đang úp.
class _CardPairIllustration extends StatelessWidget {
  final String? leftIconId;
  final String? rightIconId;
  final bool matched;

  const _CardPairIllustration({
    required this.leftIconId,
    required this.rightIconId,
    this.matched = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        _MiniCard(iconId: leftIconId, highlighted: matched),
        const SizedBox(width: 18),
        if (matched)
          const Icon(Icons.link_rounded, color: AppTheme.neonCyan, size: 30)
        else
          Icon(
            Icons.touch_app_rounded,
            size: 30,
            color: AppTheme.alpha(Theme.of(context).colorScheme.onSurface, 0.5),
          ),
        const SizedBox(width: 18),
        _MiniCard(iconId: rightIconId, highlighted: matched),
      ],
    );
  }
}

class _MiniCard extends StatelessWidget {
  final String? iconId;
  final bool highlighted;

  const _MiniCard({required this.iconId, this.highlighted = false});

  @override
  Widget build(BuildContext context) {
    const width = 96.0;
    const height = width * 1.32;
    final id = iconId;

    if (id == null) {
      return SizedBox(
        width: width,
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SvgPicture.asset(package: 'main_app_package', CardIcons.cardBack, fit: BoxFit.cover),
        ),
      );
    }

    final icon = CardIcons.all.firstWhere(
      (candidate) => candidate.id == id,
      orElse: () => CardIcons.all.first,
    );

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlighted
              ? AppTheme.neonCyan
              : AppTheme.alpha(AppTheme.violetBright, 0.25),
          width: highlighted ? 2.5 : 1.2,
        ),
        boxShadow: highlighted
            ? <BoxShadow>[
                BoxShadow(
                  color: AppTheme.alpha(AppTheme.neonCyan, 0.5),
                  blurRadius: 16,
                  spreadRadius: -2,
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: SvgPicture.asset(package: 'main_app_package', icon.asset, fit: BoxFit.contain),
      ),
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
