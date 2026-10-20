import 'dart:math' as math;

/// Các chế độ chơi ở màn sảnh.
enum GameMode {
  /// Một người chơi — máy random số, người chơi đoán.
  solo,

  /// Hai người trên cùng một máy: người này **chọn** số bí mật, người kia
  /// **đoán**. Hết lượt thì đổi vai, ai đoán ra bằng ít lượt hơn thì thắng.
  duel,

  /// Chuỗi vòng liên tiếp, mỗi vòng ít lượt hơn vòng trước. Đoán ra thì đi
  /// tiếp, hết lượt là dừng. Điểm = số vòng sống sót.
  survival,
}

extension GameModeX on GameMode {
  /// Số người chơi mà engine cần quản lý điểm.
  int get playerCount => this == GameMode.duel ? 2 : 1;

  /// Có hai bên so kè nhau hay không.
  bool get isDuel => this == GameMode.duel;

  /// Có phải chuỗi vòng nối tiếp không.
  bool get isSurvival => this == GameMode.survival;

  String get storageKey => name;
}

/// Khoảng số máy (hoặc đối thủ) chọn bí mật.
///
/// [normalGuesses]/[hardGuesses] luôn >= ceil(log2(span)) — số lượt tối thiểu
/// của chiến thuật chia đôi. Nếu để thấp hơn thì kể cả người chơi tối ưu cũng
/// thua, và trò chơi biến thành đỏ đen.
enum GuessRange {
  tiny(1, 50, 10, 7),
  small(1, 100, 12, 8),
  big(1, 500, 15, 10),
  huge(1, 1000, 18, 11);

  const GuessRange(this.min, this.max, this.normalGuesses, this.hardGuesses);

  final int min;
  final int max;

  /// Số lượt đoán tối đa ở mức Thường.
  final int normalGuesses;

  /// Số lượt đoán tối đa ở mức Khó.
  final int hardGuesses;

  /// Số lượng giá trị có thể có.
  int get span => max - min + 1;

  /// Số lượt tối thiểu mà chiến thuật chia đôi cần ở trường hợp tệ nhất:
  /// ceil(log2(span)).
  ///
  /// Đây là **sàn** của chế độ Sinh tồn. Cắt xuống dưới mức này thì người chơi
  /// tối ưu cũng có thể thua, và vòng đó biến thành đỏ đen — đúng cái điều mà
  /// [normalGuesses]/[hardGuesses] đang tránh.
  int get minHalvingGuesses => (math.log(span) / math.ln2).ceil();
}

/// Độ khó — quyết định số lượt đoán và có gợi ý "nóng/lạnh" hay không.
enum GuessDifficulty {
  /// Nhiều lượt, kèm gợi ý nóng/lạnh theo độ gần.
  normal,

  /// Ít lượt, chỉ nói cao hơn hay thấp hơn.
  hard,
}

extension GuessDifficultyX on GuessDifficulty {
  /// Có hiện gợi ý nóng/lạnh không.
  bool get showsHeat => this == GuessDifficulty.normal;

  int maxGuessesFor(GuessRange range) => this == GuessDifficulty.normal
      ? range.normalGuesses
      : range.hardGuesses;
}

/// Toàn bộ tham số để khởi tạo một ván. Bất biến — muốn đổi thì tạo ván mới.
class GameConfig {
  final GameMode mode;
  final GuessRange range;
  final GuessDifficulty difficulty;

  /// Số giây đếm ngược khi chuyền máy cho người kế tiếp (chỉ chế độ 2 người).
  final int handoffSeconds;

  const GameConfig({
    required this.mode,
    this.range = GuessRange.small,
    this.difficulty = GuessDifficulty.normal,
    this.handoffSeconds = 3,
  });

  int get maxGuesses => difficulty.maxGuessesFor(range);

  bool get showsHeat => difficulty.showsHeat;

  /// Số lượt cho vòng thứ [round] (đếm từ 1) của chế độ Sinh tồn.
  ///
  /// Mỗi vòng bớt một lượt, nhưng **không bao giờ xuống dưới**
  /// [GuessRange.minHalvingGuesses]. Khi chạm sàn thì ngân sách đứng yên: từ
  /// đó trở đi mỗi vòng đều đòi chia đôi hoàn hảo, sai một nước là dừng cuộc
  /// chơi. Đó là điểm dừng tự nhiên của chế độ này — không cần cắt tiếp để
  /// biến nó thành may rủi.
  int survivalGuessesFor(int round) {
    final start = difficulty.maxGuessesFor(range);
    return math.max(range.minHalvingGuesses, start - (round - 1));
  }

  /// Vòng đầu tiên mà ngân sách chạm sàn — từ vòng này trở đi độ khó không
  /// tăng nữa. UI dùng để báo trước cho người chơi.
  int get survivalFloorRound =>
      difficulty.maxGuessesFor(range) - range.minHalvingGuesses + 1;

  GameConfig copyWith({
    GameMode? mode,
    GuessRange? range,
    GuessDifficulty? difficulty,
    int? handoffSeconds,
  }) {
    return GameConfig(
      mode: mode ?? this.mode,
      range: range ?? this.range,
      difficulty: difficulty ?? this.difficulty,
      handoffSeconds: handoffSeconds ?? this.handoffSeconds,
    );
  }

  /// Khoá lưu kỷ lục riêng cho từng (chế độ, khoảng số, độ khó). Hai độ khó
  /// cho số lượt khác nhau nên không so chung một bảng được.
  String get recordKey => '${mode.storageKey}_${range.name}_${difficulty.name}';
}
