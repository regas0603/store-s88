import 'card_icon.dart';

/// Trạng thái của một hang.
enum HoleState {
  /// Không có gì ló lên (hoặc con vừa rồi đang thụt xuống).
  empty,

  /// Có một con đang trồi lên, đập được.
  up,

  /// Vừa bị đập trúng — giữ lại một nhịp để hiện hiệu ứng rồi mới thụt xuống.
  hit,
}

/// Một hang trên bàn chơi.
///
/// Mọi mốc thời gian tính theo *thời gian ván* (đồng hồ dừng khi tạm dừng),
/// nên pause/resume không làm chuột chũi biến mất hay ở lâu hơn bình thường.
class MoleHole {
  final int index;

  HoleState state;

  /// Tăng mỗi lần một con mới trồi lên. UI dùng làm key cho hiệu ứng, AI dùng
  /// để biết con mình định đập có còn là con đó không.
  int moleId;

  /// Nhân vật đang ở hang. null = chuột chũi cổ điển. Giữ nguyên cả khi đã
  /// thụt xuống để hiệu ứng rút về vẫn vẽ đúng hình.
  CardIcon? icon;

  /// Thứ đang trồi lên là bom bẫy, không phải chuột chũi. Đập trúng bị trừ
  /// điểm. Giữ nguyên khi thụt xuống, cùng lý do với [icon].
  bool isTrap;

  /// Lúc con đang [HoleState.up] sẽ tự thụt xuống.
  Duration hideAt;

  /// Khi [HoleState.hit]: lúc dọn hiệu ứng. Khi [HoleState.empty]: hang chưa
  /// được dùng lại trước mốc này (tránh con mới trồi lên giữa lúc con cũ đang
  /// rút về).
  Duration clearAt;

  /// Người chơi đã đập trúng con hiện tại (null nếu chưa ai).
  int? hitBy;

  MoleHole({
    required this.index,
    this.state = HoleState.empty,
    this.moleId = 0,
    this.icon,
    this.isTrap = false,
    this.hideAt = Duration.zero,
    this.clearAt = Duration.zero,
    this.hitBy,
  });

  bool get isUp => state == HoleState.up;

  /// Có một con chuột chũi thật (không phải bom) đang chờ bị đập.
  bool get hasMoleUp => isUp && !isTrap;

  /// Con trong hang đang hiện trên mặt đất (kể cả lúc đang choáng vì bị đập).
  bool get isRaised => state != HoleState.empty;

  @override
  String toString() => 'MoleHole(#$index, $state, mole: $moleId)';
}
