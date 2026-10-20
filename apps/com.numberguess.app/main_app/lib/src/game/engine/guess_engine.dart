import 'dart:math' as math;

import '../models/guess.dart';

/// Kết quả xử lý một lần nhập số.
enum GuessOutcome {
  /// Lượt đã kết thúc (đã trúng hoặc hết lượt) — không nhận thêm.
  rejected,

  /// Nằm ngoài khoảng cho phép. KHÔNG tốn lượt: đây là lỗi nhập, không phải
  /// một phán đoán.
  outOfRange,

  /// Đã đoán số này rồi. Cũng không tốn lượt, vì nó không mang thêm thông tin
  /// nào mà người chơi chưa có.
  duplicate,

  /// Đoán sai, còn lượt.
  wrong,

  /// Đoán sai và đó là lượt cuối cùng.
  exhausted,

  /// Trúng.
  correct,
}

/// Một lượt đoán của một người chơi.
///
/// Giữ luôn [lowBound]/[highBound] — khoảng còn lại sau mọi gợi ý — để UI chỉ
/// việc đọc ra mà hiển thị, không phải tự suy lại từ lịch sử.
class GuessRound {
  final int min;
  final int max;
  final int maxGuesses;

  /// Số bí mật. null = chưa được đặt (chế độ 2 người, chờ người kia nhập).
  int? secret;

  final List<Guess> history = <Guess>[];

  /// Cận dưới/cận trên còn khả dĩ sau các gợi ý đã nhận.
  late int lowBound = min;
  late int highBound = max;

  bool solved = false;

  /// Thời gian người chơi đã dùng cho lượt này.
  Duration elapsed = Duration.zero;

  GuessRound({
    required this.min,
    required this.max,
    required this.maxGuesses,
    this.secret,
  });

  int get guessesUsed => history.length;

  int get guessesLeft => math.max(0, maxGuesses - guessesUsed);

  /// Hết lượt mà vẫn chưa ra.
  bool get exhausted => !solved && guessesUsed >= maxGuesses;

  bool get isOver => solved || exhausted;

  bool get hasSecret => secret != null;

  Guess? get lastGuess => history.isEmpty ? null : history.last;
}

/// Luật chơi thuần Dart — không import Flutter, không timer, không random ẩn.
///
/// Toàn bộ ngẫu nhiên đi qua [math.Random] truyền từ ngoài, nên test chạy được với
/// seed cố định và tái lập chính xác từng ván.
class GuessEngine {
  /// Ngưỡng "rất gần" tính theo tỉ lệ của cả khoảng.
  static const double hotRatio = 0.02;

  /// Ngưỡng "gần".
  static const double warmRatio = 0.08;

  /// Ngưỡng "xa" — xa hơn nữa là "rất xa".
  static const double coldRatio = 0.25;

  final int min;
  final int max;
  final int maxGuesses;
  final int playerCount;

  /// Có chấm gợi ý nóng/lạnh không (mức Thường).
  final bool showHeat;

  final math.Random _random;

  /// Một lượt cho mỗi người chơi, đánh số theo **người đoán**.
  final List<GuessRound> _rounds;

  int _currentPlayer = 0;

  GuessEngine({
    required this.min,
    required this.max,
    required this.maxGuesses,
    this.playerCount = 1,
    this.showHeat = true,
    math.Random? random,
  })  : assert(max > min, 'Khoảng số phải có ít nhất hai giá trị'),
        assert(maxGuesses > 0, 'Phải cho ít nhất một lượt đoán'),
        assert(playerCount >= 1, 'Cần ít nhất một người chơi'),
        _random = random ?? math.Random(),
        _rounds = <GuessRound>[
          for (var i = 0; i < playerCount; i++)
            GuessRound(min: min, max: max, maxGuesses: maxGuesses),
        ];

  List<GuessRound> get rounds => List<GuessRound>.unmodifiable(_rounds);

  /// Người đang đoán.
  int get currentPlayer => _currentPlayer;

  GuessRound get currentRound => _rounds[_currentPlayer];

  GuessRound roundOf(int player) => _rounds[player];

  int get span => max - min + 1;

  /// Mọi lượt đã xong.
  bool get isFinished => _rounds.every((r) => r.isOver);

  /// Số bí mật nằm trong khoảng hợp lệ không.
  bool isInRange(int value) => value >= min && value <= max;

  /// Máy bốc số cho lượt của [player]. Dùng ở chế độ chơi đơn.
  void rollSecretFor(int player) {
    _rounds[player].secret = min + _random.nextInt(span);
  }

  /// Người chơi kia đặt số bí mật cho lượt của [player].
  ///
  /// Trả về false nếu số nằm ngoài khoảng — gọi phía UI chặn trước, nhưng
  /// engine không tin dữ liệu vào.
  bool setSecretFor(int player, int secret) {
    if (!isInRange(secret)) return false;
    _rounds[player].secret = secret;
    return true;
  }

  /// Chuyển người đoán. Trả về false nếu không còn ai chưa chơi.
  bool moveToPlayer(int player) {
    if (player < 0 || player >= playerCount) return false;
    _currentPlayer = player;
    return true;
  }

  /// Chấm một lần đoán của người đang tới lượt.
  ///
  /// Lượt chỉ bị trừ khi [value] thực sự là một phán đoán mới và hợp lệ —
  /// gõ nhầm ngoài khoảng hay lặp lại số cũ không bị phạt.
  GuessOutcome submit(int value) {
    final round = currentRound;
    final secret = round.secret;
    if (secret == null || round.isOver) return GuessOutcome.rejected;
    if (!isInRange(value)) return GuessOutcome.outOfRange;
    if (round.history.any((g) => g.value == value)) {
      return GuessOutcome.duplicate;
    }

    final hint = value == secret
        ? GuessHint.correct
        : (secret > value ? GuessHint.higher : GuessHint.lower);

    round.history.add(
      Guess(
        value: value,
        hint: hint,
        heat: hint == GuessHint.correct ? GuessHeat.none : _heatFor(value, secret),
        ordinal: round.history.length + 1,
      ),
    );

    switch (hint) {
      case GuessHint.correct:
        round
          ..solved = true
          ..lowBound = value
          ..highBound = value;
        return GuessOutcome.correct;
      case GuessHint.higher:
        round.lowBound = math.max(round.lowBound, value + 1);
      case GuessHint.lower:
        round.highBound = math.min(round.highBound, value - 1);
    }

    return round.exhausted ? GuessOutcome.exhausted : GuessOutcome.wrong;
  }

  GuessHeat _heatFor(int value, int secret) {
    if (!showHeat) return GuessHeat.none;
    final distance = (secret - value).abs();
    if (distance <= _threshold(hotRatio)) return GuessHeat.hot;
    if (distance <= _threshold(warmRatio)) return GuessHeat.warm;
    if (distance <= _threshold(coldRatio)) return GuessHeat.cold;
    return GuessHeat.freezing;
  }

  /// Ngưỡng tối thiểu là 1: khoảng 1–50 mà làm tròn xuống 0 thì không bao giờ
  /// có "rất gần".
  int _threshold(double ratio) => math.max(1, (span * ratio).round());

  /// Những người chơi thắng. Nhiều hơn một phần tử = hoà.
  ///
  /// Xếp hạng: đoán ra thắng không đoán ra; cùng đoán ra thì ít lượt hơn
  /// thắng; cùng số lượt thì nhanh hơn thắng.
  List<int> get winners {
    if (playerCount == 1) return const <int>[0];

    int? bestIndex;
    for (var i = 0; i < playerCount; i++) {
      if (bestIndex == null || _compare(i, bestIndex) < 0) bestIndex = i;
    }
    return <int>[
      for (var i = 0; i < playerCount; i++)
        if (_compare(i, bestIndex!) == 0) i,
    ];
  }

  /// <0 nếu [a] chơi hay hơn [b].
  int _compare(int a, int b) {
    final ra = _rounds[a];
    final rb = _rounds[b];
    if (ra.solved != rb.solved) return ra.solved ? -1 : 1;
    if (!ra.solved && !rb.solved) {
      // Cả hai bí: coi như hoà, không bới ra người "bí ít hơn".
      return 0;
    }
    final byGuesses = ra.guessesUsed.compareTo(rb.guessesUsed);
    if (byGuesses != 0) return byGuesses;
    return ra.elapsed.compareTo(rb.elapsed);
  }
}
