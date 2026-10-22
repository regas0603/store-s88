import 'dart:math';

import '../models/game_config.dart';
import '../models/mole_hole.dart';

/// Đối thủ máy.
///
/// Thiết kế then chốt: AI **không** đập tức thì. Mỗi khi một con trồi lên, nó
/// chỉ "để ý" được với xác suất [AiDifficultyX.hitChance], rồi cần một khoảng
/// phản xạ ngẫu nhiên mới đập tới. Con đã thụt xuống hoặc bị người chơi đập
/// trước thì cú đập đó bỏ. Nhờ vậy AI thua một cách *tự nhiên* — chậm tay đúng
/// kiểu người — thay vì phải cố tình đập trượt.
///
/// Thuần Dart, không phụ thuộc Flutter, nên test được bằng seed cố định.
class AiPlayer {
  final AiDifficulty difficulty;
  final Random _random;

  /// moleId -> (hang, mốc thời gian AI sẽ đập tới).
  final Map<int, (int, Duration)> _plans = <int, (int, Duration)>{};

  AiPlayer({required this.difficulty, Random? random})
      : _random = random ?? Random();

  /// Chỉ dùng cho test/debug.
  int get pendingCount => _plans.length;

  /// Gọi mỗi khi một con vừa trồi lên.
  void onMolePopped(MoleHole hole, Duration now) {
    if (_random.nextDouble() > difficulty.hitChance) return;
    _plan(hole, now);
  }

  /// Gọi mỗi khi một quả bom vừa trồi lên. AI chỉ đập vào nếu "lỡ tay" theo
  /// [AiDifficultyX.trapMistakeChance] — cùng nhịp phản xạ như khi đập chuột,
  /// nên trông như một cú đập vội chứ không phải cố tình.
  void onTrapPopped(MoleHole hole, Duration now) {
    if (_random.nextDouble() >= difficulty.trapMistakeChance) return;
    _plan(hole, now);
  }

  void _plan(MoleHole hole, Duration now) {
    final min = difficulty.reactionMin.inMilliseconds;
    final max = difficulty.reactionMax.inMilliseconds;
    final reaction = Duration(milliseconds: min + _random.nextInt(max - min + 1));
    _plans[hole.moleId] = (hole.index, now + reaction);
  }

  /// Những hang AI đập vào ở mốc [now]. Kế hoạch đã tới hạn luôn bị xoá, dù
  /// con đó còn hay không.
  List<int> dueWhacks(List<MoleHole> holes, Duration now) {
    final due = <int>[];
    _plans.removeWhere((moleId, plan) {
      final (index, at) = plan;
      final hole = holes[index];
      final stillThere = hole.isUp && hole.moleId == moleId;
      if (!stillThere) return true;
      if (now < at) return false;
      due.add(index);
      return true;
    });
    return due;
  }

  void reset() => _plans.clear();
}
