import 'dart:math';

import '../models/card_icon.dart';
import '../models/mole_hole.dart';

/// Kết quả một cú đập.
enum WhackOutcome {
  /// Không tính: ngoài phạm vi, hoặc đập vào con đã bị đập rồi.
  rejected,

  /// Trúng.
  hit,

  /// Đập vào hang trống.
  miss,

  /// Đập nhầm bom bẫy — bị trừ điểm.
  trap,
}

/// Những gì vừa xảy ra trong một nhịp [WhackEngine.tick].
class TickResult {
  /// Hang vừa có con trồi lên.
  final List<int> popped;

  /// Hang có con vừa chạy thoát (không ai đập kịp).
  final List<int> escaped;

  const TickResult({required this.popped, required this.escaped});

  static const TickResult none = TickResult(popped: <int>[], escaped: <int>[]);
}

/// Nhịp độ của một lượt chơi.
class WhackRules {
  /// [untilHits] = true: số con phải đập trúng. Ngược lại: số con trồi lên.
  final int moleCount;

  /// true: lượt kết thúc khi đập trúng đủ [moleCount] con (chơi đơn).
  /// false: lượt kết thúc khi đủ [moleCount] con đã trồi lên và rút đi.
  final bool untilHits;

  /// Số chuột chũi tối đa cùng ló đầu. Bom không tính vào đây.
  final int maxActive;
  final Duration upTime;
  final Duration spawnGap;

  /// Xác suất mỗi lần trồi lên là bom thay vì chuột chũi. 0 = không có bom.
  final double trapChance;

  /// Số điểm bị trừ khi đập nhầm bom.
  final int trapPenalty;

  const WhackRules({
    required this.moleCount,
    required this.untilHits,
    required this.maxActive,
    required this.upTime,
    this.spawnGap = const Duration(milliseconds: 620),
    this.trapChance = 0,
    this.trapPenalty = 1,
  }) : assert(
            trapChance >= 0 && trapChance < 1, 'trapChance phải trong [0, 1)');
}

/// Luật chơi thuần Dart — không import Flutter, không timer.
///
/// Thời gian được truyền vào từ ngoài ([tick], [whack]) thay vì tự đọc đồng
/// hồ, nên toàn bộ luật test được bằng những mốc thời gian giả, và tạm dừng
/// chỉ đơn giản là ngừng gọi [tick].
class WhackEngine {
  /// Hang vừa rút về được nghỉ bao lâu trước khi có con mới trồi lên.
  static const Duration holeCooldown = Duration(milliseconds: 320);

  /// Con bị đập nằm choáng bao lâu trước khi thụt xuống.
  static const Duration hitLinger = Duration(milliseconds: 380);

  /// Về cuối lượt, thời gian ở trên mặt đất rút ngắn tối đa bao nhiêu.
  static const double maxSpeedUp = 0.3;

  /// Bom nằm lâu hơn chuột chũi một chút: nó là chướng ngại cần né, không
  /// phải mục tiêu cần đuổi.
  static const double trapLinger = 1.25;

  /// Số bom tối đa cùng lúc trên bàn. Nhiều hơn thì bàn nhỏ thành bãi mìn.
  static const int maxTraps = 1;

  final List<MoleHole> holes;
  final int playerCount;
  final WhackRules rules;

  /// Người chơi có lần lượt thay nhau không (2 người chung máy).
  final bool takesTurns;

  /// Nhân vật có thể trồi lên. Danh sách rỗng = chuột chũi cổ điển.
  final List<CardIcon> characters;

  final Random _random;
  final List<int> _scores;
  final List<int> _trapsHit;

  int _currentPlayer = 0;
  int _taps = 0;
  int _misses = 0;
  int _spawned = 0;
  int _hits = 0;
  int _resolved = 0;
  int _nextMoleId = 1;
  int _lastHole = -1;
  Duration _nextSpawnAt = Duration.zero;

  WhackEngine({
    required int holeCount,
    required this.rules,
    this.playerCount = 1,
    this.takesTurns = false,
    this.characters = const <CardIcon>[],
    Random? random,
  })  : assert(holeCount > 0, 'Cần ít nhất một hang'),
        assert(playerCount >= 1, 'Cần ít nhất một người chơi'),
        holes = <MoleHole>[
          for (var i = 0; i < holeCount; i++) MoleHole(index: i),
        ],
        _random = random ?? Random(),
        _scores = List<int>.filled(playerCount, 0),
        _trapsHit = List<int>.filled(playerCount, 0);

  List<int> get scores => List<int>.unmodifiable(_scores);

  /// Người đang tới lượt (chỉ có ý nghĩa khi [takesTurns]).
  int get currentPlayer => _currentPlayer;

  /// Tổng số cú đập (trúng + hụt).
  int get taps => _taps;

  int get misses => _misses;

  /// Số lần đập nhầm bom của từng người chơi.
  List<int> get trapsHitBy => List<int>.unmodifiable(_trapsHit);

  /// Tổng số lần đập nhầm bom của mọi người chơi.
  int get trapsHit => _trapsHit.fold(0, (sum, n) => sum + n);

  /// Số chuột chũi đang chờ bị đập (không tính bom).
  int get activeCount => holes.where((h) => h.hasMoleUp).length;

  int get _activeTraps => holes.where((h) => h.isUp && h.isTrap).length;

  /// Số con còn lại của lượt hiện tại.
  int get molesLeft => rules.untilHits
      ? max(0, rules.moleCount - _hits)
      : max(0, rules.moleCount - _resolved);

  bool get roundOver => rules.untilHits
      ? _hits >= rules.moleCount
      : _spawned >= rules.moleCount &&
          holes.every((h) => !h.isRaised || h.isTrap);

  bool get isFinished =>
      roundOver && (!takesTurns || _currentPlayer >= playerCount - 1);

  /// Danh sách người chơi có điểm cao nhất. Nhiều hơn một phần tử = hoà.
  List<int> get winners {
    final best = _scores.reduce(max);
    return <int>[
      for (var i = 0; i < _scores.length; i++)
        if (_scores[i] == best) i,
    ];
  }

  bool get _canSpawn =>
      rules.untilHits ? _hits < rules.moleCount : _spawned < rules.moleCount;

  /// Tiến độ lượt 0..1 — dùng để tăng tốc dần.
  double get _progress {
    if (rules.moleCount <= 0) return 1;
    final done = rules.untilHits ? _hits : _spawned;
    return (done / rules.moleCount).clamp(0.0, 1.0);
  }

  /// Chuẩn bị một lượt mới bắt đầu từ mốc [now].
  void beginRound(Duration now) {
    clearHoles(now);
    _spawned = 0;
    _hits = 0;
    _resolved = 0;
    _lastHole = -1;
    _nextSpawnAt = now + const Duration(milliseconds: 350);
  }

  /// Chuyển sang người chơi kế tiếp (2 người chung máy).
  void nextTurn(Duration now) {
    if (!takesTurns) return;
    _currentPlayer = (_currentPlayer + 1) % playerCount;
    beginRound(now);
  }

  /// Cho mọi con thụt xuống ngay, không tính là chạy thoát.
  void clearHoles(Duration now) {
    for (final hole in holes) {
      hole
        ..state = HoleState.empty
        ..hitBy = null
        ..clearAt = now;
    }
  }

  /// Tiến thời gian tới [now]: con hết giờ thì chạy thoát, hang trống thì có
  /// thể có con mới trồi lên.
  TickResult tick(Duration now) {
    final popped = <int>[];
    final escaped = <int>[];

    for (final hole in holes) {
      if (hole.state == HoleState.up && now >= hole.hideAt) {
        hole
          ..state = HoleState.empty
          ..clearAt = now + holeCooldown;
        // Bom tự thụt xuống là người chơi né thành công — không phải chuột
        // chạy thoát, và cũng không tính vào số con của lượt.
        if (!hole.isTrap) {
          _resolved++;
          escaped.add(hole.index);
        }
      } else if (hole.state == HoleState.hit && now >= hole.clearAt) {
        hole
          ..state = HoleState.empty
          ..clearAt = now + holeCooldown;
      }
    }

    if (_canSpawn && activeCount < rules.maxActive && now >= _nextSpawnAt) {
      final index = _pickHole(now);
      if (index != null) {
        if (_shouldSpawnTrap()) {
          _spawnTrap(holes[index], now);
        } else {
          _spawn(holes[index], now);
        }
        popped.add(index);
        _nextSpawnAt = now + _jitter(rules.spawnGap, 0.4);
      }
    }

    if (popped.isEmpty && escaped.isEmpty) return TickResult.none;
    return TickResult(popped: popped, escaped: escaped);
  }

  /// Người chơi [player] đập vào hang [index] ở mốc [now].
  WhackOutcome whack(int index, {required int player, required Duration now}) {
    if (index < 0 || index >= holes.length) return WhackOutcome.rejected;
    if (player < 0 || player >= playerCount) return WhackOutcome.rejected;

    final hole = holes[index];
    switch (hole.state) {
      case HoleState.hit:
        // Đập thêm vào con đang choáng: không thưởng, cũng không phạt.
        return WhackOutcome.rejected;
      case HoleState.up:
        hole
          ..state = HoleState.hit
          ..hitBy = player
          ..clearAt = now + hitLinger;
        _taps++;
        if (hole.isTrap) {
          // Chế độ đấu: trừ thẳng vào điểm của người đập nhầm.
          // Chơi đơn: điểm chính là số con đã đập, nên trừ điểm = phải đập
          // thêm con nữa mới xong — phạt bằng thời gian, đúng thứ được tính
          // kỷ lục. Không cho âm để bộ đếm "còn lại" không vượt quá ban đầu.
          final penalty = min(rules.trapPenalty, _scores[player]);
          _scores[player] -= penalty;
          if (rules.untilHits) _hits = max(0, _hits - penalty);
          _trapsHit[player]++;
          return WhackOutcome.trap;
        }
        _scores[player]++;
        _hits++;
        _resolved++;
        return WhackOutcome.hit;
      case HoleState.empty:
        _misses++;
        _taps++;
        return WhackOutcome.miss;
    }
  }

  int? _pickHole(Duration now) {
    final free = <int>[
      for (final hole in holes)
        if (hole.state == HoleState.empty && now >= hole.clearAt) hole.index,
    ];
    if (free.isEmpty) return null;
    // Tránh trồi lại đúng hang vừa dùng — trông như lỗi hơn là ngẫu nhiên.
    if (free.length > 1) free.remove(_lastHole);
    return free[_random.nextInt(free.length)];
  }

  bool _shouldSpawnTrap() =>
      rules.trapChance > 0 &&
      _activeTraps < maxTraps &&
      _random.nextDouble() < rules.trapChance;

  Duration get _currentUpTime => rules.upTime * (1 - maxSpeedUp * _progress);

  void _spawn(MoleHole hole, Duration now) {
    hole
      ..state = HoleState.up
      ..moleId = _nextMoleId++
      ..isTrap = false
      ..icon = characters.isEmpty
          ? null
          : characters[_random.nextInt(characters.length)]
      ..hitBy = null
      ..hideAt = now + _jitter(_currentUpTime, 0.15);
    _spawned++;
    _lastHole = hole.index;
  }

  /// Bom chiếm một nhịp trồi lên nhưng không tính vào số con của lượt.
  void _spawnTrap(MoleHole hole, Duration now) {
    hole
      ..state = HoleState.up
      ..moleId = _nextMoleId++
      ..isTrap = true
      ..icon = null
      ..hitBy = null
      ..hideAt = now + _jitter(_currentUpTime * trapLinger, 0.15);
    _lastHole = hole.index;
  }

  /// [base] ± [spread] (tỉ lệ), ngẫu nhiên đều.
  Duration _jitter(Duration base, double spread) {
    final factor = 1 + (_random.nextDouble() * 2 - 1) * spread;
    return base * factor;
  }
}
