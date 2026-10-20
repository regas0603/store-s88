import 'package:flutter/material.dart';
import '../core/achievements.dart';
import '../core/l10n.dart';
import '../core/text_app_style.dart';

/// US-004: Màn hình hiển thị toàn bộ badge (locked + unlocked) trong grid 3 cột.
/// Tap một badge → dialog detail với tên + mô tả + ngày đạt (nếu unlocked)
/// hoặc điều kiện (nếu locked).
class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  @override
  void initState() {
    super.initState();
    AchievementStore().addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    AchievementStore().removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  void _showBadgeDetail(BadgeDef def) {
    final AchievementStore store = AchievementStore();
    final bool unlocked = store.isUnlocked(def.id);
    final DateTime? at = store.unlockedDate(def.id);

    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a3e),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Large badge icon
            _BadgeIcon(def: def, unlocked: unlocked, size: 96),
            const SizedBox(height: 16),
            Text(
              l10n.get('${def.l10nKey}_name'),
              style: TextAppStyle.ui(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: unlocked ? def.tierColor : Colors.white54,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.get('${def.l10nKey}_desc'),
              style: TextAppStyle.ui(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            if (unlocked && at != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: def.tierColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${l10n.badgeUnlockedOn}: ${_formatDate(at)}',
                  style: TextAppStyle.ui(
                    fontSize: 11,
                    color: def.tierColor,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.close,
                style: const TextStyle(color: Color(0xFF4fc3f7))),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final AchievementStore store = AchievementStore();
    final int unlockedCount = store.unlockedCount;
    final int total = BadgeCatalog.count;

    return Scaffold(
      backgroundColor: const Color(0xFF070714),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          l10n.achievementsTitle,
          style: TextAppStyle.ui(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFFFFD700).withValues(alpha: 0.15),
                      const Color(0xFFFFD700).withValues(alpha: 0.05),
                    ],
                  ),
                  border: Border.all(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.emoji_events_rounded,
                        color: Color(0xFFFFD700), size: 32),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.badgeProgress,
                          style: TextAppStyle.ui(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                        Text(
                          '$unlockedCount / $total',
                          style: TextAppStyle.ui(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFFFFD700),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 60,
                      height: 60,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 50,
                            height: 50,
                            child: CircularProgressIndicator(
                              value: total == 0 ? 0 : unlockedCount / total,
                              strokeWidth: 4,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.1),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                  Color(0xFFFFD700)),
                            ),
                          ),
                          Text(
                            '${total == 0 ? 0 : ((unlockedCount * 100) / total).round()}%',
                            style: TextAppStyle.ui(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GridView.builder(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.78,
                  ),
                  itemCount: BadgeCatalog.count,
                  itemBuilder: (BuildContext ctx, int i) {
                    final BadgeDef def = BadgeCatalog.all[i];
                    final bool unlocked = store.isUnlocked(def.id);
                    return GestureDetector(
                      onTap: () => _showBadgeDetail(def),
                      child: _BadgeTile(def: def, unlocked: unlocked),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Badge Tile ───────────────────────────────────────────────────────────────

class _BadgeTile extends StatelessWidget {
  final BadgeDef def;
  final bool unlocked;
  const _BadgeTile({required this.def, required this.unlocked});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(
          color: unlocked
              ? def.tierColor.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.08),
          width: unlocked ? 1.5 : 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _BadgeIcon(def: def, unlocked: unlocked, size: 52),
          const SizedBox(height: 8),
          // Reserve exactly 2 lines of text height so every tile has the same
          // content height → icons thẳng hàng giữa các tile trong cùng 1 row.
          SizedBox(
            height: 26,
            child: Text(
              l10n.get('${def.l10nKey}_name'),
              style: TextAppStyle.ui(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: unlocked
                    ? def.tierColor
                    : Colors.white.withValues(alpha: 0.35),
                height: 1.1,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Badge Icon ───────────────────────────────────────────────────────────────

class _BadgeIcon extends StatelessWidget {
  final BadgeDef def;
  final bool unlocked;
  final double size;
  const _BadgeIcon({
    required this.def,
    required this.unlocked,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final Color color =
        unlocked ? def.tierColor : Colors.white.withValues(alpha: 0.2);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: unlocked
            ? RadialGradient(
                colors: [
                  color.withValues(alpha: 0.3),
                  color.withValues(alpha: 0.05),
                ],
              )
            : null,
        color: unlocked ? null : Colors.white.withValues(alpha: 0.03),
        border: Border.all(
          color: color.withValues(alpha: unlocked ? 0.6 : 0.25),
          width: unlocked ? 2 : 1,
        ),
        boxShadow: unlocked
            ? <BoxShadow>[
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: size * 0.25,
                ),
              ]
            : null,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(def.icon, color: color, size: size * 0.48),
          if (!unlocked)
            Positioned(
              bottom: size * 0.1,
              right: size * 0.1,
              child: Container(
                padding: EdgeInsets.all(size * 0.04),
                decoration: BoxDecoration(
                  color: const Color(0xFF070714),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lock,
                  size: size * 0.18,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
