import 'package:flutter/material.dart';
import '../core/app_settings.dart';
import '../core/game_history.dart';
import '../core/l10n.dart';
import '../core/text_app_style.dart';

/// Thống kê tổng hợp từ [GameHistory]:
/// - Tổng số ván, thắng / thua / hòa, win-rate
/// - Chia theo mode (2P vs vsAI) và theo AI difficulty
/// - Chuỗi thắng dài nhất, tổng thời gian chơi
class StatisticsScreen extends StatelessWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070714),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildHeader(context),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
          Text(
            l10n.statisticsTitle,
            style: TextAppStyle.pressStart2p(
              color: Colors.white,
              fontSize: 16,
            ).copyWith(letterSpacing: 2),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final List<GameRecord> records = GameHistory().records;
    if (records.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            l10n.statNoData,
            textAlign: TextAlign.center,
            style: TextAppStyle.ui(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 15,
              height: 1.5,
            ),
          ),
        ),
      );
    }

    final _Stats stats = _Stats.compute(records);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: <Widget>[
        _OverviewCard(stats: stats),
        const SizedBox(height: 16),
        _SectionTitle(text: l10n.statByMode),
        _ModeBreakdown(stats: stats),
        if (stats.byDifficulty.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          _SectionTitle(text: l10n.statByDifficulty),
          _DifficultyBreakdown(stats: stats),
        ],
      ],
    );
  }
}

// ─── Stats computation ───────────────────────────────────────────────────────

class _Stats {
  final int totalGames;
  final int wins; // User (X) wins
  final int losses; // User (X) losses
  final int draws;
  final int timeouts;
  final int bestStreak;
  final int totalPlaySecs;

  /// Map<mode, (games, wins, losses, draws)>
  final Map<GameMode, _ModeStats> byMode;

  /// Map<difficultyIndex, (games, wins, losses, draws)> — only vsAI with index != -1
  final Map<int, _ModeStats> byDifficulty;

  const _Stats({
    required this.totalGames,
    required this.wins,
    required this.losses,
    required this.draws,
    required this.timeouts,
    required this.bestStreak,
    required this.totalPlaySecs,
    required this.byMode,
    required this.byDifficulty,
  });

  double get winRate => totalGames == 0 ? 0 : wins / totalGames;

  factory _Stats.compute(List<GameRecord> records) {
    int wins = 0, losses = 0, draws = 0, timeouts = 0, totalSecs = 0;
    int bestStreak = 0, currentStreak = 0;
    final Map<GameMode, _ModeStatsBuilder> byMode =
        <GameMode, _ModeStatsBuilder>{};
    final Map<int, _ModeStatsBuilder> byDiff = <int, _ModeStatsBuilder>{};

    // Records are stored newest-first; iterate oldest-first to compute streak.
    final List<GameRecord> chronological = records.reversed.toList();
    for (final GameRecord r in chronological) {
      totalSecs += r.durationSecs;
      final bool userIsX = true; // In current game, user is always X.
      final bool userWon = r.result == GameResult.xWins;
      final bool userLost = r.result == GameResult.oWins ||
          (r.result == GameResult.timeout && userIsX);
      final bool isDraw = r.result == GameResult.draw;

      if (userWon) {
        wins++;
        currentStreak++;
        if (currentStreak > bestStreak) bestStreak = currentStreak;
      } else if (userLost) {
        losses++;
        currentStreak = 0;
      } else if (isDraw) {
        draws++;
        currentStreak = 0;
      }
      if (r.result == GameResult.timeout) timeouts++;

      final _ModeStatsBuilder mb =
          byMode.putIfAbsent(r.mode, () => _ModeStatsBuilder());
      mb.add(r);

      if (r.mode == GameMode.vsAI && r.aiDifficultyIndex >= 0) {
        final _ModeStatsBuilder db =
            byDiff.putIfAbsent(r.aiDifficultyIndex, () => _ModeStatsBuilder());
        db.add(r);
      }
    }

    return _Stats(
      totalGames: records.length,
      wins: wins,
      losses: losses,
      draws: draws,
      timeouts: timeouts,
      bestStreak: bestStreak,
      totalPlaySecs: totalSecs,
      byMode: byMode.map(
        (GameMode k, _ModeStatsBuilder v) =>
            MapEntry<GameMode, _ModeStats>(k, v.build()),
      ),
      byDifficulty: byDiff.map(
        (int k, _ModeStatsBuilder v) =>
            MapEntry<int, _ModeStats>(k, v.build()),
      ),
    );
  }
}

class _ModeStats {
  final int games;
  final int wins;
  final int losses;
  final int draws;

  const _ModeStats({
    required this.games,
    required this.wins,
    required this.losses,
    required this.draws,
  });

  double get winRate => games == 0 ? 0 : wins / games;
}

class _ModeStatsBuilder {
  int games = 0;
  int wins = 0;
  int losses = 0;
  int draws = 0;

  void add(GameRecord r) {
    games++;
    if (r.result == GameResult.xWins) wins++;
    if (r.result == GameResult.oWins) losses++;
    if (r.result == GameResult.timeout) losses++;
    if (r.result == GameResult.draw) draws++;
  }

  _ModeStats build() => _ModeStats(
        games: games,
        wins: wins,
        losses: losses,
        draws: draws,
      );
}

// ─── Widgets ─────────────────────────────────────────────────────────────────

class _OverviewCard extends StatelessWidget {
  final _Stats stats;
  const _OverviewCard({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF1a1a3e), Color(0xFF0d0d22)],
        ),
        border: Border.all(color: const Color(0xFF4fc3f7).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _bigStat(
                  label: l10n.statTotalGames,
                  value: '${stats.totalGames}',
                  color: const Color(0xFF4fc3f7),
                ),
              ),
              Expanded(
                child: _bigStat(
                  label: l10n.statWinRate,
                  value: '${(stats.winRate * 100).toStringAsFixed(0)}%',
                  color: const Color(0xFFFFD700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: <Widget>[
              Expanded(
                child: _smallStat(
                  label: l10n.statWins,
                  value: '${stats.wins}',
                  color: const Color(0xFF80FFDB),
                ),
              ),
              Expanded(
                child: _smallStat(
                  label: l10n.statLosses,
                  value: '${stats.losses}',
                  color: const Color(0xFFf48fb1),
                ),
              ),
              Expanded(
                child: _smallStat(
                  label: l10n.statDraws,
                  value: '${stats.draws}',
                  color: const Color(0xFFFFD23F),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),
          const SizedBox(height: 16),
          _textRow(
            icon: Icons.whatshot_rounded,
            label: l10n.statBestStreak,
            value: '${stats.bestStreak}',
            color: const Color(0xFFFF6B35),
          ),
          const SizedBox(height: 10),
          _textRow(
            icon: Icons.timer_outlined,
            label: l10n.statTotalPlayTime,
            value: _formatDuration(stats.totalPlaySecs),
            color: const Color(0xFF56CFE1),
          ),
        ],
      ),
    );
  }

  static String _formatDuration(int secs) {
    final int h = secs ~/ 3600;
    final int m = (secs % 3600) ~/ 60;
    final int s = secs % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  Widget _bigStat({required String label, required String value, required Color color}) {
    return Column(
      children: <Widget>[
        Text(
          value,
          style: TextAppStyle.pressStart2p(color: color, fontSize: 22, shadows: <Shadow>[
            Shadow(color: color.withValues(alpha: 0.5), blurRadius: 12),
          ]),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextAppStyle.ui(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _smallStat({required String label, required String value, required Color color}) {
    return Column(
      children: <Widget>[
        Text(
          value,
          style: TextAppStyle.rajdhani(
            color: color,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextAppStyle.ui(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _textRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      children: <Widget>[
        Icon(icon, color: color.withValues(alpha: 0.7), size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextAppStyle.ui(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 13,
            ),
          ),
        ),
        Text(
          value,
          style: TextAppStyle.rajdhani(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 0, 10),
      child: Text(
        text,
        style: TextAppStyle.rajdhani(
          color: Colors.white.withValues(alpha: 0.55),
          fontSize: 13,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

class _ModeBreakdown extends StatelessWidget {
  final _Stats stats;
  const _ModeBreakdown({required this.stats});

  @override
  Widget build(BuildContext context) {
    final _ModeStats? pvp = stats.byMode[GameMode.twoPlayers];
    final _ModeStats? vsAi = stats.byMode[GameMode.vsAI];
    return Column(
      children: <Widget>[
        if (pvp != null)
          _row(label: l10n.twoPlayers, stats: pvp, color: const Color(0xFFf48fb1)),
        if (vsAi != null) ...<Widget>[
          if (pvp != null) const SizedBox(height: 8),
          _row(label: l10n.vsAI, stats: vsAi, color: const Color(0xFF4fc3f7)),
        ],
      ],
    );
  }

  Widget _row({required String label, required _ModeStats stats, required Color color}) =>
      _StatBar(label: label, stats: stats, color: color);
}

class _DifficultyBreakdown extends StatelessWidget {
  final _Stats stats;
  const _DifficultyBreakdown({required this.stats});

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[];
    for (final AiDifficulty d in AiDifficulty.values) {
      final _ModeStats? ms = stats.byDifficulty[d.index];
      if (ms == null) continue;
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 8));
      rows.add(_StatBar(
        label: _difficultyLabel(d),
        stats: ms,
        color: _difficultyColor(d),
      ));
    }
    return Column(children: rows);
  }

  String _difficultyLabel(AiDifficulty d) {
    switch (d) {
      case AiDifficulty.low:
        return l10n.aiDifficultyLow;
      case AiDifficulty.medium:
        return l10n.aiDifficultyMedium;
      case AiDifficulty.high:
        return l10n.aiDifficultyHigh;
    }
  }

  Color _difficultyColor(AiDifficulty d) {
    switch (d) {
      case AiDifficulty.low:
        return const Color(0xFF80FFDB);
      case AiDifficulty.medium:
        return const Color(0xFFFFD23F);
      case AiDifficulty.high:
        return const Color(0xFFFF6B35);
    }
  }
}

class _StatBar extends StatelessWidget {
  final String label;
  final _ModeStats stats;
  final Color color;

  const _StatBar({
    required this.label,
    required this.stats,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                label,
                style: TextAppStyle.rajdhani(
                  color: color,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                '${(stats.winRate * 100).toStringAsFixed(0)}%',
                style: TextAppStyle.rajdhani(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: stats.winRate,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              _tag(l10n.statWins, '${stats.wins}', const Color(0xFF80FFDB)),
              const SizedBox(width: 10),
              _tag(l10n.statLosses, '${stats.losses}', const Color(0xFFf48fb1)),
              const SizedBox(width: 10),
              _tag(l10n.statDraws, '${stats.draws}', const Color(0xFFFFD23F)),
              const Spacer(),
              Text(
                '${stats.games}',
                style: TextAppStyle.ui(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tag(String label, String value, Color color) {
    return Row(
      children: <Widget>[
        Text(
          '$label: ',
          style: TextAppStyle.ui(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 11,
          ),
        ),
        Text(
          value,
          style: TextAppStyle.ui(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
