import 'dart:math';

import '../models/board_card.dart';
import '../models/game_config.dart';

/// Đối thủ máy.
///
/// Thiết kế then chốt: AI **không** được nhìn trộm bàn cờ. Nó chỉ biết những lá
/// đã từng được lật lên trước mặt nó, và chỉ nhớ được với xác suất
/// [AiDifficultyX.memoryAccuracy]. Nhờ vậy AI dễ thua một cách *tự nhiên* —
/// đúng kiểu người chơi hay quên — thay vì phải cố tình đi sai nước, thứ mà
/// người chơi luôn nhận ra và thấy bị coi thường.
///
/// Thuần Dart, không phụ thuộc Flutter, nên test được bằng seed cố định.
class AiPlayer {
  final AiDifficulty difficulty;
  final Random _random;

  /// index của ô -> id icon mà AI tin là nằm ở đó.
  final Map<int, String> _memory = <int, String>{};

  AiPlayer({required this.difficulty, Random? random})
      : _random = random ?? Random();

  /// Chỉ dùng cho test/debug.
  Map<int, String> get memorySnapshot => Map<int, String>.unmodifiable(_memory);

  /// Gọi mỗi khi một lá được lật ngửa — kể cả do người chơi lật.
  ///
  /// AI "nhìn thấy" nhưng chỉ ghi nhớ được theo xác suất của độ khó.
  ///
  /// [scale] hạ xác suất ghi nhớ cho những lần "liếc" chứ không phải nhìn kỹ.
  /// Giai đoạn xem trước đầu ván dùng scale thấp: người chơi chỉ kịp nhớ vài lá
  /// trong 2 giây, nên nếu AI hard nuốt trọn cả bàn thì tính năng xem trước
  /// biến thành hình phạt.
  void observe(BoardCard card, {double scale = 1.0}) {
    if (card.matched) {
      _memory.remove(card.index);
      return;
    }
    if (_random.nextDouble() <= difficulty.memoryAccuracy * scale) {
      _memory[card.index] = card.icon.id;
    }
  }

  /// Xác suất ghi nhớ khi chỉ được liếc qua lúc bắt đầu ván.
  static const double peekScale = 0.25;

  /// Xoá khỏi trí nhớ những ô đã bị ăn — chúng không còn ý nghĩa.
  void forgetMatched(Iterable<int> indexes) {
    for (final index in indexes) {
      _memory.remove(index);
    }
  }

  /// Gọi ở đầu mỗi lượt của AI: mô phỏng việc quên dần.
  void decay() {
    final rate = difficulty.forgetRate;
    if (rate <= 0) return;
    _memory.removeWhere((_, __) => _random.nextDouble() < rate);
  }

  /// Chọn lá đầu tiên.
  ///
  /// Ưu tiên: (1) một cặp đã biết chắc, (2) một ô chưa từng thấy — lật ô lạ là
  /// nước đi thu được nhiều thông tin nhất, (3) bất kỳ ô nào còn lại.
  int chooseFirst(List<BoardCard> cards) {
    final selectable = cards.where((c) => c.isSelectable).toList();
    if (selectable.isEmpty) {
      throw StateError('Không còn ô nào để lật');
    }

    final knownPair = _findKnownPair(selectable);
    if (knownPair != null) return knownPair.$1;

    final unseen = selectable.where((c) => !_memory.containsKey(c.index)).toList();
    final pool = unseen.isNotEmpty ? unseen : selectable;
    return pool[_random.nextInt(pool.length)].index;
  }

  /// Chọn lá thứ hai, biết lá đầu là [first].
  int chooseSecond(List<BoardCard> cards, BoardCard first) {
    final selectable = cards
        .where((c) => c.isSelectable && c.index != first.index)
        .toList();
    if (selectable.isEmpty) {
      throw StateError('Không còn ô nào để lật');
    }

    // Nhớ được ô nào cùng icon với lá vừa lật không?
    for (final card in selectable) {
      if (_memory[card.index] == first.icon.id) return card.index;
    }

    final unseen = selectable.where((c) => !_memory.containsKey(c.index)).toList();
    final pool = unseen.isNotEmpty ? unseen : selectable;
    return pool[_random.nextInt(pool.length)].index;
  }

  /// Tìm hai ô còn lật được mà AI tin là cùng icon.
  (int, int)? _findKnownPair(List<BoardCard> selectable) {
    final selectableIndexes = selectable.map((c) => c.index).toSet();
    final byIcon = <String, List<int>>{};

    for (final entry in _memory.entries) {
      if (!selectableIndexes.contains(entry.key)) continue;
      byIcon.putIfAbsent(entry.value, () => <int>[]).add(entry.key);
    }

    for (final indexes in byIcon.values) {
      if (indexes.length >= 2) return (indexes[0], indexes[1]);
    }
    return null;
  }
}
