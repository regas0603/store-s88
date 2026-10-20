import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:main_app_package/src/data/stats_repository.dart';
import 'package:main_app_package/src/game/game_controller.dart';
import 'package:main_app_package/src/game/models/game_config.dart';
import 'package:main_app_package/src/services/sound_service.dart';

/// Controller chưa gọi `sound.init()` nên mọi `play()` tự no-op, và
/// `StatsRepository` chưa `load()` nên không chạm tới shared_preferences —
/// vừa đúng cho test luật chơi.
GameController buildController({
  GuessRange range = GuessRange.small,
  GuessDifficulty difficulty = GuessDifficulty.normal,
  int seed = 11,
}) {
  final controller = GameController(
    config: GameConfig(
      mode: GameMode.survival,
      range: range,
      difficulty: difficulty,
    ),
    sound: SoundService(),
    stats: StatsRepository(),
    random: Random(seed),
  );
  addTearDown(controller.dispose);
  return controller;
}

/// Chơi hết vòng hiện tại bằng chia đôi. Trả về số lượt đã dùng.
int solveCurrentRound(GameController controller) {
  var guesses = 0;
  while (controller.phase == GamePhase.playing) {
    final mid = controller.lowBound +
        ((controller.highBound - controller.lowBound) ~/ 2);
    controller.submitGuess(mid);
    guesses++;
    if (guesses > 64) fail('Chia đôi không bao giờ cần tới 64 lượt');
  }
  return guesses;
}

/// Đốt sạch lượt mà KHÔNG đoán trúng.
///
/// Đọc trộm số bí mật để chắc chắn trượt — chỉ test mới làm được chuyện này.
/// Mỗi lần đoán một cận chỉ thu hẹp khoảng đúng 1 đơn vị, nên với ngân sách
/// lượt hiện tại khoảng không bao giờ co lại còn mỗi số bí mật.
void burnAllGuesses(GameController controller) {
  var safety = 0;
  while (controller.phase == GamePhase.playing) {
    final secret = controller.round.secret;
    final value = controller.lowBound == secret
        ? controller.highBound
        : controller.lowBound;
    if (value == secret) {
      fail('Khoảng còn lại chỉ còn số bí mật — không đoán trượt được nữa');
    }
    controller.submitGuess(value);
    if (++safety > 64) fail('Không đốt hết được lượt');
  }
}

void main() {
  group('sinh tồn: chuỗi vòng', () {
    test('đoán ra thì sang nhịp nghỉ chứ không kết thúc ván', () {
      final controller = buildController()..start();

      expect(controller.survivalRound, 1);
      solveCurrentRound(controller);

      expect(controller.phase, GamePhase.roundCleared);
      expect(controller.survivedRounds, 1);
      expect(controller.result, isNull);
    });

    test('qua nhịp nghỉ là vào vòng mới, ngân sách bớt một lượt', () {
      final controller = buildController()..start();
      final budgetRound1 = controller.guessBudget;

      solveCurrentRound(controller);
      controller.skipRoundBreak();

      expect(controller.phase, GamePhase.playing);
      expect(controller.survivalRound, 2);
      expect(controller.guessBudget, budgetRound1 - 1);
      // Vòng mới là ván sạch: lịch sử rỗng, khoảng còn lại mở hết.
      expect(controller.history, isEmpty);
      expect(controller.lowBound, GuessRange.small.min);
      expect(controller.highBound, GuessRange.small.max);
    });

    test('hết lượt là dừng, chuỗi tính bằng số vòng ĐÃ qua', () {
      final controller = buildController()..start();

      solveCurrentRound(controller);
      controller.skipRoundBreak();
      solveCurrentRound(controller);
      controller.skipRoundBreak();

      expect(controller.survivalRound, 3);
      burnAllGuesses(controller);

      expect(controller.phase, GamePhase.finished);
      final result = controller.result;
      expect(result, isNotNull);
      // Vòng 3 là vòng thua nên không được tính vào chuỗi.
      expect(result!.survivedRounds, 2);
      expect(controller.survivedRounds, 2);
    });

    test('thua ngay vòng đầu thì chuỗi bằng 0', () {
      final controller = buildController()..start();
      burnAllGuesses(controller);

      expect(controller.phase, GamePhase.finished);
      expect(controller.result!.survivedRounds, 0);
    });

    test('ngân sách đi xuống tới sàn rồi đứng yên', () {
      const config = GameConfig(
        mode: GameMode.survival,
        range: GuessRange.small,
        difficulty: GuessDifficulty.normal,
      );
      final floorRound = config.survivalFloorRound;

      final controller = buildController()..start();
      // Chơi qua đúng số vòng để chạm sàn.
      for (var i = 1; i < floorRound; i++) {
        solveCurrentRound(controller);
        controller.skipRoundBreak();
      }

      expect(controller.survivalRound, floorRound);
      expect(controller.guessBudget, GuessRange.small.minHalvingGuesses);

      // Thêm một vòng nữa: ngân sách KHÔNG được giảm tiếp.
      solveCurrentRound(controller);
      controller.skipRoundBreak();
      expect(controller.survivalRound, floorRound + 1);
      expect(controller.guessBudget, GuessRange.small.minHalvingGuesses);
    });

    test('chia đôi luôn qua được vòng, kể cả khi ngân sách đã chạm sàn', () {
      for (final range in GuessRange.values) {
        for (final difficulty in GuessDifficulty.values) {
          final controller = buildController(
            range: range,
            difficulty: difficulty,
            seed: range.index * 10 + difficulty.index,
          )..start();

          // Chơi quá điểm chạm sàn vài vòng — tới đây mỗi vòng đều là bài
          // kiểm tra chia đôi hoàn hảo.
          final rounds = GameConfig(
                mode: GameMode.survival,
                range: range,
                difficulty: difficulty,
              ).survivalFloorRound +
              3;

          for (var i = 0; i < rounds; i++) {
            solveCurrentRound(controller);
            expect(
              controller.phase,
              GamePhase.roundCleared,
              reason: '${range.name}/${difficulty.name}: '
                  'chia đôi trượt ở vòng ${controller.survivalRound}',
            );
            controller.skipRoundBreak();
          }

          expect(controller.survivedRounds, rounds);
        }
      }
    });

    test('chơi lại đặt chuỗi và vòng về mốc ban đầu', () {
      final controller = buildController()..start();

      solveCurrentRound(controller);
      controller.skipRoundBreak();
      expect(controller.survivalRound, 2);

      controller.restart();

      expect(controller.survivalRound, 1);
      expect(controller.survivedRounds, 0);
      expect(controller.guessBudget, GuessRange.small.normalGuesses);
      expect(controller.phase, GamePhase.playing);
    });

    test('tạm dừng giữa nhịp nghỉ rồi tiếp tục vẫn giữ nhịp nghỉ', () {
      final controller = buildController()..start();

      solveCurrentRound(controller);
      expect(controller.phase, GamePhase.roundCleared);

      controller.pause();
      expect(controller.phase, GamePhase.paused);

      controller.resume();
      expect(controller.phase, GamePhase.roundCleared);
      expect(controller.survivalRound, 1);
    });
  });

  group('sinh tồn: thành tích', () {
    test('ghi kỷ lục chuỗi, không đụng kỷ lục chơi đơn', () async {
      final stats = StatsRepository();
      const key = 'survival_small_normal';

      expect(await stats.submitSurvival(recordKey: key, streak: 3), isTrue);
      expect(stats.recordFor(key).bestStreak, 3);
      expect(stats.recordFor(key).bestGuesses, isNull);

      // Chuỗi ngắn hơn không ghi đè.
      expect(await stats.submitSurvival(recordKey: key, streak: 1), isFalse);
      expect(stats.recordFor(key).bestStreak, 3);

      expect(await stats.submitSurvival(recordKey: key, streak: 7), isTrue);
      expect(stats.recordFor(key).bestStreak, 7);
    });

    test('một ván sinh tồn tính là một ván, không phải mỗi vòng một ván',
        () async {
      final stats = StatsRepository();
      await stats.submitSurvival(recordKey: 'k', streak: 5);

      expect(stats.gamesPlayed, 1);
      expect(stats.solved, 1);
    });

    test('chuỗi 0 vòng tính là ván không đoán ra', () async {
      final stats = StatsRepository();
      await stats.submitSurvival(recordKey: 'k', streak: 0);

      expect(stats.gamesPlayed, 1);
      expect(stats.solved, 0);
      expect(stats.unsolved, 1);
    });

    test('ghi chuỗi rồi ghi kỷ lục chơi đơn thì cả hai cùng còn', () async {
      final stats = StatsRepository();
      const key = 'k';

      await stats.submitSurvival(recordKey: key, streak: 4);
      await stats.submitSolo(recordKey: key, elapsedMs: 9000, guesses: 6);

      expect(stats.recordFor(key).bestStreak, 4);
      expect(stats.recordFor(key).bestGuesses, 6);
      expect(stats.recordFor(key).bestTimeMs, 9000);
    });
  });
}
