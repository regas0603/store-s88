/// Máy trả lời gì cho một lần đoán.
enum GuessHint {
  /// Số bí mật LỚN HƠN số vừa đoán — đoán cao lên.
  higher,

  /// Số bí mật NHỎ HƠN số vừa đoán — đoán thấp xuống.
  lower,

  /// Trúng.
  correct,
}

/// Gợi ý phụ theo độ gần, chỉ bật ở mức Thường.
///
/// Nóng/lạnh làm cho những lần đoán "trượt nhưng sát" vẫn có thông tin, nhờ
/// vậy người mới không phải thuộc lòng chiến thuật chia đôi mới chơi vui được.
enum GuessHeat {
  /// Không dùng (mức Khó) hoặc đã trúng.
  none,

  /// Rất xa.
  freezing,

  /// Xa.
  cold,

  /// Gần.
  warm,

  /// Rất gần.
  hot,
}

/// Một lần đoán đã được chấm, đủ để UI vẽ lại lịch sử mà không cần biết số bí mật.
class Guess {
  /// Số người chơi đã nhập.
  final int value;

  final GuessHint hint;
  final GuessHeat heat;

  /// Thứ tự lần đoán, bắt đầu từ 1.
  final int ordinal;

  const Guess({
    required this.value,
    required this.hint,
    required this.heat,
    required this.ordinal,
  });

  bool get isCorrect => hint == GuessHint.correct;

  @override
  String toString() => 'Guess(#$ordinal, $value, ${hint.name})';
}
