import 'dart:math';

import '../models/board_card.dart';
import '../models/card_icon.dart';

/// Kết quả của một cú lật.
enum FlipOutcome {
  /// Không hợp lệ: ô đã ngửa / đã ghép, ngoài phạm vi, hoặc đang chờ resolve.
  rejected,

  /// Đã lật lá thứ nhất, chờ lá thứ hai.
  firstCard,

  /// Đã lật lá thứ hai — caller phải gọi [MemoryEngine.resolve] sau một nhịp
  /// delay để người chơi kịp nhìn.
  secondCard,
}

/// Kết quả sau khi engine xử lý cặp vừa lật.
class ResolveOutcome {
  /// Hai lá có khớp nhau không.
  final bool matched;

  /// Người chơi đã thực hiện nước đi này (không phải người sẽ đi tiếp).
  final int player;

  final int firstIndex;
  final int secondIndex;

  /// Lượt có bị chuyển sang người khác không.
  final bool turnPassed;

  /// Ván đã kết thúc sau nước đi này chưa.
  final bool gameFinished;

  const ResolveOutcome({
    required this.matched,
    required this.player,
    required this.firstIndex,
    required this.secondIndex,
    required this.turnPassed,
    required this.gameFinished,
  });
}

/// Luật chơi thuần Dart — không import Flutter, không timer, không side effect.
///
/// Tách riêng như vậy để test được toàn bộ luật bằng unit test chạy trong vài
/// mili-giây, và để UI có thể thay đổi mà không đụng tới logic.
///
/// Vòng đời một nước đi:
/// ```
/// flip(a) -> firstCard
/// flip(b) -> secondCard
/// (UI chờ ~700ms cho người chơi nhìn)
/// resolve() -> ResolveOutcome
/// ```
class MemoryEngine {
  final List<BoardCard> cards;
  final int playerCount;

  final List<int> _scores;
  final List<int> _selection = <int>[];

  int _currentPlayer = 0;
  int _moves = 0;

  MemoryEngine({
    required this.cards,
    this.playerCount = 1,
  })  : assert(playerCount >= 1, 'Cần ít nhất một người chơi'),
        assert(cards.length.isEven, 'Số lá bài phải chẵn'),
        _scores = List<int>.filled(playerCount, 0);

  /// Dựng bàn từ danh sách icon: mỗi icon nhân đôi rồi xáo trộn.
  factory MemoryEngine.fromIcons(
    List<CardIcon> icons, {
    int playerCount = 1,
    Random? random,
  }) {
    final rng = random ?? Random();
    final deck = <CardIcon>[...icons, ...icons]..shuffle(rng);
    final cards = <BoardCard>[
      for (var i = 0; i < deck.length; i++) BoardCard(index: i, icon: deck[i]),
    ];
    return MemoryEngine(cards: cards, playerCount: playerCount);
  }

  List<int> get scores => List<int>.unmodifiable(_scores);

  int get currentPlayer => _currentPlayer;

  /// Số nước đi đã hoàn tất (mỗi nước = một cặp được lật và xử lý xong).
  int get moves => _moves;

  List<int> get selection => List<int>.unmodifiable(_selection);

  /// Đang có đủ hai lá chờ [resolve].
  bool get awaitingResolve => _selection.length == 2;

  int get totalPairs => cards.length ~/ 2;

  int get matchedPairs => cards.where((c) => c.matched).length ~/ 2;

  bool get isFinished => cards.every((c) => c.matched);

  /// Danh sách người chơi có điểm cao nhất. Nhiều hơn một phần tử = hoà.
  List<int> get winners {
    final best = _scores.reduce(max);
    return <int>[
      for (var i = 0; i < _scores.length; i++)
        if (_scores[i] == best) i,
    ];
  }

  /// Lật một lá. Trả về [FlipOutcome.rejected] nếu nước đi không hợp lệ —
  /// caller cứ gọi thoải mái, engine tự bảo vệ trạng thái.
  FlipOutcome flip(int index) {
    if (awaitingResolve) return FlipOutcome.rejected;
    if (index < 0 || index >= cards.length) return FlipOutcome.rejected;

    final card = cards[index];
    if (!card.isSelectable) return FlipOutcome.rejected;

    card.faceUp = true;
    _selection.add(index);

    return _selection.length == 1 ? FlipOutcome.firstCard : FlipOutcome.secondCard;
  }

  /// Xử lý cặp đang chờ. Ném [StateError] nếu chưa đủ hai lá — gọi sai thứ tự
  /// là bug của caller, không nên nuốt lặng lẽ.
  ResolveOutcome resolve() {
    if (!awaitingResolve) {
      throw StateError('resolve() cần đúng 2 lá đang lật, hiện có ${_selection.length}');
    }

    final firstIndex = _selection[0];
    final secondIndex = _selection[1];
    final first = cards[firstIndex];
    final second = cards[secondIndex];
    final player = _currentPlayer;

    final matched = first.icon.id == second.icon.id;
    _moves++;

    if (matched) {
      first
        ..matched = true
        ..matchedBy = player;
      second
        ..matched = true
        ..matchedBy = player;
      _scores[player]++;
    } else {
      first.faceUp = false;
      second.faceUp = false;
    }

    _selection.clear();

    // Ăn được cặp thì giữ lượt. Đây là luật Concentration tiêu chuẩn và là thứ
    // tạo ra chuỗi combo — bỏ đi thì chế độ đấu mất hết kịch tính.
    final finished = isFinished;
    final turnPassed = !matched && !finished && playerCount > 1;
    if (turnPassed) {
      _currentPlayer = (_currentPlayer + 1) % playerCount;
    }

    return ResolveOutcome(
      matched: matched,
      player: player,
      firstIndex: firstIndex,
      secondIndex: secondIndex,
      turnPassed: turnPassed,
      gameFinished: finished,
    );
  }

  /// Ngửa toàn bộ lá chưa ghép — dùng cho giai đoạn xem trước đầu ván.
  void revealAll() {
    for (final card in cards) {
      if (!card.matched) card.faceUp = true;
    }
  }

  /// Úp lại mọi lá không thuộc lựa chọn hiện tại.
  void hideUnselected() {
    for (final card in cards) {
      if (!card.matched && !_selection.contains(card.index)) {
        card.faceUp = false;
      }
    }
  }

  /// Danh sách ô còn bấm được — AI dùng để ra quyết định.
  List<BoardCard> get selectableCards =>
      cards.where((c) => c.isSelectable).toList(growable: false);
}
