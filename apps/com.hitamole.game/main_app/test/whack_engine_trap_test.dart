import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:main_app_package/src/game/engine/ai_player.dart';
import 'package:main_app_package/src/game/engine/whack_engine.dart';
import 'package:main_app_package/src/game/models/game_config.dart';
import 'package:main_app_package/src/game/models/mole_hole.dart';

/// Random luôn trả về cùng một giá trị — ép engine ra bom (0.0) hoặc chuột (0.99).
class _FixedRandom implements Random {
  final double value;
  _FixedRandom(this.value);

  @override
  double nextDouble() => value;
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
}

WhackEngine _engine({required double trapChance, required double roll}) {
  return WhackEngine(
    holeCount: 9,
    rules: WhackRules(
      moleCount: 3,
      untilHits: true,
      maxActive: 1,
      upTime: const Duration(seconds: 1),
      trapChance: trapChance,
    ),
    random: _FixedRandom(roll),
  )..beginRound(Duration.zero);
}

/// Tick tới khi có thứ trồi lên, trả về hang đó.
MoleHole _popNext(WhackEngine engine, Duration from) {
  for (var t = from;
      t < from + const Duration(seconds: 5);
      t += const Duration(milliseconds: 40)) {
    final popped = engine.tick(t).popped;
    if (popped.isNotEmpty) return engine.holes[popped.first];
  }
  fail('Không có gì trồi lên');
}

void main() {
  test('Mức thường không bao giờ có bom', () {
    final engine = _engine(trapChance: 0, roll: 0);
    expect(_popNext(engine, Duration.zero).isTrap, isFalse);
  });

  test('Đập bom được tính là trap, điểm không bao giờ âm', () {
    final engine = _engine(trapChance: 0.25, roll: 0.99);
    const now = Duration(seconds: 1);

    // Đập trúng một chuột thật trước để có điểm mà trừ.
    final mole = _popNext(engine, Duration.zero);
    expect(mole.isTrap, isFalse);
    expect(engine.whack(mole.index, player: 0, now: now), WhackOutcome.hit);
    expect(engine.scores.first, 1);
    expect(engine.molesLeft, 2);

    // Ép con tiếp theo là bom.
    final trapEngine = _engine(trapChance: 0.25, roll: 0);
    final trap = _popNext(trapEngine, Duration.zero);
    expect(trap.isTrap, isTrue);
    expect(
        trapEngine.whack(trap.index, player: 0, now: now), WhackOutcome.trap);
    expect(trapEngine.trapsHit, 1);
    expect(trapEngine.taps, 1);
    // Chưa có điểm thì không bị âm.
    expect(trapEngine.scores.first, 0);
    expect(trapEngine.molesLeft, 3);
  });

  test('Trừ điểm làm tăng lại số con còn lại', () {
    final engine = _engine(trapChance: 0.25, roll: 0.99);
    final mole = _popNext(engine, Duration.zero);
    engine.whack(mole.index, player: 0, now: const Duration(seconds: 1));
    expect(engine.molesLeft, 2);

    // Biến tay một hang thành bom đang trồi để kiểm tra phép trừ.
    final hole = engine.holes[5]
      ..state = HoleState.up
      ..isTrap = true
      ..hideAt = const Duration(seconds: 10);
    expect(
      engine.whack(hole.index, player: 0, now: const Duration(seconds: 2)),
      WhackOutcome.trap,
    );
    expect(engine.scores.first, 0);
    expect(engine.molesLeft, 3);
    expect(engine.roundOver, isFalse);
  });

  test('Bom tự thụt xuống không tính là chuột chạy thoát', () {
    final engine = _engine(trapChance: 0.25, roll: 0);
    final trap = _popNext(engine, Duration.zero);
    expect(trap.isTrap, isTrue);

    final result = engine.tick(trap.hideAt);
    expect(result.escaped, isEmpty);
    expect(engine.molesLeft, 3);
  });

  test('Bom không chiếm chỗ của chuột chũi', () {
    final engine = _engine(trapChance: 0.25, roll: 0);
    expect(_popNext(engine, Duration.zero).isTrap, isTrue);
    expect(engine.activeCount, 0);
  });

  test('Kỷ lục chơi đơn mức khó tách riêng, mức thường giữ khoá cũ', () {
    const normal = GameConfig(mode: GameMode.solo, boardSize: BoardSize.small);
    final hard = normal.copyWith(boardDifficulty: BoardDifficulty.hard);
    expect(normal.recordKey, 'solo_small');
    expect(hard.recordKey, 'solo_small_hard');
  });

  test('Mức khó bật bom cho cả ba chế độ', () {
    for (final mode in GameMode.values) {
      final config =
          GameConfig(mode: mode, boardDifficulty: BoardDifficulty.hard);
      expect(config.hasTraps, isTrue, reason: mode.name);
      expect(config.copyWith(boardDifficulty: BoardDifficulty.normal).hasTraps,
          isFalse,
          reason: mode.name);
    }
  });

  group('Chế độ đấu', () {
    WhackEngine versus({required double roll, bool takesTurns = false}) {
      return WhackEngine(
        holeCount: 9,
        playerCount: 2,
        takesTurns: takesTurns,
        rules: const WhackRules(
          moleCount: 2,
          untilHits: false,
          maxActive: 1,
          upTime: Duration(seconds: 1),
          trapChance: 0.25,
        ),
        random: _FixedRandom(roll),
      )..beginRound(Duration.zero);
    }

    MoleHole plantTrap(WhackEngine engine, int index) => engine.holes[index]
      ..state = HoleState.up
      ..isTrap = true
      ..moleId = 999
      ..hideAt = const Duration(seconds: 10);

    test('Chỉ người đập nhầm bị trừ điểm', () {
      final engine = versus(roll: 0.99);
      final mole = _popNext(engine, Duration.zero);
      engine.whack(mole.index, player: 1, now: const Duration(seconds: 1));
      expect(engine.scores, <int>[0, 1]);

      plantTrap(engine, 7);
      expect(
        engine.whack(7, player: 1, now: const Duration(seconds: 2)),
        WhackOutcome.trap,
      );
      expect(engine.scores, <int>[0, 0]);
      expect(engine.trapsHitBy, <int>[0, 1]);
      // Số chuột còn lại của lượt không đổi — bom không phải chuột.
      expect(engine.molesLeft, 1);
    });

    test('Bom còn trên bàn không giữ lượt lại', () {
      final engine = versus(roll: 0.99);
      var now = Duration.zero;
      // Nhịp tick đầu tiên của _popNext cũng cho con trước chạy thoát.
      for (var i = 0; i < 2; i++) {
        now = _popNext(engine, now).hideAt;
      }
      engine.tick(now); // con cuối chạy thoát
      plantTrap(engine, 8);
      expect(engine.roundOver, isTrue);
    });
  });

  group('AI và bom', () {
    MoleHole trapHole() => MoleHole(
          index: 3,
          state: HoleState.up,
          moleId: 42,
          isTrap: true,
          hideAt: const Duration(seconds: 10),
        );

    test('AI lỡ tay khi xác suất rơi dưới ngưỡng', () {
      final ai =
          AiPlayer(difficulty: AiDifficulty.easy, random: _FixedRandom(0));
      final hole = trapHole();
      ai.onTrapPopped(hole, Duration.zero);
      expect(ai.pendingCount, 1);
      expect(
          ai.dueWhacks(
              <MoleHole>[for (var i = 0; i < 3; i++) MoleHole(index: i), hole],
              const Duration(seconds: 2)),
          <int>[3]);
    });

    test('AI né bom khi xác suất vượt ngưỡng', () {
      final ai =
          AiPlayer(difficulty: AiDifficulty.hard, random: _FixedRandom(0.5));
      ai.onTrapPopped(trapHole(), Duration.zero);
      expect(ai.pendingCount, 0);
    });
  });
}
