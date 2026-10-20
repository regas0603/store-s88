import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/app_scope.dart';
import '../../core/theme.dart';
import '../../data/settings.dart';
import '../../game/models/card_icon.dart';
import '../../game/models/game_config.dart';
import '../../l10n/strings.dart';
import '../widgets/app_background.dart';
import 'tutorial_screen.dart';

/// Màn Cài đặt.
///
/// Nhóm theo việc người chơi muốn làm (nghe / nhìn / chơi / dữ liệu) chứ không
/// theo kiểu dữ liệu. Mọi thay đổi có hiệu lực ngay và tự lưu — không có nút
/// "Lưu", vì không ai muốn mất 3 lần chạm để tắt tiếng.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final scope = AppScope.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(s.settings),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: AppBackground(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: scope.settings,
            builder: (context, _) {
              final settings = scope.settings.value;
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: <Widget>[
                  _Section(
                    title: s.sectionAudio,
                    children: <Widget>[
                      SwitchListTile(
                        title: Text(s.sfx),
                        value: settings.soundEnabled,
                        onChanged: scope.settings.setSoundEnabled,
                        secondary: const Icon(Icons.graphic_eq_rounded),
                      ),
                      SwitchListTile(
                        title: Text(s.music),
                        subtitle: Text(s.musicHint),
                        value: settings.musicEnabled,
                        onChanged: scope.settings.setMusicEnabled,
                        secondary: const Icon(Icons.music_note_rounded),
                      ),
                      ListTile(
                        leading: const Icon(Icons.volume_up_rounded),
                        title: Text(s.volume),
                        subtitle: Slider(
                          value: settings.volume,
                          divisions: 10,
                          label: '${(settings.volume * 100).round()}%',
                          onChanged: scope.settings.setVolume,
                        ),
                      ),
                      SwitchListTile(
                        title: Text(s.haptics),
                        value: settings.hapticsEnabled,
                        onChanged: scope.settings.setHapticsEnabled,
                        secondary: const Icon(Icons.vibration_rounded),
                      ),
                    ],
                  ),
                  _Section(
                    title: s.sectionDisplay,
                    children: <Widget>[
                      _PickerTile<ThemeMode>(
                        icon: Icons.brightness_6_rounded,
                        title: s.theme,
                        value: settings.themeMode,
                        options: const <ThemeMode>[
                          ThemeMode.system,
                          ThemeMode.light,
                          ThemeMode.dark,
                        ],
                        labelOf: (mode) => switch (mode) {
                          ThemeMode.system => s.themeSystem,
                          ThemeMode.light => s.themeLight,
                          ThemeMode.dark => s.themeDark,
                        },
                        onSelected: scope.settings.setThemeMode,
                      ),
                      _PickerTile<LanguageSetting>(
                        icon: Icons.language_rounded,
                        title: s.language,
                        value: settings.language,
                        options: LanguageSetting.values,
                        labelOf: (language) => switch (language) {
                          LanguageSetting.system => s.languageSystem,
                          LanguageSetting.vi => 'Tiếng Việt',
                          LanguageSetting.en => 'English',
                        },
                        onSelected: scope.settings.setLanguage,
                      ),
                      SwitchListTile(
                        title: Text(s.showTimer),
                        subtitle: Text(s.showTimerHint),
                        value: settings.showTimer,
                        onChanged: scope.settings.setShowTimer,
                        secondary: const Icon(Icons.timer_outlined),
                      ),
                    ],
                  ),
                  _Section(
                    title: s.sectionGameplay,
                    children: <Widget>[
                      _PickerTile<BoardSize>(
                        icon: Icons.grid_view_rounded,
                        title: s.boardSizeLabel,
                        value: settings.boardSize,
                        options: BoardSize.values,
                        labelOf: (size) =>
                            '${s.boardSizeName(size)} · ${s.boardSizeDetail(size)}',
                        onSelected: scope.settings.setBoardSize,
                      ),
                      _PickerTile<AiDifficulty>(
                        icon: Icons.smart_toy_outlined,
                        title: s.difficultyLabel,
                        value: settings.aiDifficulty,
                        options: AiDifficulty.values,
                        labelOf: (level) =>
                            '${s.difficultyName(level)} · ${s.difficultyDetail(level)}',
                        onSelected: scope.settings.setAiDifficulty,
                      ),
                      _PickerTile<CardCategory?>(
                        icon: Icons.style_rounded,
                        title: s.cardThemeLabel,
                        value: settings.cardCategory,
                        options: <CardCategory?>[null, ...CardCategory.values],
                        labelOf: (category) => category == null
                            ? s.allThemes
                            : s.categoryName(category),
                        onSelected: scope.settings.setCardCategory,
                      ),
                      _PickerTile<int>(
                        icon: Icons.visibility_rounded,
                        title: s.peekSeconds,
                        subtitle: s.peekSecondsHint,
                        value: settings.peekSeconds,
                        options: const <int>[0, 1, 2, 3],
                        labelOf: s.secondsValue,
                        onSelected: scope.settings.setPeekSeconds,
                      ),
                    ],
                  ),
                  _Section(
                    title: s.sectionData,
                    children: <Widget>[
                      ListTile(
                        leading: const Icon(Icons.school_rounded),
                        title: Text(s.replayTutorial),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          scope.sound.tapFeedback();
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const TutorialScreen(),
                            ),
                          );
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.delete_sweep_rounded),
                        title: Text(s.resetStats),
                        onTap: () => _confirmAndRun(
                          context,
                          title: s.resetStats,
                          body: s.resetStatsConfirm,
                          action: scope.stats.reset,
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.restore_rounded),
                        title: Text(s.resetSettings),
                        onTap: () => _confirmAndRun(
                          context,
                          title: s.resetSettings,
                          body: s.resetSettingsConfirm,
                          action: scope.settings.resetToDefaults,
                        ),
                      ),
                    ],
                  ),
                  _Section(
                    title: s.sectionAbout,
                    children: <Widget>[
                      ListTile(
                        leading: const Icon(Icons.info_outline_rounded),
                        title: Text(s.version),
                        trailing: Text(AppInfo.displayVersion),
                      ),
                      ListTile(
                        leading: const Icon(Icons.copyright_rounded),
                        title: Text(s.credits),
                        subtitle: Text(s.creditsBody),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _confirmAndRun(
    BuildContext context, {
    required String title,
    required String body,
    required Future<void> Function() action,
  }) async {
    final s = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.confirm),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await action();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s.done), duration: const Duration(seconds: 2)),
    );
  }
}

/// Nhóm cài đặt với tiêu đề nhỏ phía trên.
class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
            child: Text(
              title.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: AppTheme.alpha(theme.colorScheme.onSurface, 0.6),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.panelColor(theme.colorScheme, theme.brightness),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppTheme.panelBorder(theme.colorScheme, theme.brightness),
              ),
            ),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

/// ListTile mở bottom sheet chọn một giá trị.
///
/// Tự dựng thay vì dùng [RadioListTile]/[DropdownButton]: API radio của Flutter
/// đang trong quá trình thay đổi giữa các bản SDK, còn dropdown thì chật chội
/// với nhãn dài như "Siêu lớn · 6×8 · 24 cặp".
class _PickerTile<T> extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final T value;
  final List<T> options;
  final String Function(T value) labelOf;
  final Future<void> Function(T value) onSelected;

  const _PickerTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.options,
    required this.labelOf,
    required this.onSelected,
    this.subtitle,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 150),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(
              child: Text(
                labelOf(value),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(Icons.expand_more_rounded, size: 20),
          ],
        ),
      ),
      onTap: () => _pick(context),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final scope = AppScope.of(context);
    scope.sound.tapFeedback();

    final selected = await showModalBottomSheet<_Selection<T>>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            for (final option in options)
              ListTile(
                title: Text(labelOf(option)),
                trailing: option == value
                    ? Icon(
                        Icons.check_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : null,
                onTap: () =>
                    Navigator.of(context).pop(_Selection<T>(option)),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (selected == null) return;
    await onSelected(selected.value);
  }
}

/// Bọc giá trị để phân biệt "người dùng chọn null" với "đóng sheet".
class _Selection<T> {
  final T value;

  const _Selection(this.value);
}
