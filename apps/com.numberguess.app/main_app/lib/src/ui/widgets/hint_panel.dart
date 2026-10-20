import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../game/models/guess.dart';
import '../../l10n/strings.dart';

/// Màu gắn với từng mức nóng/lạnh. Để ở đây thay vì trong [AppTheme] vì nó chỉ
/// có nghĩa trong ngữ cảnh gợi ý.
Color heatColor(GuessHeat heat) {
  switch (heat) {
    case GuessHeat.none:
      return AppTheme.mint;
    case GuessHeat.freezing:
      return AppTheme.neonCyan;
    case GuessHeat.cold:
      return const Color(0xFF7FC4E8);
    case GuessHeat.warm:
      return AppTheme.sunGold;
    case GuessHeat.hot:
      return AppTheme.neonPink;
  }
}

IconData heatIcon(GuessHeat heat) {
  switch (heat) {
    case GuessHeat.none:
      return Icons.circle_outlined;
    case GuessHeat.freezing:
      return Icons.ac_unit_rounded;
    case GuessHeat.cold:
      return Icons.severe_cold_rounded;
    case GuessHeat.warm:
      return Icons.local_fire_department_outlined;
    case GuessHeat.hot:
      return Icons.local_fire_department_rounded;
  }
}

/// Khối gợi ý lớn ngay dưới thanh thống kê: CAO HƠN / THẤP HƠN cho lần đoán
/// vừa rồi, kèm khoảng số còn khả dĩ.
///
/// Đây là thứ người chơi nhìn nhiều nhất trong ván, nên nó chiếm nguyên một
/// khối to, mũi tên rõ và màu đổi theo hướng — đọc được bằng đuôi mắt trong
/// lúc tay vẫn đang bấm số.
class HintPanel extends StatelessWidget {
  /// Lần đoán gần nhất, null khi chưa đoán lần nào.
  final Guess? guess;

  /// Khoảng còn khả dĩ; null = người chơi tắt gợi ý khoảng trong Cài đặt.
  final (int low, int high)? bounds;

  const HintPanel({required this.guess, required this.bounds, super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final current = guess;

    final (String title, IconData icon, Color color) = switch (current?.hint) {
      null => (s.hintStart, Icons.search_rounded, scheme.primary),
      GuessHint.higher => (s.hintHigher, Icons.arrow_upward_rounded,
          AppTheme.sunGold),
      GuessHint.lower => (s.hintLower, Icons.arrow_downward_rounded,
          AppTheme.neonCyan),
      GuessHint.correct => (s.hintCorrect, Icons.check_circle_rounded,
          AppTheme.greenSoft),
    };

    final subtitle = switch (current?.hint) {
      null => null,
      GuessHint.higher => s.hintHigherThan(current!.value),
      GuessHint.lower => s.hintLowerThan(current!.value),
      GuessHint.correct => s.secretWas(current!.value),
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(
        color: AppTheme.alpha(color, 0.14),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.alpha(color, 0.55), width: 1.6),
      ),
      child: Column(
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, color: color, size: 30),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: color,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.alpha(scheme.onSurface, 0.75),
              ),
            ),
          ],
          if (current != null && current.heat != GuessHeat.none) ...<Widget>[
            const SizedBox(height: 10),
            _HeatBadge(heat: current.heat),
          ],
          if (bounds != null && current?.hint != GuessHint.correct) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              s.rangeStillPossible(bounds!.$1, bounds!.$2),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.primary,
                fontFeatures: const <FontFeature>[
                  FontFeature.tabularFigures(),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeatBadge extends StatelessWidget {
  final GuessHeat heat;

  const _HeatBadge({required this.heat});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final color = heatColor(heat);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.alpha(color, 0.2),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.alpha(color, 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(heatIcon(heat), size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            s.heatName(heat),
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Lịch sử các lần đoán, mới nhất bên trái.
///
/// Cuộn ngang một hàng chứ không phải danh sách dọc: lịch sử là thông tin phụ,
/// không được phép đẩy bàn phím số xuống dưới mép màn hình trên máy nhỏ.
class GuessHistoryStrip extends StatelessWidget {
  final List<Guess> guesses;

  const GuessHistoryStrip({required this.guesses, super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);

    if (guesses.isEmpty) {
      return SizedBox(
        height: 42,
        child: Center(
          child: Text(
            s.noGuessesYet,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppTheme.alpha(theme.colorScheme.onSurface, 0.5),
            ),
          ),
        ),
      );
    }

    final newestFirst = guesses.reversed.toList(growable: false);

    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: newestFirst.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) => _GuessPill(guess: newestFirst[index]),
      ),
    );
  }
}

class _GuessPill extends StatelessWidget {
  final Guess guess;

  const _GuessPill({required this.guess});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (IconData icon, Color color) = switch (guess.hint) {
      GuessHint.higher => (Icons.arrow_upward_rounded, AppTheme.sunGold),
      GuessHint.lower => (Icons.arrow_downward_rounded, AppTheme.neonCyan),
      GuessHint.correct => (Icons.check_rounded, AppTheme.greenSoft),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.alpha(color, 0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.alpha(color, 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '${guess.value}',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 4),
          Icon(icon, size: 18, color: color),
        ],
      ),
    );
  }
}
