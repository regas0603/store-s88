import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:main_app_package/src/game/engine/guess_engine.dart';
import 'package:main_app_package/src/game/models/game_config.dart';
import 'package:main_app_package/src/game/models/guess.dart';

GuessEngine buildEngine({
  int min = 1,
  int max = 100,
  int maxGuesses = 12,
  int playerCount = 1,
  bool showHeat = true,
  int seed = 7,
}) {
  return GuessEngine(
    min: min,
    max: max,
    maxGuesses: maxGuesses,
    playerCount: playerCount,
    showHeat: showHeat,
    random: Random(seed),
  );
}

void main() {
  group('gợi ý cao hơn / thấp hơn', () {
    test('đoán thấp hơn số bí mật thì được bảo đoán cao lên', () {
      final engine = buildEngine()..setSecretFor(0, 42);

      expect(engine.submit(10), GuessOutcome.wrong);
      expect(engine.currentRound.lastGuess!.hint, GuessHint.higher);
    });

    test('đoán cao hơn số bí mật thì được bảo đoán thấp xuống', () {
      final engine = buildEngine()..setSecretFor(0, 42);

      expect(engine.submit(90), GuessOutcome.wrong);
      expect(engine.currentRound.lastGuess!.hint, GuessHint.lower);
    });

    test('đoán trúng thì kết thúc lượt', () {
      final engine = buildEngine()..setSecretFor(0, 42);

      expect(engine.submit(42), GuessOutcome.correct);
      expect(engine.currentRound.solved, isTrue);
      expect(engine.isFinished, isTrue);
      // Lượt đã xong thì không nhận thêm số nào nữa.
      expect(engine.submit(43), GuessOutcome.rejected);
    });
  });

  group('khoảng còn khả dĩ', () {
    test('thu hẹp dần theo từng gợi ý', () {
      final engine = buildEngine()..setSecretFor(0, 42);

      engine.submit(10);
      expect(engine.currentRound.lowBound, 11);
      expect(engine.currentRound.highBound, 100);

      engine.submit(70);
      expect(engine.currentRound.lowBound, 11);
      expect(engine.currentRound.highBound, 69);

      engine.submit(40);
      expect(engine.currentRound.lowBound, 41);
      expect(engine.currentRound.highBound, 69);
    });

    test('một lần đoán tệ hơn không nới rộng khoảng đã biết', () {
      final engine = buildEngine()..setSecretFor(0, 42);

      engine.submit(40); // cao hơn 40
      engine.submit(5); // vẫn cao hơn 5, nhưng 41 mới là cận dưới đúng
      expect(engine.currentRound.lowBound, 41);
    });
  });

  group('lượt đoán bị trừ đúng lúc', () {
    test('số ngoài khoảng không tốn lượt', () {
      final engine = buildEngine()..setSecretFor(0, 42);

      expect(engine.submit(500), GuessOutcome.outOfRange);
      expect(engine.submit(0), GuessOutcome.outOfRange);
      expect(engine.currentRound.guessesUsed, 0);
    });

    test('đoán lại số cũ không tốn lượt', () {
      final engine = buildEngine()..setSecretFor(0, 42);

      engine.submit(10);
      expect(engine.submit(10), GuessOutcome.duplicate);
      expect(engine.currentRound.guessesUsed, 1);
    });

    test('hết lượt thì báo exhausted và khoá lượt', () {
      final engine = buildEngine(maxGuesses: 3)..setSecretFor(0, 42);

      expect(engine.submit(1), GuessOutcome.wrong);
      expect(engine.submit(2), GuessOutcome.wrong);
      expect(engine.submit(3), GuessOutcome.exhausted);
      expect(engine.currentRound.exhausted, isTrue);
      expect(engine.currentRound.solved, isFalse);
      expect(engine.submit(42), GuessOutcome.rejected);
    });
  });

  group('gợi ý nóng/lạnh', () {
    test('càng gần càng nóng', () {
      final engine = buildEngine()..setSecretFor(0, 50);

      engine.submit(51);
      expect(engine.currentRound.history.last.heat, GuessHeat.hot);
      engine.submit(45);
      expect(engine.currentRound.history.last.heat, GuessHeat.warm);
      engine.submit(70);
      expect(engine.currentRound.history.last.heat, GuessHeat.cold);
      engine.submit(99);
      expect(engine.currentRound.history.last.heat, GuessHeat.freezing);
    });

    test('mức Khó tắt hẳn nóng/lạnh', () {
      final engine = buildEngine(showHeat: false)..setSecretFor(0, 50);

      engine.submit(51);
      expect(engine.currentRound.history.last.heat, GuessHeat.none);
    });
  });

  group('máy bốc số', () {
    test('số bốc ra luôn nằm trong khoảng', () {
      for (var seed = 0; seed < 50; seed++) {
        final engine = buildEngine(min: 1, max: 10, seed: seed)
          ..rollSecretFor(0);
        final secret = engine.currentRound.secret!;
        expect(secret, inInclusiveRange(1, 10));
      }
    });

    test('không nhận số bí mật ngoài khoảng', () {
      final engine = buildEngine(min: 1, max: 100);
      expect(engine.setSecretFor(0, 101), isFalse);
      expect(engine.currentRound.hasSecret, isFalse);
    });
  });

  group('chế độ 2 người', () {
    test('ai ít lượt hơn thì thắng', () {
      final engine = buildEngine(playerCount: 2)
        ..setSecretFor(0, 30)
        ..setSecretFor(1, 70);

      // Người 2 (index 1) đoán trước, mất 2 lượt.
      engine.moveToPlayer(1);
      engine.submit(50);
      engine.submit(70);

      // Người 1 (index 0) đoán sau, mất 3 lượt.
      engine.moveToPlayer(0);
      engine.submit(50);
      engine.submit(20);
      engine.submit(30);

      expect(engine.isFinished, isTrue);
      expect(engine.winners, <int>[1]);
    });

    test('cùng số lượt thì người nhanh hơn thắng', () {
      final engine = buildEngine(playerCount: 2)
        ..setSecretFor(0, 30)
        ..setSecretFor(1, 70);

      engine.moveToPlayer(1);
      engine.submit(70);
      engine.roundOf(1).elapsed = const Duration(seconds: 9);

      engine.moveToPlayer(0);
      engine.submit(30);
      engine.roundOf(0).elapsed = const Duration(seconds: 4);

      expect(engine.winners, <int>[0]);
    });

    test('đoán ra luôn thắng người hết lượt', () {
      final engine = buildEngine(playerCount: 2, maxGuesses: 2)
        ..setSecretFor(0, 30)
        ..setSecretFor(1, 70);

      engine.moveToPlayer(1);
      engine.submit(1);
      engine.submit(2);

      engine.moveToPlayer(0);
      engine.submit(30);

      expect(engine.winners, <int>[0]);
    });

    test('cả hai cùng bí thì hoà', () {
      final engine = buildEngine(playerCount: 2, maxGuesses: 1)
        ..setSecretFor(0, 30)
        ..setSecretFor(1, 70);

      engine.moveToPlayer(1);
      engine.submit(1);
      engine.moveToPlayer(0);
      engine.submit(2);

      expect(engine.winners, <int>[0, 1]);
    });
  });

  group('số lượt cho phép đủ để chia đôi', () {
    test('mọi khoảng × độ khó đều giải được bằng chiến thuật chia đôi', () {
      for (final range in GuessRange.values) {
        for (final difficulty in GuessDifficulty.values) {
          final budget = difficulty.maxGuessesFor(range);
          // Trường hợp tệ nhất của chia đôi là ceil(log2(span)).
          var worstCase = 0;
          var remaining = range.span;
          while (remaining > 1) {
            remaining = (remaining + 1) ~/ 2;
            worstCase++;
          }
          expect(
            budget,
            greaterThanOrEqualTo(worstCase),
            reason: '${range.name}/${difficulty.name}: '
                'cho $budget lượt nhưng cần tới $worstCase',
          );
        }
      }
    });

    test('minHalvingGuesses khớp trường hợp tệ nhất của chia đôi', () {
      for (final range in GuessRange.values) {
        var worstCase = 0;
        var remaining = range.span;
        while (remaining > 1) {
          remaining = (remaining + 1) ~/ 2;
          worstCase++;
        }
        expect(
          range.minHalvingGuesses,
          worstCase,
          reason: range.name,
        );
      }
    });
  });

  group('sinh tồn: ngân sách lượt theo vòng', () {
    test('vòng 1 bằng đúng ngân sách của độ khó', () {
      for (final range in GuessRange.values) {
        for (final difficulty in GuessDifficulty.values) {
          final config = GameConfig(
            mode: GameMode.survival,
            range: range,
            difficulty: difficulty,
          );
          expect(
            config.survivalGuessesFor(1),
            difficulty.maxGuessesFor(range),
            reason: '${range.name}/${difficulty.name}',
          );
        }
      }
    });

    test('mỗi vòng bớt đúng một lượt cho tới khi chạm sàn', () {
      const config = GameConfig(
        mode: GameMode.survival,
        range: GuessRange.small, // 1–100: thường 12 lượt, sàn 7
        difficulty: GuessDifficulty.normal,
      );

      expect(config.survivalGuessesFor(1), 12);
      expect(config.survivalGuessesFor(2), 11);
      expect(config.survivalGuessesFor(5), 8);
      expect(config.survivalGuessesFor(6), 7);
    });

    test('không bao giờ xuống dưới sàn chia đôi, dù chơi tới vòng nào', () {
      for (final range in GuessRange.values) {
        for (final difficulty in GuessDifficulty.values) {
          final config = GameConfig(
            mode: GameMode.survival,
            range: range,
            difficulty: difficulty,
          );
          for (final round in <int>[1, 10, 100, 1000]) {
            expect(
              config.survivalGuessesFor(round),
              greaterThanOrEqualTo(range.minHalvingGuesses),
              reason: '${range.name}/${difficulty.name} vòng $round',
            );
          }
        }
      }
    });

    test('survivalFloorRound là vòng đầu tiên chạm sàn', () {
      for (final range in GuessRange.values) {
        for (final difficulty in GuessDifficulty.values) {
          final config = GameConfig(
            mode: GameMode.survival,
            range: range,
            difficulty: difficulty,
          );
          final floor = config.survivalFloorRound;
          expect(
            config.survivalGuessesFor(floor),
            range.minHalvingGuesses,
            reason: '${range.name}/${difficulty.name}: vòng $floor',
          );
          if (floor > 1) {
            expect(
              config.survivalGuessesFor(floor - 1),
              greaterThan(range.minHalvingGuesses),
              reason: '${range.name}/${difficulty.name}: vòng ${floor - 1}',
            );
          }
        }
      }
    });

    test('sinh tồn chỉ có một người chơi', () {
      expect(GameMode.survival.playerCount, 1);
      expect(GameMode.survival.isDuel, isFalse);
      expect(GameMode.survival.isSurvival, isTrue);
    });

    test('kỷ lục sinh tồn không dùng chung khoá với chơi đơn', () {
      const survival = GameConfig(mode: GameMode.survival);
      const solo = GameConfig(mode: GameMode.solo);
      expect(survival.recordKey, isNot(solo.recordKey));
    });
  });
}
