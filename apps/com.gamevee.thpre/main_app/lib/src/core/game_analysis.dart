/// Model cho tính năng Phân tích ván đấu (US-005).
///
/// File này **thuần Dart** — không import Flutter — để engine phân tích chạy
/// được trong isolate và để unit test không cần Flutter binding.
library;

/// Chất lượng một nước đi, xếp từ tốt nhất đến tệ nhất.
///
/// **Thứ tự enum là dữ liệu đã persist** (lưu bằng index trong JSON). Chỉ được
/// thêm giá trị mới vào CUỐI, không chèn vào giữa.
enum MoveQuality {
  brilliant,
  good,
  inaccuracy,
  mistake,
  blunder;

  bool get isBad => this == MoveQuality.mistake || this == MoveQuality.blunder;
}

/// Kết quả chấm điểm cho một nước đi.
class MoveAnalysis {
  /// Lợi thế sau nước đi, tính theo **góc nhìn của người X (player 1)**,
  /// nhân 1000 và làm tròn. Khoảng giá trị: -1000..1000.
  ///
  /// Luôn quy về góc nhìn X để biểu đồ lợi thế có một trục nhất quán cho cả
  /// ván, không phải đảo dấu theo lượt.
  final int advantageMilli;

  /// Tổn thất so với nước tốt nhất, theo góc nhìn NGƯỜI ĐANG ĐI, ×1000.
  /// Luôn >= 0.
  final int lossMilli;

  final MoveQuality quality;

  /// Nước tốt hơn do engine đề xuất. Chỉ khác null khi [quality] là
  /// mistake/blunder — các mức khác không hiển thị gợi ý để tránh nhiễu.
  final int? betterRow;
  final int? betterCol;

  /// true khi nước này chỉ được quét ở pass nông (hết ngân sách thời gian nên
  /// không kịp đào sâu). Dùng để UI biết mức tin cậy.
  final bool shallow;

  const MoveAnalysis({
    required this.advantageMilli,
    required this.lossMilli,
    required this.quality,
    this.betterRow,
    this.betterCol,
    this.shallow = false,
  });

  bool get hasBetterMove => betterRow != null && betterCol != null;

  double get advantage => advantageMilli / 1000.0;
  double get loss => lossMilli / 1000.0;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'a': advantageMilli,
        'l': lossMilli,
        'q': quality.index,
        if (betterRow != null) 'br': betterRow,
        if (betterCol != null) 'bc': betterCol,
        if (shallow) 's': 1,
      };

  factory MoveAnalysis.fromJson(Map<String, dynamic> json) {
    final int qi = (json['q'] as int?) ?? MoveQuality.good.index;
    return MoveAnalysis(
      advantageMilli: (json['a'] as int?) ?? 0,
      lossMilli: (json['l'] as int?) ?? 0,
      quality: MoveQuality
          .values[qi.clamp(0, MoveQuality.values.length - 1)],
      betterRow: json['br'] as int?,
      betterCol: json['bc'] as int?,
      shallow: (json['s'] as int?) == 1,
    );
  }
}

/// Kết quả phân tích của cả ván, gắn vào `GameRecord.analysis`.
class GameAnalysis {
  /// Tăng khi cấu trúc thay đổi. Bản phân tích có version khác sẽ bị bỏ qua
  /// (coi như chưa phân tích) thay vì làm hỏng cả record.
  static const int schemaVersion = 1;

  /// Cùng độ dài và cùng thứ tự với `GameRecord.moves`.
  /// Nước không được chấm điểm (ví dụ nước của máy) có quality = good và
  /// lossMilli = 0 — UI dùng [isScored] để biết nước nào thật sự được chấm.
  final List<MoveAnalysis> moveAnalyses;

  /// Index (trong `moves`) của những nước ĐÃ được chấm điểm.
  final List<int> scoredIndexes;

  /// 0..100. Với chế độ vs AI chỉ [accuracyX] có nghĩa.
  final int accuracyX;
  final int accuracyO;

  /// Index nước làm lợi thế đảo chiều mạnh nhất. -1 khi không có.
  final int turningPointIndex;

  /// true khi phải cắt pass đào sâu vì hết ngân sách thời gian.
  final bool isShallow;

  final DateTime analyzedAt;

  const GameAnalysis({
    required this.moveAnalyses,
    required this.scoredIndexes,
    required this.accuracyX,
    required this.accuracyO,
    required this.turningPointIndex,
    required this.isShallow,
    required this.analyzedAt,
  });

  bool isScored(int moveIndex) => scoredIndexes.contains(moveIndex);

  /// Đếm số nước theo từng nhãn, chỉ tính các nước đã được chấm.
  Map<MoveQuality, int> get counts {
    final Map<MoveQuality, int> out = <MoveQuality, int>{
      for (final MoveQuality q in MoveQuality.values) q: 0,
    };
    for (final int i in scoredIndexes) {
      if (i < 0 || i >= moveAnalyses.length) continue;
      final MoveQuality q = moveAnalyses[i].quality;
      out[q] = (out[q] ?? 0) + 1;
    }
    return out;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'v': schemaVersion,
        'ax': accuracyX,
        'ao': accuracyO,
        'tp': turningPointIndex,
        if (isShallow) 'sh': 1,
        'at': analyzedAt.millisecondsSinceEpoch,
        'si': scoredIndexes,
        'm': moveAnalyses.map((MoveAnalysis m) => m.toJson()).toList(),
      };

  /// Trả về null khi JSON hỏng hoặc schema không khớp — caller coi như record
  /// chưa được phân tích, KHÔNG được để lỗi lan ra làm hỏng cả `GameRecord`.
  static GameAnalysis? fromJson(Map<String, dynamic> json) {
    try {
      if ((json['v'] as int?) != schemaVersion) return null;
      final List<dynamic> rawM = (json['m'] as List<dynamic>?) ?? <dynamic>[];
      final List<dynamic> rawS = (json['si'] as List<dynamic>?) ?? <dynamic>[];
      return GameAnalysis(
        moveAnalyses: rawM
            .map((dynamic e) =>
                MoveAnalysis.fromJson(e as Map<String, dynamic>))
            .toList(),
        scoredIndexes: rawS.map((dynamic e) => e as int).toList(),
        accuracyX: (json['ax'] as int?) ?? 0,
        accuracyO: (json['ao'] as int?) ?? 0,
        turningPointIndex: (json['tp'] as int?) ?? -1,
        isShallow: (json['sh'] as int?) == 1,
        analyzedAt: DateTime.fromMillisecondsSinceEpoch(
            (json['at'] as int?) ?? 0),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Chuyển (row, col) thành toạ độ kiểu cờ vua: cột = chữ cái, hàng = số.
///
/// Quy ước thống nhất toàn app: cột A..O từ trái sang phải, hàng 1..15 từ trên
/// xuống. Ví dụ (7, 7) trên bàn 15x15 → "H8".
String formatCellCoord(int row, int col) {
  if (row < 0 || col < 0) return '—';
  final int letter = 'A'.codeUnitAt(0) + col;
  return '${String.fromCharCode(letter)}${row + 1}';
}
