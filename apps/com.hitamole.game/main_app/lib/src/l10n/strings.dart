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
  String get appName => 'Hit a Mole';
  String get tagline => _t('Đập chuột chũi. Luyện phản xạ.',
      'Hit the moles. Train your reflexes.');
  String get cancel => _t('Huỷ', 'Cancel');
  String get confirm => _t('Đồng ý', 'Confirm');
  String get close => _t('Đóng', 'Close');
  String get back => _t('Quay lại', 'Back');

  // -------------------------------------------------------------- tutorial
  String get skip => _t('Bỏ qua', 'Skip');
  String get next => _t('Tiếp', 'Next');
  String get startPlaying => _t('Bắt đầu chơi', 'Start playing');

  String get tutorial1Title => _t('Chuột chũi trồi lên', 'Moles pop up');
  String get tutorial1Body => _t(
        'Chuột chũi sẽ ló đầu khỏi hang trong chốc lát. Chạm thật nhanh vào con nào vừa trồi lên.',
        'Moles peek out of their holes for just a moment. Tap one as soon as it pops up.',
      );

  String get tutorial2Title => _t('Đập trúng là ghi điểm', 'Bonk to score');
  String get tutorial2Body => _t(
        'Mỗi con đập trúng được một điểm. Chậm tay thì nó chui mất, còn đập vào hang trống vẫn bị tính một cú đập.',
        'Every mole you bonk is a point. Too slow and it escapes, and tapping an empty hole still counts as a tap.',
      );

  String get tutorialTrapTitle => _t('Cẩn thận bom bẫy', 'Watch out for bombs');
  String get tutorialTrapBody => _t(
        'Ở độ khó Khó, bom sẽ trồi lên xen kẽ với chuột chũi. Đừng chạm vào bom: đập nhầm sẽ bị trừ 1 điểm. Cứ để bom tự thụt xuống là an toàn.',
        'On Hard, bombs pop up between the moles. Don\'t touch them: hitting one costs you a point. Just let a bomb sink back down and you\'re safe.',
      );

  String get tutorial3Title => _t('Càng về sau càng nhanh', 'It gets faster');
  String get tutorial3Body => _t(
        'Về cuối ván chuột chũi thụt xuống nhanh hơn. Đấu máy thì hai bên tranh nhau trên cùng một bàn, còn chơi hai người thì lần lượt mỗi người một lượt.',
        'Moles hide faster toward the end. Against the AI you race on the same board; with two players you take turns.',
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
  String get aiSkillLabel => _t('Trình độ AI', 'AI skill');
  String get characterLabel => _t('Nhân vật', 'Characters');
  String get classicMole => _t('Chuột chũi', 'Classic mole');
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
      '${size.columns}×${size.rows} · ${size.moleCount} ${_t('con', 'moles')}';

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
        return _t('AI chậm tay, hay bỏ lỡ', 'The AI is slow and misses a lot');
      case AiDifficulty.normal:
        return _t('AI phản xạ khá nhanh', 'The AI has decent reflexes');
      case AiDifficulty.hard:
        return _t('AI nhanh như chớp', 'The AI is lightning fast');
    }
  }

  String get boardDifficultyLabel =>
      _t('Độ khó (bom bẫy)', 'Difficulty (bombs)');

  String boardDifficultyName(BoardDifficulty level) {
    switch (level) {
      case BoardDifficulty.normal:
        return _t('Bình thường', 'Normal');
      case BoardDifficulty.hard:
        return _t('Khó', 'Hard');
    }
  }

  String boardDifficultyDetail(BoardDifficulty level) {
    switch (level) {
      case BoardDifficulty.normal:
        return _t('Chỉ có chuột chũi', 'Only moles');
      case BoardDifficulty.hard:
        return _t(
          'Có bom bẫy trồi lên xen kẽ — đập nhầm bị trừ 1 điểm',
          'Bombs pop up between moles — hitting one costs a point',
        );
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
  String turnOf(String name) => _t('Lượt của $name', "$name's turn");
  String get getReady => _t('Chuẩn bị!', 'Get ready!');
  String getReadyPlayer(String name) =>
      _t('$name chuẩn bị!', '$name, get ready!');
  String get whackThem => _t('Đập nhanh lên!', 'Hit them!');
  String get beatTheAiTraps =>
      _t('Nhanh tay hơn máy, né bom!', 'Beat the AI, dodge the bombs!');
  String get dodgeBombs => _t('Né bom!', 'Dodge bombs!');
  String get avoidTraps =>
      _t('Đập chuột, né bom!', 'Hit moles, dodge bombs!');
  String get trapsHit => _t('Dính bom', 'Bombs hit');
  String get beatTheAi => _t('Nhanh tay hơn máy!', 'Beat the AI to it!');
  String get moves => _t('Lượt đập', 'Taps');
  String get time => _t('Thời gian', 'Time');
  String get molesLeft => _t('Còn lại', 'Left');
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
  String get bestMoves => _t('Ít lượt đập nhất', 'Fewest taps');
  String get playAgain => _t('Chơi ván nữa', 'Play again');
  String get backToMenu => _t('Về sảnh', 'Back to menu');

  // ------------------------------------------------------------------ cài đặt
  String get sectionAudio => _t('Âm thanh', 'Audio');
  String get sfx => _t('Hiệu ứng âm thanh', 'Sound effects');
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
  String get countdownSeconds => _t('Đếm ngược', 'Countdown');
  String get countdownSecondsHint => _t(
        'Số giây chuẩn bị trước khi chuột chũi bắt đầu trồi lên.',
        'Seconds to get ready before the moles start popping up.',
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
        'Icon nhân vật: Fluent Emoji của Microsoft, giấy phép MIT.',
        'Character icons: Fluent Emoji by Microsoft, MIT License.',
      );
}
