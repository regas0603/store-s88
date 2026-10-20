import 'package:flutter/widgets.dart';

import '../game/models/game_config.dart';
import '../game/models/guess.dart';

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
  String get appName => _t('Đoán Số', 'Number Guess');
  String get tagline =>
      _t('Máy giấu số. Bạn đoán ra.', 'A secret number. You find it.');
  String get cancel => _t('Huỷ', 'Cancel');
  String get confirm => _t('Đồng ý', 'Confirm');
  String get close => _t('Đóng', 'Close');
  String get back => _t('Quay lại', 'Back');

  // -------------------------------------------------------------- tutorial
  String get skip => _t('Bỏ qua', 'Skip');
  String get next => _t('Tiếp', 'Next');
  String get startPlaying => _t('Bắt đầu chơi', 'Start playing');

  String get tutorial1Title => _t('Một con số được giấu', 'A hidden number');
  String get tutorial1Body => _t(
        'Máy bốc ngẫu nhiên một số trong khoảng bạn chọn — ví dụ 1 đến 100 — rồi giấu đi. Việc của bạn là tìm ra nó.',
        'The app picks a random number inside the range you choose — say 1 to 100 — and hides it. Your job is to find it.',
      );

  String get tutorial2Title => _t('Cao hơn hay thấp hơn', 'Higher or lower');
  String get tutorial2Body => _t(
        'Mỗi lần đoán, máy chỉ nói số bí mật CAO HƠN hay THẤP HƠN số bạn vừa nhập. Chỉ vậy thôi là đủ để thu hẹp dần.',
        'After each guess the app tells you whether the secret is HIGHER or LOWER than what you typed. That alone is enough to close in.',
      );

  String get tutorial3Title => _t('Cứ chia đôi mà đi', 'Just halve it');
  String get tutorial3Body => _t(
        'Mẹo: luôn đoán giữa khoảng còn lại. Với 1–100 thì bắt đầu từ 50, mỗi lần đoán cắt một nửa, bảy lượt là chắc chắn ra.',
        'Tip: always guess the middle of what is left. With 1–100, start at 50; each guess halves the range, so seven guesses always get there.',
      );

  String get tutorial4Title => _t('Hai cách chơi', 'Two ways to play');
  String get tutorial4Body => _t(
        'Chơi đơn để phá kỷ lục của chính mình. Hoặc hai người một máy: một người chọn số, người kia đoán, rồi đổi vai — ai ít lượt hơn thì thắng.',
        'Play solo to beat your own record. Or pass one phone around: one player picks the number, the other guesses, then you swap — fewest guesses wins.',
      );

  // ------------------------------------------------------------------ menu
  String get modeSolo => _t('Chơi một mình', 'Solo');
  String get modeSoloHint => _t('Máy giấu số', 'The app hides a number');
  String get modeDuel => _t('Hai người chơi', 'Two players');
  String get modeDuelHint => _t('Chọn xong rồi đoán', 'Pick, then guess');
  String get modeSurvival => _t('Sinh tồn', 'Survival');
  String get modeSurvivalHint =>
      _t('Mỗi vòng một ít lượt hơn', 'Fewer guesses every round');
  String get settings => _t('Cài đặt', 'Settings');
  String get howToPlay => _t('Hướng dẫn chơi', 'How to play');
  String get gamesPlayed => _t('Ván đã chơi', 'Games played');
  String get solvedRatio => _t('Đoán ra', 'Solved');

  // ------------------------------------------------------------ thiết lập ván
  String get newGame => _t('Ván mới', 'New game');
  String get rangeLabel => _t('Khoảng số', 'Number range');
  String get difficultyLabel => _t('Độ khó', 'Difficulty');
  String get start => _t('Bắt đầu', 'Start');

  String rangeName(GuessRange range) {
    switch (range) {
      case GuessRange.tiny:
        return _t('Nhỏ', 'Small');
      case GuessRange.small:
        return _t('Vừa', 'Medium');
      case GuessRange.big:
        return _t('Lớn', 'Large');
      case GuessRange.huge:
        return _t('Siêu lớn', 'Huge');
    }
  }

  String rangeSpan(GuessRange range) => '${range.min}–${range.max}';

  String difficultyName(GuessDifficulty level) {
    switch (level) {
      case GuessDifficulty.normal:
        return _t('Thường', 'Normal');
      case GuessDifficulty.hard:
        return _t('Khó', 'Hard');
    }
  }

  String difficultyDetail(GuessDifficulty level, GuessRange range) {
    final n = level.maxGuessesFor(range);
    switch (level) {
      case GuessDifficulty.normal:
        return _t(
          '$n lượt đoán, có gợi ý nóng/lạnh',
          '$n guesses, with hot/cold hints',
        );
      case GuessDifficulty.hard:
        return _t(
          'Chỉ $n lượt, không có nóng/lạnh',
          'Only $n guesses, no hot/cold',
        );
    }
  }

  // ------------------------------------------------------------------ ván chơi
  String get you => _t('Bạn', 'You');
  String get player1 => _t('Người 1', 'Player 1');
  String get player2 => _t('Người 2', 'Player 2');

  String get guessesUsed => _t('Đã đoán', 'Guesses');
  String get guessesLeft => _t('Còn lại', 'Left');
  String get time => _t('Thời gian', 'Time');
  String get yourGuess => _t('Số bạn đoán', 'Your guess');
  String get submitGuess => _t('Đoán', 'Guess');
  String get clear => _t('Xoá', 'Clear');

  String rangeStillPossible(int low, int high) =>
      _t('Số nằm trong $low…$high', 'The number is in $low…$high');

  String get hintHigher => _t('CAO HƠN', 'HIGHER');
  String get hintLower => _t('THẤP HƠN', 'LOWER');
  String get hintCorrect => _t('CHÍNH XÁC!', 'SPOT ON!');
  String get hintStart =>
      _t('Nhập một số để bắt đầu', 'Type a number to start');

  String hintHigherThan(int value) =>
      _t('Số bí mật lớn hơn $value', 'The secret is bigger than $value');
  String hintLowerThan(int value) =>
      _t('Số bí mật nhỏ hơn $value', 'The secret is smaller than $value');

  String heatName(GuessHeat heat) {
    switch (heat) {
      case GuessHeat.none:
        return '';
      case GuessHeat.freezing:
        return _t('Rất xa', 'Freezing');
      case GuessHeat.cold:
        return _t('Xa', 'Cold');
      case GuessHeat.warm:
        return _t('Gần rồi', 'Warm');
      case GuessHeat.hot:
        return _t('Rất gần!', 'Hot!');
    }
  }

  String get outOfRangeWarning =>
      _t('Số ngoài khoảng cho phép', 'That number is outside the range');
  String get duplicateWarning =>
      _t('Bạn đã đoán số này rồi', 'You already guessed that one');

  String get history => _t('Các lần đoán', 'Your guesses');
  String get noGuessesYet => _t('Chưa đoán lần nào', 'No guesses yet');

  // ------------------------------------------------- chế độ 2 người: chọn số
  String setSecretTitle(String name) =>
      _t('$name chọn số bí mật', '$name picks the secret');
  String setSecretBody(int min, int max, String guesser) => _t(
        'Nhập một số từ $min đến $max rồi đưa máy cho $guesser. Số sẽ được che đi khi bạn bấm xác nhận.',
        'Type a number from $min to $max, then hand the phone to $guesser. It gets hidden as soon as you confirm.',
      );
  String get secretHidden => _t('Đã che', 'Hidden');
  String get revealSecret => _t('Xem lại', 'Peek');
  String get confirmSecret => _t('Xác nhận số này', 'Lock it in');

  String handoffTitle(String name) =>
      _t('Đưa máy cho $name', 'Pass the phone to $name');
  String get handoffBody => _t(
        'Người vừa chọn số đừng nhìn màn hình nữa nhé.',
        'Whoever picked the number, look away now.',
      );
  String get handoffSkip => _t('Tôi sẵn sàng', "I'm ready");

  String turnOf(String name) => _t('Lượt của $name', "$name's turn");
  String legOf(int leg) => _t('Lượt $leg/2', 'Round $leg of 2');

  // ------------------------------------------------------------- sinh tồn
  String survivalRound(int round) => _t('Vòng $round', 'Round $round');
  String get survivalCleared => _t('Qua vòng!', 'Round cleared!');
  String survivalNextRound(int round, int guesses) => _t(
        'Vòng $round — còn $guesses lượt',
        'Round $round — $guesses guesses',
      );
  String get survivalAtFloor => _t(
        'Từ đây mỗi vòng đều đòi chia đôi hoàn hảo.',
        'From here, every round needs perfect halving.',
      );
  String get survivalContinue => _t('Vào vòng tiếp', 'Next round');
  String survivalSetupDetail(int start, int floor, int floorRound) => _t(
        'Bắt đầu với $start lượt, mỗi vòng bớt 1, dừng ở $floor lượt từ vòng '
            '$floorRound. Hết lượt là kết thúc.',
        'Start with $start guesses, one fewer each round, bottoming out at '
            '$floor from round $floorRound. Run out and the run ends.',
      );

  // ------------------------------------------------------------------ tạm dừng
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
  String get resultSolved => _t('Đoán ra rồi!', 'You got it!');
  String get resultFailed => _t('Hết lượt mất rồi', 'Out of guesses');
  String resultPlayerWins(String name) => _t('$name thắng!', '$name wins!');
  String get resultDraw => _t('Hoà', 'Draw');
  String secretWas(int value) =>
      _t('Số bí mật là $value', 'The secret was $value');
  String get newRecord => _t('Kỷ lục mới!', 'New record!');
  String get bestTime => _t('Thời gian tốt nhất', 'Best time');
  String get bestGuesses => _t('Ít lượt nhất', 'Fewest guesses');
  String get bestStreak => _t('Chuỗi dài nhất', 'Longest run');
  String get survivalResultTitle => _t('Hết lượt', 'Run over');
  String get survivalResultNone =>
      _t('Chưa qua vòng nào', 'No rounds cleared');
  String survivalRoundsCleared(int n) => _t(
        n == 1 ? 'Qua 1 vòng' : 'Qua $n vòng',
        n == 1 ? '1 round cleared' : '$n rounds cleared',
      );
  String survivalDiedOnRound(int round) =>
      _t('Dừng ở vòng $round', 'Stopped on round $round');
  String get playAgain => _t('Chơi ván nữa', 'Play again');
  String get backToMenu => _t('Về sảnh', 'Back to menu');
  String guessCount(int n) => _t('$n lượt', n == 1 ? '1 guess' : '$n guesses');
  String get didNotSolve => _t('Không ra', 'Not solved');

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
  String get showRangeHint => _t('Hiện khoảng còn lại', 'Show remaining range');
  String get showRangeHintHint => _t(
        'App tự thu hẹp "số nằm trong 42…67" sau mỗi gợi ý. Tắt đi nếu bạn thích tự nhẩm.',
        'The app narrows "the number is in 42…67" for you. Turn it off to do the bookkeeping yourself.',
      );

  String get sectionGameplay => _t('Lối chơi', 'Gameplay');
  String get handoffSeconds => _t('Đếm ngược chuyền máy', 'Hand-off countdown');
  String get handoffSecondsHint => _t(
        'Số giây chờ khi đưa máy cho người kia ở chế độ 2 người.',
        'Seconds to wait while passing the phone in two-player mode.',
      );
  String secondsValue(int value) => _t('$value giây', '${value}s');

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
}
