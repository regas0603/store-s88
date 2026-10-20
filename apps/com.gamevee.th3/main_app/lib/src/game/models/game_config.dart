import 'card_icon.dart';

/// Ba chế độ chơi ở màn sảnh.
enum GameMode {
  /// Một người chơi — đua với đồng hồ và số lượt lật.
  solo,

  /// Người vs AI — luân phiên, ai ăn nhiều cặp hơn thì thắng.
  vsAi,

  /// Hai người trên cùng một máy — luân phiên.
  pvp,
}

extension GameModeX on GameMode {
  /// Số người chơi mà engine cần quản lý điểm.
  int get playerCount => this == GameMode.solo ? 1 : 2;

  bool get isTurnBased => this != GameMode.solo;

  String get storageKey => name;
}

/// Độ khó của AI — quyết định AI nhớ được bao nhiêu phần trăm lá đã lật.
enum AiDifficulty { easy, normal, hard }

extension AiDifficultyX on AiDifficulty {
  /// Xác suất AI ghi nhớ một lá vừa được lật lên.
  double get memoryAccuracy {
    switch (this) {
      case AiDifficulty.easy:
        return 0.35;
      case AiDifficulty.normal:
        return 0.70;
      case AiDifficulty.hard:
        return 0.95;
    }
  }

  /// Xác suất AI quên một mục đã nhớ, tính mỗi lượt của nó.
  double get forgetRate {
    switch (this) {
      case AiDifficulty.easy:
        return 0.18;
      case AiDifficulty.normal:
        return 0.06;
      case AiDifficulty.hard:
        return 0.0;
    }
  }

  /// Thời gian "giả vờ suy nghĩ" để nước đi của AI trông tự nhiên.
  Duration get thinkingDelay {
    switch (this) {
      case AiDifficulty.easy:
        return const Duration(milliseconds: 900);
      case AiDifficulty.normal:
        return const Duration(milliseconds: 700);
      case AiDifficulty.hard:
        return const Duration(milliseconds: 520);
    }
  }
}

/// Kích thước bàn chơi. Giữ columns <= 6 để lá bài không quá nhỏ ở màn dọc.
enum BoardSize {
  small(4, 4),
  medium(4, 6),
  large(5, 6),
  huge(6, 8);

  const BoardSize(this.columns, this.rows);

  final int columns;
  final int rows;

  int get cardCount => columns * rows;

  int get pairs => cardCount ~/ 2;
}

/// Toàn bộ tham số để khởi tạo một ván. Bất biến — muốn đổi thì tạo ván mới.
class GameConfig {
  final GameMode mode;
  final BoardSize boardSize;
  final AiDifficulty aiDifficulty;

  /// null = trộn icon từ mọi chủ đề.
  final CardCategory? category;

  /// Thời gian cho người chơi nhìn trước toàn bộ bàn, tính bằng giây.
  final int peekSeconds;

  const GameConfig({
    required this.mode,
    this.boardSize = BoardSize.medium,
    this.aiDifficulty = AiDifficulty.normal,
    this.category,
    this.peekSeconds = 2,
  });

  GameConfig copyWith({
    GameMode? mode,
    BoardSize? boardSize,
    AiDifficulty? aiDifficulty,
    CardCategory? category,
    bool clearCategory = false,
    int? peekSeconds,
  }) {
    return GameConfig(
      mode: mode ?? this.mode,
      boardSize: boardSize ?? this.boardSize,
      aiDifficulty: aiDifficulty ?? this.aiDifficulty,
      category: clearCategory ? null : (category ?? this.category),
      peekSeconds: peekSeconds ?? this.peekSeconds,
    );
  }

  /// Khoá dùng để lưu kỷ lục riêng cho từng (chế độ, cỡ bàn).
  String get recordKey => '${mode.storageKey}_${boardSize.name}';
}
