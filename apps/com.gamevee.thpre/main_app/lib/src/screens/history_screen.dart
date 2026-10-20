import 'package:flutter/material.dart';
import '../core/game_history.dart';
import '../core/game_analysis.dart';
import '../core/l10n.dart';
import '../core/quality_palette.dart';
import 'analysis/analysis_progress_dialog.dart';
import 'analysis/analysis_replay_screen.dart';
import '../core/text_app_style.dart';
import 'replay_screen.dart';
import 'statistics_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _history = GameHistory();

  @override
  Widget build(BuildContext context) {
    final records = _history.records;

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
                  Expanded(
                    child: Text(
                      l10n.historyTitle,
                      style: TextAppStyle.sfProWithCjkFallback(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 3,
                      ),
                    ),
                  ),
                  if (records.isNotEmpty) ...<Widget>[
                    GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const StatisticsScreen(),
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15)),
                          color: Colors.white.withValues(alpha: 0.05),
                        ),
                        child: const Icon(Icons.bar_chart_rounded,
                            color: Colors.white, size: 18),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _confirmClear,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: Colors.red.withValues(alpha: 0.4)),
                          color: Colors.red.withValues(alpha: 0.1),
                        ),
                        child: Text(
                          l10n.clearHistory,
                          style: TextAppStyle.sfProWithCjkFallback(
                            color: Colors.red.withValues(alpha: 0.8),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Stats summary
            if (records.isNotEmpty) _StatsSummary(records: records),
            // List
            Expanded(
              child: records.isEmpty
                  ? _EmptyState()
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: records.length,
                      itemBuilder: (_, i) =>
                          _RecordCard(record: records[i], index: i),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a3e),
        title: Text(
          l10n.clearHistory,
          style: TextAppStyle.sfProWithCjkFallback(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Bạn có chắc muốn xóa toàn bộ lịch sử?',
          style: TextAppStyle.sfProWithCjkFallback(
              color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Hủy',
                style: TextAppStyle.sfProWithCjkFallback(
                    color: Colors.white, fontSize: 16)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Xóa',
                style: TextAppStyle.sfProWithCjkFallback(
                    color: Colors.red,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _history.clear();
      setState(() {});
    }
  }
}

class _StatsSummary extends StatelessWidget {
  final List<GameRecord> records;
  const _StatsSummary({required this.records});

  @override
  Widget build(BuildContext context) {
    final xWins = records.where((r) => r.result == GameResult.xWins).length;
    final oWins = records.where((r) => r.result == GameResult.oWins).length;
    final draws = records.where((r) => r.result == GameResult.draw).length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF1a1a3e), Color(0xFF0d0d22)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatChip(
              label: 'X Thắng',
              value: '$xWins',
              color: const Color(0xFF4fc3f7)),
          _StatChip(
              label: 'Hòa', value: '$draws', color: const Color(0xFFFFD700)),
          _StatChip(
              label: 'O Thắng',
              value: '$oWins',
              color: const Color(0xFFf48fb1)),
          _StatChip(
              label: 'Tổng', value: '${records.length}', color: Colors.white),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextAppStyle.sfProWithCjkFallback(
            color: color,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextAppStyle.sfProWithCjkFallback(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _RecordCard extends StatelessWidget {
  final GameRecord record;
  final int index;
  const _RecordCard({required this.record, required this.index});

  Color get _resultColor {
    switch (record.result) {
      case GameResult.xWins:
        return const Color(0xFF4fc3f7);
      case GameResult.oWins:
        return const Color(0xFFf48fb1);
      case GameResult.draw:
        return const Color(0xFFFFD700);
      case GameResult.timeout:
        return Colors.orange;
    }
  }

  String get _resultText {
    switch (record.result) {
      case GameResult.xWins:
        return l10n.xWins;
      case GameResult.oWins:
        return l10n.oWins;
      case GameResult.draw:
        return l10n.draw;
      case GameResult.timeout:
        return l10n.timeout;
    }
  }

  String get _modeText =>
      record.mode == GameMode.vsAI ? '🤖 VS AI' : '👥 2 Người';

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final Widget card = Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _resultColor.withValues(alpha: 0.25)),
        color: _resultColor.withValues(alpha: 0.05),
      ),
      child: Row(
        children: [
          // Index
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _resultColor.withValues(alpha: 0.15),
            ),
            child: Center(
              child: Text(
                l10n.resultListMark(record.result),
                style: TextAppStyle.ui(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: _resultColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _resultText,
                  style: TextAppStyle.sfProWithCjkFallback(
                    color: _resultColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$_modeText  •  ${l10n.formatHistoryBoardLine(record.boardSide, record.winLength)}  •  ${l10n.formatHistoryMoveCount(record.totalMoves)}  •  ${record.durationText}',
                  style: TextAppStyle.sfProWithCjkFallback(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (record.hasAnalysis) ...<Widget>[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: QualityPalette.accuracyColor(record.analysis!.accuracyX)
                    .withValues(alpha: 0.15),
                border: Border.all(
                  color:
                      QualityPalette.accuracyColor(record.analysis!.accuracyX)
                          .withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                '${record.analysis!.accuracyX}%',
                style: TextAppStyle.rajdhani(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color:
                      QualityPalette.accuracyColor(record.analysis!.accuracyX),
                ),
              ),
            ),
            const SizedBox(width: 4),
          ] else if (record.canAnalyze) ...<Widget>[
            const SizedBox(width: 8),
            Icon(
              Icons.insights_rounded,
              color: Colors.white.withValues(alpha: 0.35),
              size: 18,
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.play_circle_rounded,
              color: _resultColor.withValues(alpha: 0.8),
              size: 24,
            ),
            const SizedBox(width: 4),
          ] else if (record.canReplay) ...<Widget>[
            const SizedBox(width: 8),
            Icon(
              Icons.play_circle_rounded,
              color: _resultColor.withValues(alpha: 0.8),
              size: 24,
            ),
            const SizedBox(width: 4),
          ] else
            Text(
              _formatDate(record.playedAt),
              style: TextAppStyle.sfProWithCjkFallback(
                color: Colors.white.withValues(alpha: 0.25),
                fontSize: 10,
              ),
            ),
        ],
      ),
    );

    if (!record.canReplay) return card;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openRecord(context, record),
      child: card,
    );
  }

  /// Ván đã phân tích -> mở thẳng màn phân tích, KHÔNG tính lại.
  /// Ván đủ dài mà chưa phân tích -> chạy phân tích lần đầu.
  /// Còn lại -> phát lại như cũ.
  Future<void> _openRecord(BuildContext context, GameRecord record) async {
    final GameAnalysis? existing = record.analysis;
    if (existing != null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              AnalysisReplayScreen(record: record, analysis: existing),
        ),
      );
      return;
    }

    if (record.canAnalyze) {
      final GameAnalysis? fresh = await runAnalysisWithDialog(context, record);
      if (fresh != null) {
        if (!context.mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AnalysisReplayScreen(
              record: record.copyWithAnalysis(fresh),
              analysis: fresh,
            ),
          ),
        );
        return;
      }
      if (!context.mounted) return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReplayScreen(record: record),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🎮', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text(
            l10n.noHistory,
            style: TextAppStyle.sfProWithCjkFallback(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 16,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }
}
