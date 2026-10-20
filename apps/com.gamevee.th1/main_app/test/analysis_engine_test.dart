import 'dart:convert';

import 'package:main_app_package/src/core/achievements.dart';
import 'package:main_app_package/src/core/game_analysis.dart';
import 'package:main_app_package/src/core/game_history.dart';
import 'package:main_app_package/src/game/ai_engine.dart';
import 'package:main_app_package/src/game/analysis_engine.dart';
import 'package:flutter_test/flutter_test.dart';

List<List<int>> emptyBoard(int n) =>
    List<List<int>>.generate(n, (_) => List<int>.filled(n, 0));

void main() {
  group('AnalysisEngine.advantage', () {
    test('đối xứng tuyệt đối: adv(b,1) == -adv(b,2)', () {
      // Đây là bất biến nền tảng của cả tính năng. AiEngine._evaluateBoard
      // KHÔNG có tính chất này (nó nhân điểm đối thủ với 1.2 + centre bonus),
      // nên tầng phân tích phải tự dựng thang đo từ threatScoreFor.
      final List<List<int>> b = emptyBoard(15);
      b[7][5] = 1;
      b[7][6] = 1;
      b[7][7] = 1;
      b[8][5] = 2;
      b[8][6] = 2;

      final double a1 = AnalysisEngine.advantage(b, 15, 5, 1);
      final double a2 = AnalysisEngine.advantage(b, 15, 5, 2);
      expect(a1, closeTo(-a2, 1e-12));
      expect(a1, greaterThan(0), reason: 'X có open three nên phải dương');
    });

    test('bàn trống là cân bằng', () {
      expect(AnalysisEngine.advantage(emptyBoard(9), 9, 5, 1), 0.0);
      expect(AnalysisEngine.advantage(emptyBoard(9), 9, 5, 2), 0.0);
    });

    test('thế thắng trả về đúng ±1', () {
      final List<List<int>> b = emptyBoard(15);
      for (int c = 3; c < 8; c++) {
        b[7][c] = 1;
      }
      expect(AnalysisEngine.advantage(b, 15, 5, 1), 1.0);
      expect(AnalysisEngine.advantage(b, 15, 5, 2), -1.0);
    });

    test('mối đe doạ mạnh hơn cho lợi thế lớn hơn', () {
      final List<List<int>> two = emptyBoard(15);
      two[7][6] = 1;
      two[7][7] = 1;

      final List<List<int>> three = emptyBoard(15);
      three[7][6] = 1;
      three[7][7] = 1;
      three[7][8] = 1;

      expect(
        AnalysisEngine.advantage(three, 15, 5, 1),
        greaterThan(AnalysisEngine.advantage(two, 15, 5, 1)),
      );
    });

    test('luôn nằm trong khoảng [-1, 1]', () {
      final List<List<int>> b = emptyBoard(15);
      for (int c = 0; c < 4; c++) {
        b[7][c] = 1;
        b[9][c] = 2;
      }
      for (final int p in <int>[1, 2]) {
        final double v = AnalysisEngine.advantage(b, 15, 5, p);
        expect(v, inInclusiveRange(-1.0, 1.0));
      }
    });
  });

  group('AiEngine — API bổ sung không phá gameplay', () {
    test('flipPlayers đảo đúng và không đụng ô trống', () {
      final List<List<int>> b = emptyBoard(4);
      b[0][0] = 1;
      b[1][1] = 2;
      final List<List<int>> f = AiEngine.flipPlayers(b, 4);
      expect(f[0][0], 2);
      expect(f[1][1], 1);
      expect(f[3][3], 0);
      // bản gốc không bị sửa
      expect(b[0][0], 1);
    });

    test('threatScoreFor đếm mỗi chuỗi đúng một lần', () {
      final List<List<int>> b = emptyBoard(15);
      b[7][6] = 1;
      b[7][7] = 1;
      b[7][8] = 1;
      final int x = AiEngine.threatScoreFor(b, 15, 5, 1);
      final int o = AiEngine.threatScoreFor(b, 15, 5, 2);
      expect(o, 0);
      // 10009 = một open three (10 000) theo phương ngang
      //       + 3 quân x 3 phương còn lại, mỗi quân là chuỗi dài 1 (_sOpen1 = 1).
      // Con số này đã được đối chiếu với chính thuật toán của AiEngine; nếu
      // canonical-start bị hỏng, kết quả sẽ thành bội số của 10 000.
      expect(x, 10009);
    });
  });

  group('AnalysisEngine.rebuildBoard', () {
    test('dựng lại đúng dãy nước thường', () {
      final List<AnalysisMove> moves = <AnalysisMove>[
        const AnalysisMove(row: 0, col: 0, player: 1),
        const AnalysisMove(row: 1, col: 1, player: 2),
        const AnalysisMove(row: 0, col: 1, player: 1),
      ];
      final List<List<int>> b = AnalysisEngine.rebuildBoard(moves, 3, 3);
      expect(b[0][0], 1);
      expect(b[1][1], 2);
      expect(b[0][1], 1);
      expect(b[2][2], 0);
    });

    test('luật sliding-cap: gỡ quân cũ TRƯỚC khi đặt quân mới', () {
      // Bàn 3x3: nước thứ 3 của X đẩy quân X đầu tiên ra khỏi bàn.
      final List<AnalysisMove> moves = <AnalysisMove>[
        const AnalysisMove(row: 0, col: 0, player: 1),
        const AnalysisMove(row: 1, col: 1, player: 2),
        const AnalysisMove(
            row: 2, col: 2, player: 1, removedRow: 0, removedCol: 0),
      ];
      final List<List<int>> b = AnalysisEngine.rebuildBoard(moves, 3, 3);
      expect(b[0][0], 0, reason: 'quân cũ phải bị gỡ');
      expect(b[2][2], 1);
      expect(b[1][1], 2);
    });

    test('dựng tới nửa chừng chỉ áp dụng các nước đã xảy ra', () {
      final List<AnalysisMove> moves = <AnalysisMove>[
        const AnalysisMove(row: 0, col: 0, player: 1),
        const AnalysisMove(row: 1, col: 1, player: 2),
      ];
      final List<List<int>> b = AnalysisEngine.rebuildBoard(moves, 3, 1);
      expect(b[0][0], 1);
      expect(b[1][1], 0);
    });
  });

  group('AnalysisScoring', () {
    test('phân loại theo đúng các ngưỡng đã hiệu chuẩn', () {
      MoveQuality q(double loss, {bool best = false, double gap = 0}) =>
          AnalysisScoring.classify(
              loss: loss, matchedBest: best, gapToSecond: gap);

      expect(q(0.0), MoveQuality.good);
      expect(q(0.05), MoveQuality.good);
      expect(q(0.12), MoveQuality.inaccuracy);
      expect(q(0.30), MoveQuality.mistake);
      expect(q(0.60), MoveQuality.blunder);
    });

    test('Xuất sắc chỉ khi trùng nước tốt nhất VÀ là nước duy nhất đúng', () {
      // Không có điều kiện "nước duy nhất", ~70% số nước sẽ thành Xuất sắc.
      expect(
        AnalysisScoring.classify(
            loss: 0.0, matchedBest: true, gapToSecond: 0.30),
        MoveQuality.brilliant,
      );
      expect(
        AnalysisScoring.classify(
            loss: 0.0, matchedBest: true, gapToSecond: 0.01),
        MoveQuality.good,
        reason: 'thế cờ có nhiều nước tốt ngang nhau thì không phải Xuất sắc',
      );
      expect(
        AnalysisScoring.classify(
            loss: 0.0, matchedBest: false, gapToSecond: 0.30),
        MoveQuality.good,
      );
    });

    test('điểm mỗi nước giảm dần và bị chặn dưới ở 0', () {
      expect(AnalysisScoring.moveScore(0.0), 100.0);
      expect(AnalysisScoring.moveScore(0.25), closeTo(50.0, 0.001));
      expect(AnalysisScoring.moveScore(0.5), 0.0);
      expect(AnalysisScoring.moveScore(5.0), 0.0);
    });

    test('độ chính xác bỏ qua các nước khai cuộc', () {
      // 2 nước đầu tệ nhưng bị bỏ qua -> vẫn 100.
      expect(
        AnalysisScoring.accuracy(<double>[0.5, 0.5, 0.0, 0.0]),
        100,
      );
      expect(AnalysisScoring.accuracy(<double>[]), 0);
    });

    test('độ chính xác tất định', () {
      final List<double> l = <double>[0.0, 0.1, 0.2, 0.05, 0.3];
      final int a = AnalysisScoring.accuracy(l);
      expect(AnalysisScoring.accuracy(l), a);
      expect(AnalysisScoring.accuracy(List<double>.from(l)), a);
    });
  });

  group('Lưu trữ', () {
    test('GameAnalysis round-trip JSON', () {
      final GameAnalysis a = GameAnalysis(
        moveAnalyses: <MoveAnalysis>[
          const MoveAnalysis(
            advantageMilli: 250,
            lossMilli: 0,
            quality: MoveQuality.good,
          ),
          const MoveAnalysis(
            advantageMilli: -400,
            lossMilli: 450,
            quality: MoveQuality.blunder,
            betterRow: 7,
            betterCol: 8,
            shallow: true,
          ),
        ],
        scoredIndexes: <int>[0, 1],
        accuracyX: 78,
        accuracyO: 64,
        turningPointIndex: 1,
        isShallow: true,
        analyzedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );

      final GameAnalysis? b =
          GameAnalysis.fromJson(jsonDecode(jsonEncode(a.toJson())));
      expect(b, isNotNull);
      expect(b!.accuracyX, 78);
      expect(b.accuracyO, 64);
      expect(b.turningPointIndex, 1);
      expect(b.isShallow, isTrue);
      expect(b.moveAnalyses.length, 2);
      expect(b.moveAnalyses[1].quality, MoveQuality.blunder);
      expect(b.moveAnalyses[1].betterRow, 7);
      expect(b.moveAnalyses[1].betterCol, 8);
      expect(b.moveAnalyses[1].shallow, isTrue);
      expect(b.analyzedAt, a.analyzedAt);
    });

    test('GameAnalysis sai schema trả null thay vì ném lỗi', () {
      expect(GameAnalysis.fromJson(<String, dynamic>{'v': 999}), isNull);
      expect(GameAnalysis.fromJson(<String, dynamic>{}), isNull);
    });

    test('GameRecord của phiên bản CŨ (không có field analysis) vẫn parse', () {
      // Đây là dữ liệu thật mà người dùng hiện hữu đang có trong máy.
      final Map<String, dynamic> old = <String, dynamic>{
        'id': '123',
        'playedAt': '2026-01-01T10:00:00.000',
        'mode': 1,
        'result': 0,
        'totalMoves': 20,
        'durationSecs': 90,
        'skinName': 'neon',
        'boardSide': 15,
        'winLength': 5,
        'aiDifficultyIndex': 2,
        'moves': <dynamic>[
          <String, dynamic>{'r': 7, 'c': 7, 'p': 1},
        ],
      };
      final GameRecord r = GameRecord.fromJson(old);
      expect(r.analysis, isNull);
      expect(r.hasAnalysis, isFalse);
      expect(r.moves.length, 1);
      expect(r.boardSide, 15);
    });

    test('GameRecord round-trip có kèm analysis', () {
      final GameRecord r = GameRecord(
        id: 'abc',
        playedAt: DateTime(2026, 8, 18, 14, 32),
        mode: GameMode.vsAI,
        result: GameResult.xWins,
        totalMoves: 10,
        durationSecs: 60,
        skinName: 'fire',
        boardSide: 9,
        winLength: 5,
        aiDifficultyIndex: 1,
        moves: const <MoveLog>[MoveLog(row: 1, col: 1, player: 1)],
      ).copyWithAnalysis(GameAnalysis(
        moveAnalyses: const <MoveAnalysis>[
          MoveAnalysis(
              advantageMilli: 0, lossMilli: 0, quality: MoveQuality.good),
        ],
        scoredIndexes: const <int>[0],
        accuracyX: 90,
        accuracyO: 0,
        turningPointIndex: -1,
        isShallow: false,
        analyzedAt: DateTime(2026, 8, 18, 14, 33),
      ));

      final GameRecord back =
          GameRecord.fromJson(jsonDecode(jsonEncode(r.toJson())));
      expect(back.hasAnalysis, isTrue);
      expect(back.analysis!.accuracyX, 90);
      expect(back.skinName, 'fire');
    });

    test('kích thước JSON của 100 ván có phân tích vẫn ở mức an toàn', () {
      // Chặn rủi ro R4: phình dữ liệu SharedPreferences.
      final List<MoveAnalysis> ma = List<MoveAnalysis>.generate(
        40,
        (int i) => MoveAnalysis(
          advantageMilli: i * 7,
          lossMilli: i,
          quality: MoveQuality.values[i % MoveQuality.values.length],
          betterRow: i % 15,
          betterCol: (i * 3) % 15,
        ),
      );
      final GameRecord r = GameRecord(
        id: 'x',
        playedAt: DateTime(2026, 1, 1),
        mode: GameMode.vsAI,
        result: GameResult.xWins,
        totalMoves: 40,
        durationSecs: 200,
        skinName: 'neon',
        boardSide: 15,
        winLength: 5,
        moves: List<MoveLog>.generate(
          40,
          (int i) => MoveLog(row: i % 15, col: (i * 3) % 15, player: i % 2 + 1),
        ),
      ).copyWithAnalysis(GameAnalysis(
        moveAnalyses: ma,
        scoredIndexes: List<int>.generate(20, (int i) => i * 2),
        accuracyX: 80,
        accuracyO: 0,
        turningPointIndex: 14,
        isShallow: false,
        analyzedAt: DateTime(2026, 1, 1),
      ));

      final int bytes = jsonEncode(r.toJson()).length * 100;
      expect(bytes, lessThan(700 * 1024),
          reason: '100 ván phải ở dưới ngưỡng an toàn của SharedPreferences');
    });
  });

  group('Achievements — tương thích ngược', () {
    test('18 badge cũ giữ nguyên thứ tự index', () {
      // Index enum được persist trong AchievementStore. Chèn badge vào giữa sẽ
      // làm hỏng huy hiệu của người dùng hiện hữu.
      const List<String> expected = <String>[
        'firstGame',
        'win10',
        'win50',
        'win100',
        'streak3',
        'streak7',
        'beatAiLow',
        'beatAiMedium',
        'beatAiHigh',
        'played10',
        'played50',
        'fastWin',
        'blitzWin',
        'allBoardSizes',
        'slidingCapWinner',
        'bigBoardWinner',
        'modeVariety',
        'skinExplorer',
      ];
      for (int i = 0; i < expected.length; i++) {
        expect(BadgeId.values[i].name, expected[i],
            reason: 'badge thứ $i bị đổi chỗ');
      }
      expect(BadgeId.perfectGame.index, 18);
      expect(BadgeId.analyst.index, 19);
    });

    test('mọi badge đều có định nghĩa trong catalog', () {
      for (final BadgeId id in BadgeId.values) {
        expect(() => BadgeCatalog.def(id), returnsNormally);
      }
    });
  });

  group('formatCellCoord', () {
    test('theo quy ước cờ vua: cột chữ, hàng số từ 1', () {
      expect(formatCellCoord(7, 7), 'H8');
      expect(formatCellCoord(0, 0), 'A1');
      expect(formatCellCoord(14, 14), 'O15');
      expect(formatCellCoord(-1, 0), '—');
    });
  });
}
