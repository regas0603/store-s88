import 'package:flutter/material.dart';
import '../core/app_settings.dart';
import '../core/l10n.dart';
import '../core/text_app_style.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settings = AppSettings();

  @override
  void initState() {
    super.initState();
    _settings.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _settings.removeListener(_rebuild);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070714),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15)),
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                      child: const Icon(Icons.arrow_back_ios,
                          color: Colors.white, size: 18),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    l10n.settingsTitle,
                    style: TextAppStyle.sfProWithCjkFallback(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                    ),
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionTitle(
                        icon: Icons.timer_outlined, title: l10n.turnTime),
                    const SizedBox(height: 12),
                    _TurnTimeSelector(
                      current: _settings.turnTimeSecs,
                      onChanged: (v) => _settings.setTurnTime(v),
                    ),
                    const SizedBox(height: 28),
                    _SectionTitle(
                        icon: Icons.palette_outlined, title: l10n.skin),
                    const SizedBox(height: 12),
                    _SkinSelector(
                      current: _settings.skin,
                      onChanged: (s) => _settings.setSkin(s),
                    ),
                    const SizedBox(height: 28),
                    _SectionTitle(
                      icon: Icons.grid_view_rounded,
                      title: l10n.boardBackground,
                    ),
                    const SizedBox(height: 12),
                    _BoardBackgroundSelector(
                      current: _settings.boardBackground,
                      onChanged: (BoardBackground b) =>
                          _settings.setBoardBackground(b),
                    ),
                    const SizedBox(height: 28),
                    _SectionTitle(
                      icon: Icons.crop_square_outlined,
                      title: l10n.boardSize,
                    ),
                    const SizedBox(height: 12),
                    _BoardSizePresetSelector(
                      current: _settings.boardSizePreset,
                      onChanged: (BoardSizePreset p) =>
                          _settings.setBoardSizePreset(p),
                    ),
                    const SizedBox(height: 28),
                    _SectionTitle(icon: Icons.language, title: l10n.language),
                    const SizedBox(height: 12),
                    _LanguageSelector(
                      current: _settings.language,
                      onChanged: (lang) {
                        _settings.setLanguage(lang);
                        l10n.setLanguage(lang);
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 28),
                    _SectionTitle(
                        icon: Icons.music_note_rounded, title: l10n.sound),
                    const SizedBox(height: 12),
                    _SoundToggle(
                      enabled: _settings.soundEnabled,
                      onChanged: (v) => _settings.setSoundEnabled(v),
                    ),
                    const SizedBox(height: 28),
                    _SectionTitle(
                      icon: Icons.smart_toy_outlined,
                      title: l10n.aiDifficulty,
                    ),
                    const SizedBox(height: 12),
                    _AiDifficultySelector(
                      current: _settings.aiDifficulty,
                      onChanged: (AiDifficulty d) => _settings.setAiDifficulty(d),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final Color tint = Colors.white.withValues(alpha: 0.7);
    final TextStyle titleStyle = TextAppStyle.sfProWithCjkFallback(
      color: tint,
      fontSize: 16,
      fontWeight: FontWeight.bold,
      letterSpacing: 2,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 22, color: tint),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            title,
            style: titleStyle,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ─── Turn Time Selector ───────────────────────────────────────────────────────

class _TurnTimeSelector extends StatelessWidget {
  final int current;
  final ValueChanged<int> onChanged;

  const _TurnTimeSelector({required this.current, required this.onChanged});

  static const options = [0, 10, 15, 20, 30, 60];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: options.map((secs) {
        final selected = current == secs;
        final label = secs == 0 ? l10n.noLimit : '${secs}s';
        return GestureDetector(
          onTap: () => onChanged(secs),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? const Color(0xFF4fc3f7)
                    : Colors.white.withValues(alpha: 0.2),
                width: selected ? 1.5 : 1,
              ),
              color: selected
                  ? const Color(0xFF4fc3f7).withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.04),
            ),
            child: Text(
              label,
              style: TextAppStyle.ui(
                color: selected
                    ? const Color(0xFF4fc3f7)
                    : Colors.white.withValues(alpha: 0.5),
                fontWeight: FontWeight.bold,
                fontSize: 15,
                letterSpacing: 1,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Skin Selector ────────────────────────────────────────────────────────────

class _SkinSelector extends StatelessWidget {
  final PieceSkin current;
  final ValueChanged<PieceSkin> onChanged;

  const _SkinSelector({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: PieceSkin.values.map((skin) {
        final selected = current == skin;
        return GestureDetector(
          onTap: () => onChanged(skin),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? skin.xColor
                    : Colors.white.withValues(alpha: 0.1),
                width: selected ? 1.5 : 1,
              ),
              color: selected
                  ? skin.xColor.withValues(alpha: 0.1)
                  : Colors.white.withValues(alpha: 0.03),
            ),
            child: Row(
              children: [
                // X preview
                _PiecePreview(color: skin.xColor, isX: true),
                const SizedBox(width: 8),
                // O preview
                _PiecePreview(color: skin.oColor, isX: false),
                const SizedBox(width: 16),
                Text(
                  l10n.skinLabel(skin),
                  style: TextAppStyle.ui(
                    color: selected
                        ? skin.xColor
                        : Colors.white.withValues(alpha: 0.6),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    letterSpacing: 1,
                  ),
                ),
                const Spacer(),
                if (selected)
                  Icon(Icons.check_circle, color: skin.xColor, size: 20),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Board background ─────────────────────────────────────────────────────────

class _BoardBackgroundSelector extends StatelessWidget {
  final BoardBackground current;
  final ValueChanged<BoardBackground> onChanged;

  const _BoardBackgroundSelector({
    required this.current,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: BoardBackground.values.map((BoardBackground bg) {
        final bool selected = current == bg;
        final Color accent = Color.lerp(bg.colorA, bg.colorB, 0.5)!;
        return GestureDetector(
          onTap: () => onChanged(bg),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? accent
                    : Colors.white.withValues(alpha: 0.1),
                width: selected ? 1.5 : 1,
              ),
              color: selected
                  ? accent.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.03),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [bg.colorA, bg.colorB],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    l10n.boardBackgroundLabel(bg),
                    style: TextAppStyle.ui(
                      color: selected
                          ? accent
                          : Colors.white.withValues(alpha: 0.6),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle, color: accent, size: 20),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Board size preset ────────────────────────────────────────────────────────

class _BoardSizePresetSelector extends StatelessWidget {
  final BoardSizePreset current;
  final ValueChanged<BoardSizePreset> onChanged;

  const _BoardSizePresetSelector({
    required this.current,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: BoardSizePreset.values.map((BoardSizePreset preset) {
        final bool selected = current == preset;
        const Color accent = Color(0xFF4fc3f7);
        return GestureDetector(
          onTap: () => onChanged(preset),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? accent
                    : Colors.white.withValues(alpha: 0.1),
                width: selected ? 1.5 : 1,
              ),
              color: selected
                  ? accent.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.03),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.grid_on_rounded,
                  color: selected ? accent : Colors.white.withValues(alpha: 0.45),
                  size: 28,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    l10n.boardSizePresetLabel(preset),
                    style: TextAppStyle.sfProWithCjkFallback(
                      color: selected
                          ? accent
                          : Colors.white.withValues(alpha: 0.65),
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_circle, color: accent, size: 20),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _PiecePreview extends StatelessWidget {
  final Color color;
  final bool isX;
  const _PiecePreview({required this.color, required this.isX});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 30,
      child: CustomPaint(
        painter: _PreviewPainter(color: color, isX: isX),
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  final Color color;
  final bool isX;
  _PreviewPainter({required this.color, required this.isX});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final r = size.width / 2 - 4;
    final cx = size.width / 2;
    final cy = size.height / 2;
    if (isX) {
      canvas.drawLine(Offset(cx - r, cy - r), Offset(cx + r, cy + r), paint);
      canvas.drawLine(Offset(cx + r, cy - r), Offset(cx - r, cy + r), paint);
    } else {
      canvas.drawCircle(Offset(cx, cy), r, paint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// ─── Language Selector ────────────────────────────────────────────────────────

class _LanguageSelector extends StatelessWidget {
  final AppLanguage current;
  final ValueChanged<AppLanguage> onChanged;

  const _LanguageSelector({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: AppLanguage.values.map((lang) {
        final selected = current == lang;
        return GestureDetector(
          onTap: () => onChanged(lang),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? const Color(0xFF80FFDB)
                    : Colors.white.withValues(alpha: 0.15),
                width: selected ? 1.5 : 1,
              ),
              color: selected
                  ? const Color(0xFF80FFDB).withValues(alpha: 0.1)
                  : Colors.white.withValues(alpha: 0.04),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Text(
                //   lang.flag,
                //   style: TextAppStyle.emojiOnly(
                //     fontSize: 20,
                //     color: selected
                //         ? const Color(0xFF80FFDB)
                //         : Colors.white.withValues(alpha: 0.85),
                //   ),
                // ),
                const SizedBox(width: 8),
                Text(
                  lang.label,
                  style: TextAppStyle.ui(
                    color: selected
                        ? const Color(0xFF80FFDB)
                        : Colors.white.withValues(alpha: 0.5),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Sound Toggle ─────────────────────────────────────────────────────────────

class _SoundToggle extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _SoundToggle({required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!enabled),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: enabled
                ? const Color(0xFFFFD700)
                : Colors.white.withValues(alpha: 0.1),
          ),
          color: enabled
              ? const Color(0xFFFFD700).withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.03),
        ),
        child: Row(
          children: [
            Icon(
              enabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              color: enabled
                  ? const Color(0xFFFFD700)
                  : Colors.white.withValues(alpha: 0.3),
              size: 24,
            ),
            const SizedBox(width: 14),
            Text(
              enabled ? l10n.soundOn : l10n.soundOff,
              style: TextAppStyle.ui(
                color: enabled
                    ? const Color(0xFFFFD700)
                    : Colors.white.withValues(alpha: 0.4),
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const Spacer(),
            _ToggleSwitch(value: enabled, color: const Color(0xFFFFD700)),
          ],
        ),
      ),
    );
  }
}

// ─── AI difficulty (VS AI) ────────────────────────────────────────────────────

class _AiDifficultySelector extends StatelessWidget {
  final AiDifficulty current;
  final ValueChanged<AiDifficulty> onChanged;

  const _AiDifficultySelector({
    required this.current,
    required this.onChanged,
  });

  String _label(AiDifficulty d) {
    switch (d) {
      case AiDifficulty.low:
        return l10n.aiDifficultyLow;
      case AiDifficulty.medium:
        return l10n.aiDifficultyMedium;
      case AiDifficulty.high:
        return l10n.aiDifficultyHigh;
    }
  }

  Color _color(AiDifficulty d) {
    switch (d) {
      case AiDifficulty.low:
        return const Color(0xFF8BC34A);
      case AiDifficulty.medium:
        return const Color(0xFFFFD700);
      case AiDifficulty.high:
        return const Color(0xFFFF5252);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: AiDifficulty.values.map((AiDifficulty d) {
        final bool selected = current == d;
        final Color accent = _color(d);
        return GestureDetector(
          onTap: () => onChanged(d),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? accent
                    : Colors.white.withValues(alpha: 0.15),
                width: selected ? 1.5 : 1,
              ),
              color: selected
                  ? accent.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.04),
            ),
            child: Text(
              _label(d),
              style: TextAppStyle.ui(
                color: selected
                    ? accent
                    : Colors.white.withValues(alpha: 0.5),
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ToggleSwitch extends StatelessWidget {
  final bool value;
  final Color color;
  const _ToggleSwitch({required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 48,
      height: 26,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        color: value
            ? color.withValues(alpha: 0.3)
            : Colors.white.withValues(alpha: 0.1),
        border: Border.all(
            color: value ? color : Colors.white.withValues(alpha: 0.2)),
      ),
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            left: value ? 24 : 2,
            top: 2,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value ? color : Colors.white.withValues(alpha: 0.3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
