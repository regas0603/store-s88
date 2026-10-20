import 'card_icon.dart';

/// Một ô trên bàn chơi.
///
/// [index] là vị trí cố định trong danh sách — dùng làm định danh duy nhất,
/// vì cùng một [icon] luôn xuất hiện ở đúng hai ô khác nhau.
class BoardCard {
  final int index;
  final CardIcon icon;

  /// Đang ngửa (do người chơi vừa lật, hoặc đang trong giai đoạn xem trước).
  bool faceUp;

  /// Đã ghép cặp thành công — không lật lại được nữa.
  bool matched;

  /// Người chơi nào ăn được cặp này (null nếu chưa ai ăn).
  int? matchedBy;

  BoardCard({
    required this.index,
    required this.icon,
    this.faceUp = false,
    this.matched = false,
    this.matchedBy,
  });

  /// Có hiển thị mặt trước hay không.
  bool get isRevealed => faceUp || matched;

  /// Còn có thể bấm vào được không.
  bool get isSelectable => !faceUp && !matched;

  @override
  String toString() =>
      'BoardCard(#$index, ${icon.id}, faceUp: $faceUp, matched: $matched)';
}
