import 'card_icon.dart';

/// Ba chế độ chơi ở màn sảnh.
enum GameMode {
  /// Một người chơi — đập đủ số chuột chũi nhanh nhất, ít cú đập hụt nhất.
  solo,

  /// Người vs AI — cùng tranh đập trên một bàn, ai đập được nhiều hơn thì thắng.
  vsAi,

  /// Hai người trên cùng một máy — lần lượt mỗi người một lượt.
  pvp,
}

extension GameModeX on GameMode {
  /// Số người chơi mà engine cần quản lý điểm.
  int get playerCount => this == GameMode.solo ? 1 : 2;

  /// Có tính điểm đối kháng (hiện thẻ điểm) hay không.
  bool get isVersus => this != GameMode.solo;

  /// Người chơi lần lượt thay nhau (chỉ 2 người chung máy). Đấu AI thì hai bên
  /// tranh nhau trên cùng một bàn, không có lượt.
  bool get takesTurns => this == GameMode.pvp;

  String get storageKey => name;
}

/// Độ khó của AI — quyết định AI phản xạ nhanh cỡ nào và hay trượt tới đâu.
enum AiDifficulty { easy, normal, hard }

extension AiDifficultyX on AiDifficulty {
  /// Xác suất AI kịp nhắm vào một con chuột chũi vừa trồi lên.
  double get hitChance {
    switch (this) {
      case AiDifficulty.easy:
        return 0.45;
      case AiDifficulty.normal:
        return 0.70;
      case AiDifficulty.hard:
        return 0.90;
    }
  }

  /// Thời gian phản xạ nhanh nhất của AI.
  Duration get reactionMin {
    switch (this) {
      case AiDifficulty.easy:
        return const Duration(milliseconds: 650);
      case AiDifficulty.normal:
        return const Duration(milliseconds: 480);
      case AiDifficulty.hard:
        return const Duration(milliseconds: 330);
    }
  }

  /// Thời gian phản xạ chậm nhất của AI. Nếu vượt quá lúc chuột chũi thụt
  /// xuống thì AI tự nhiên đập hụt — không cần cố tình "chơi dở".
  Duration get reactionMax {
    switch (this) {
      case AiDifficulty.easy:
        return const Duration(milliseconds: 1100);
      case AiDifficulty.normal:
        return const Duration(milliseconds: 850);
      case AiDifficulty.hard:
        return const Duration(milliseconds: 620);
    }
  }

  /// Xác suất AI lỡ tay đập vào một quả bom vừa trồi lên. AI không được miễn
  /// nhiễm với bẫy — nếu không, mức khó chỉ phạt mỗi người chơi.
  double get trapMistakeChance {
    switch (this) {
      case AiDifficulty.easy:
        return 0.30;
      case AiDifficulty.normal:
        return 0.15;
      case AiDifficulty.hard:
        return 0.05;
    }
  }
}

/// Độ khó của bàn chơi, áp dụng cho cả ba chế độ.
enum BoardDifficulty {
  /// Chỉ có chuột chũi.
  normal,

  /// Bom bẫy trồi lên xen kẽ — đập nhầm bị trừ điểm.
  hard,
}

extension BoardDifficultyX on BoardDifficulty {
  /// Xác suất một lần trồi lên là bom thay vì chuột chũi.
  double get trapChance => this == BoardDifficulty.hard ? 0.25 : 0;

  /// Số điểm bị trừ khi đập nhầm bom.
  int get trapPenalty => 1;
}

/// Kích thước bàn chơi: số hang, số chuột chũi mỗi lượt và nhịp độ.
///
/// Bàn càng lớn thì càng nhiều con trồi lên cùng lúc và thụt xuống càng nhanh.
enum BoardSize {
  small(3, 3, 20, 1, 1150),
  medium(3, 4, 25, 2, 1000),
  large(4, 4, 30, 2, 900),
  huge(4, 5, 40, 3, 820);

  const BoardSize(
    this.columns,
    this.rows,
    this.moleCount,
    this.maxActive,
    this.upTimeMs,
  );

  final int columns;
  final int rows;

  /// Chơi đơn: số con phải đập trúng. Chế độ đấu: số con trồi lên mỗi lượt.
  final int moleCount;

  /// Số chuột chũi tối đa cùng ló đầu một lúc.
  final int maxActive;

  /// Thời gian một con ở trên mặt đất lúc đầu ván (sẽ nhanh dần về cuối).
  final int upTimeMs;

  int get holeCount => columns * rows;
}

/// Toàn bộ tham số để khởi tạo một ván. Bất biến — muốn đổi thì tạo ván mới.
class GameConfig {
  final GameMode mode;
  final BoardSize boardSize;
  final AiDifficulty aiDifficulty;

  /// Có bom bẫy hay không — áp dụng cho mọi chế độ.
  final BoardDifficulty boardDifficulty;

  /// Nhân vật trồi lên. null = chuột chũi cổ điển.
  final CardCategory? category;

  /// Số giây đếm ngược trước khi bắt đầu ván.
  final int countdownSeconds;

  const GameConfig({
    required this.mode,
    this.boardSize = BoardSize.medium,
    this.aiDifficulty = AiDifficulty.normal,
    this.boardDifficulty = BoardDifficulty.normal,
    this.category,
    this.countdownSeconds = 2,
  });

  GameConfig copyWith({
    GameMode? mode,
    BoardSize? boardSize,
    AiDifficulty? aiDifficulty,
    BoardDifficulty? boardDifficulty,
    CardCategory? category,
    bool clearCategory = false,
    int? countdownSeconds,
  }) {
    return GameConfig(
      mode: mode ?? this.mode,
      boardSize: boardSize ?? this.boardSize,
      aiDifficulty: aiDifficulty ?? this.aiDifficulty,
      boardDifficulty: boardDifficulty ?? this.boardDifficulty,
      category: clearCategory ? null : (category ?? this.category),
      countdownSeconds: countdownSeconds ?? this.countdownSeconds,
    );
  }

  /// Ván này có bom bẫy không.
  bool get hasTraps => boardDifficulty.trapChance > 0;

  /// Khoá dùng để lưu kỷ lục riêng cho từng (chế độ, cỡ bàn, độ khó).
  ///
  /// Mức thường giữ nguyên khoá cũ để người chơi nâng cấp không mất kỷ lục;
  /// mức khó có bảng riêng vì bị trừ điểm nên không so được với mức thường.
  String get recordKey {
    final base = '${mode.storageKey}_${boardSize.name}';
    return hasTraps ? '${base}_${boardDifficulty.name}' : base;
  }
}
