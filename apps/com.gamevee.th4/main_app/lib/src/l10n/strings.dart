import 'package:flutter/widgets.dart';

import '../game/models/card_icon.dart';
import '../game/models/game_config.dart';

/// Chuỗi hiển thị cho tiếng Việt và tiếng Anh.
///
/// Cố tình KHÔNG dùng `intl` + `gen_l10n`: app chỉ có 2 ngôn ngữ và ~90 chuỗi,
/// nên một file getter đọc thẳng được sẽ nhanh hơn nhiều so với vòng lặp
/// arb -> build_runner mỗi lần sửa một chữ.
///
/// Điểm đổi ý: khi thêm ngôn ngữ thứ ba, hoặc khi cần người ngoài team dịch,
/// hãy chuyển sang gen_l10n — lúc đó file .arb mới đáng giá.
class AppStrings {
  final String languageCode;

  const AppStrings(this.languageCode);

  static const List<Locale> supportedLocales = <Locale>[
    Locale('vi'),
    Locale('en'),
  ];

  /// Lấy chuỗi theo locale đang hiệu lực của widget tree.
  static AppStrings of(BuildContext context) {
    final code = Localizations.maybeLocaleOf(context)?.languageCode ?? 'vi';
    return AppStrings(code == 'en' ? 'en' : 'vi');
  }

  bool get isEnglish => languageCode == 'en';

  String _t(String vi, String en) => isEnglish ? en : vi;

  // ---------------------------------------------------------------- chung
  String get appName => 'Flipmind';
  String get tagline => _t('Lật thẻ. Luyện trí nhớ.', 'Flip cards. Train your mind.');
  String get cancel => _t('Huỷ', 'Cancel');
  String get confirm => _t('Đồng ý', 'Confirm');
  String get close => _t('Đóng', 'Close');
  String get back => _t('Quay lại', 'Back');

  // -------------------------------------------------------------- tutorial
  String get skip => _t('Bỏ qua', 'Skip');
  String get next => _t('Tiếp', 'Next');
  String get startPlaying => _t('Bắt đầu chơi', 'Start playing');

  String get tutorial1Title => _t('Lật hai lá', 'Flip two cards');
  String get tutorial1Body => _t(
        'Chạm để lật một lá, rồi lật lá thứ hai. Cả hai sẽ ngửa trong giây lát để bạn kịp nhìn.',
        'Tap a card to flip it, then flip a second one. Both stay face up for a moment so you can see them.',
      );

  String get tutorial2Title => _t('Ghép đúng cặp', 'Match the pair');
  String get tutorial2Body => _t(
        'Hai lá giống nhau sẽ ở lại trên bàn và bạn được cộng điểm. Khác nhau thì chúng úp lại — hãy ghi nhớ vị trí.',
        'A matching pair stays on the board and scores a point. A mismatch flips back — remember where they were.',
      );

  String get tutorial3Title => _t('Giữ lượt khi ăn cặp', 'Keep your turn');
  String get tutorial3Body => _t(
        'Trong chế độ đấu, ăn được một cặp thì bạn được đi tiếp. Lật sai mới mất lượt, nên chuỗi combo là chìa khoá thắng.',
        'In versus modes, matching a pair lets you go again. You only lose your turn on a miss, so combos decide the game.',
      );

  String get tutorial4Title => _t('Ba cách chơi', 'Three ways to play');
  String get tutorial4Body => _t(
        'Chơi đơn để phá kỷ lục của chính mình, đấu AI ở ba mức khó, hoặc đưa máy cho bạn bè và thi đấu trực tiếp.',
        'Play solo to beat your own record, face the AI at three levels, or pass the phone and duel a friend.',
      );

  // ------------------------------------------------------------------ menu
  String get modeSolo => _t('Chơi một mình', 'Solo');
  String get modeSoloHint => _t('Đua với đồng hồ', 'Race the clock');
  String get modeVsAi => _t('Đấu với máy', 'Versus AI');
  String get modeVsAiHint => _t('Ba mức độ khó', 'Three difficulty levels');
  String get modePvp => _t('Hai người chơi', 'Two players');
  String get modePvpHint => _t('Cùng một thiết bị', 'Same device');
  String get settings => _t('Cài đặt', 'Settings');
  String get howToPlay => _t('Hướng dẫn chơi', 'How to play');
  String get gamesPlayed => _t('Ván đã chơi', 'Games played');
  String get vsAiRecord => _t('Thành tích đấu AI', 'AI record');

  // ------------------------------------------------------------ thiết lập ván
  String get newGame => _t('Ván mới', 'New game');
  String get boardSizeLabel => _t('Cỡ bàn', 'Board size');
  String get difficultyLabel => _t('Độ khó', 'Difficulty');
  String get cardThemeLabel => _t('Bộ thẻ', 'Card set');
  String get allThemes => _t('Tất cả', 'All');
  String get start => _t('Bắt đầu', 'Start');

  String boardSizeName(BoardSize size) {
    switch (size) {
      case BoardSize.small:
        return _t('Nhỏ', 'Small');
      case BoardSize.medium:
        return _t('Vừa', 'Medium');
      case BoardSize.large:
        return _t('Lớn', 'Large');
      case BoardSize.huge:
        return _t('Siêu lớn', 'Huge');
    }
  }

  String boardSizeDetail(BoardSize size) =>
      '${size.columns}×${size.rows} · ${size.pairs} ${_t('cặp', 'pairs')}';

  String difficultyName(AiDifficulty level) {
    switch (level) {
      case AiDifficulty.easy:
        return _t('Dễ', 'Easy');
      case AiDifficulty.normal:
        return _t('Thường', 'Normal');
      case AiDifficulty.hard:
        return _t('Khó', 'Hard');
    }
  }

  String difficultyDetail(AiDifficulty level) {
    switch (level) {
      case AiDifficulty.easy:
        return _t('AI hay quên vị trí', 'The AI forgets a lot');
      case AiDifficulty.normal:
        return _t('AI nhớ khá tốt', 'The AI remembers well');
      case AiDifficulty.hard:
        return _t('AI gần như nhớ hết', 'The AI forgets almost nothing');
    }
  }

  String categoryName(CardCategory category) {
    switch (category) {
      case CardCategory.fruit:
        return _t('Trái cây', 'Fruit');
      case CardCategory.animal:
        return _t('Động vật', 'Animals');
      case CardCategory.food:
        return _t('Đồ ăn', 'Food');
      case CardCategory.nature:
        return _t('Thiên nhiên', 'Nature');
      case CardCategory.object:
        return _t('Đồ vật', 'Objects');
      case CardCategory.sport:
        return _t('Thể thao', 'Sports');
      case CardCategory.vehicle:
        return _t('Phương tiện', 'Vehicles');
    }
  }

  // ------------------------------------------------------------------ ván chơi
  String get you => _t('Bạn', 'You');
  String get ai => _t('Máy', 'AI');
  String get player1 => _t('Người 1', 'Player 1');
  String get player2 => _t('Người 2', 'Player 2');
  String get yourTurn => _t('Lượt của bạn', 'Your turn');
  String turnOf(String name) => _t('Lượt của $name', "$name's turn");
  String get aiThinking => _t('Máy đang nghĩ…', 'AI is thinking…');
  String get memorize => _t('Ghi nhớ nhanh!', 'Memorize!');
  String get moves => _t('Lượt', 'Moves');
  String get time => _t('Thời gian', 'Time');
  String get pairsLeft => _t('Cặp còn lại', 'Pairs left');
  String get paused => _t('Tạm dừng', 'Paused');
  String get resume => _t('Tiếp tục', 'Resume');
  String get restart => _t('Chơi lại', 'Restart');
  String get quitTitle => _t('Thoát ván này?', 'Quit this game?');
  String get quitBody => _t(
        'Tiến trình ván hiện tại sẽ không được lưu.',
        'Your progress in this round will be lost.',
      );
  String get quit => _t('Thoát', 'Quit');

  // ------------------------------------------------------------------ kết quả
  String get resultSolo => _t('Hoàn thành!', 'Cleared!');
  String get resultWin => _t('Bạn thắng!', 'You win!');
  String get resultLose => _t('Bạn thua', 'You lose');
  String get resultDraw => _t('Hoà', 'Draw');
  String resultPlayerWins(String name) => _t('$name thắng!', '$name wins!');
  String get newRecord => _t('Kỷ lục mới!', 'New record!');
  String get bestTime => _t('Thời gian tốt nhất', 'Best time');
  String get bestMoves => _t('Ít lượt nhất', 'Fewest moves');
  String get noRecordYet => _t('Chưa có kỷ lục', 'No record yet');
  String get playAgain => _t('Chơi ván nữa', 'Play again');
  String get backToMenu => _t('Về sảnh', 'Back to menu');

  // ------------------------------------------------------------------ cài đặt
  String get sectionAudio => _t('Âm thanh', 'Audio');
  String get sfx => _t('Hiệu ứng âm thanh', 'Sound effects');
  String get music => _t('Nhạc nền', 'Background music');
  String get musicHint => _t(
        'Cần thêm file assets/sfx/music.mp3',
        'Requires assets/sfx/music.mp3',
      );
  String get volume => _t('Âm lượng', 'Volume');
  String get haptics => _t('Rung phản hồi', 'Haptic feedback');

  String get sectionDisplay => _t('Hiển thị', 'Display');
  String get theme => _t('Giao diện', 'Theme');
  String get themeSystem => _t('Theo hệ thống', 'System');
  String get themeLight => _t('Sáng', 'Light');
  String get themeDark => _t('Tối', 'Dark');
  String get language => _t('Ngôn ngữ', 'Language');
  String get languageSystem => _t('Theo thiết bị', 'Device default');
  String get showTimer => _t('Hiện đồng hồ khi chơi', 'Show timer in game');
  String get showTimerHint => _t(
        'Tắt đi nếu bạn muốn chơi thư giãn, không áp lực thời gian.',
        'Turn off for a relaxed game with no time pressure.',
      );

  String get sectionGameplay => _t('Lối chơi', 'Gameplay');
  String get peekSeconds => _t('Xem trước bàn cờ', 'Peek at the board');
  String get peekSecondsHint => _t(
        'Số giây ngửa toàn bộ thẻ khi bắt đầu ván.',
        'Seconds all cards stay face up at the start.',
      );
  String secondsValue(int value) =>
      value == 0 ? _t('Tắt', 'Off') : _t('$value giây', '${value}s');

  String get sectionData => _t('Dữ liệu', 'Data');
  String get replayTutorial => _t('Xem lại hướng dẫn', 'Replay the tutorial');
  String get resetStats => _t('Xoá thành tích', 'Clear statistics');
  String get resetStatsConfirm => _t(
        'Toàn bộ kỷ lục và số ván đã chơi sẽ bị xoá. Không khôi phục được.',
        'All records and game counts will be deleted. This cannot be undone.',
      );
  String get resetSettings => _t('Khôi phục mặc định', 'Reset to defaults');
  String get resetSettingsConfirm => _t(
        'Mọi tuỳ chọn trở về mặc định. Thành tích được giữ nguyên.',
        'All options return to their defaults. Your statistics are kept.',
      );
  String get done => _t('Đã xong', 'Done');

  String get sectionAbout => _t('Giới thiệu', 'About');
  String get version => _t('Phiên bản', 'Version');
  String get credits => _t('Bản quyền icon', 'Icon credits');
  String get creditsBody => _t(
        'Icon lá bài: Fluent Emoji của Microsoft, giấy phép MIT.',
        'Card icons: Fluent Emoji by Microsoft, MIT License.',
      );
}
