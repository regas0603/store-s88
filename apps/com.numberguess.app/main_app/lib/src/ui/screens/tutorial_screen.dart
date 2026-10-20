import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/theme.dart';
import '../../l10n/strings.dart';
import '../widgets/app_background.dart';
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
        illustration: const _SecretNumberIllustration(),
      ),
      _TutorialPageData(
        title: s.tutorial2Title,
        body: s.tutorial2Body,
        illustration: const _HintIllustration(),
      ),
      _TutorialPageData(
        title: s.tutorial3Title,
        body: s.tutorial3Body,
        illustration: const _HalvingIllustration(),
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

/// Ba ô chữ số bị che — "một con số đang nằm đâu đó trong khoảng này".
class _SecretNumberIllustration extends StatelessWidget {
  const _SecretNumberIllustration();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Container(
              width: 74,
              height: 96,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.alpha(AppTheme.greenDeep, 0.5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.alpha(AppTheme.mint, 0.4)),
              ),
              child: Text(
                '?',
                style: theme.textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: AppTheme.mint,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Một lần đoán sai kèm mũi tên CAO HƠN / THẤP HƠN.
class _HintIllustration extends StatelessWidget {
  const _HintIllustration();

  @override
  Widget build(BuildContext context) {
    Widget arrow(IconData icon, Color color, String label) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppTheme.alpha(color, 0.16),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.alpha(color, 0.6), width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 44, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: color,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        );

    final s = AppStrings.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        arrow(Icons.arrow_upward_rounded, AppTheme.sunGold, s.hintHigher),
        const SizedBox(width: 16),
        arrow(Icons.arrow_downward_rounded, AppTheme.neonCyan, s.hintLower),
      ],
    );
  }
}

/// Thanh khoảng số bị cắt đôi dần — minh hoạ chiến thuật chia đôi.
class _HalvingIllustration extends StatelessWidget {
  const _HalvingIllustration();

  @override
  Widget build(BuildContext context) {
    const widths = <double>[220, 110, 55, 28];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var i = 0; i < widths.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Container(
              width: widths[i],
              height: 26,
              decoration: BoxDecoration(
                color: AppTheme.alpha(
                  AppTheme.greenSoft,
                  0.25 + 0.2 * i,
                ),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: AppTheme.alpha(AppTheme.greenSoft, 0.7),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ModesIllustration extends StatelessWidget {
  const _ModesIllustration();

  @override
  Widget build(BuildContext context) {
    const items = <(IconData, Color)>[
      (Icons.person_rounded, AppTheme.neonCyan),
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
