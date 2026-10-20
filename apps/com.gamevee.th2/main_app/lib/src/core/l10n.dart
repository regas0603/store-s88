import 'app_settings.dart';
import 'game_history.dart';

class L10n {
  static final L10n _i = L10n._();
  factory L10n() => _i;
  L10n._();

  AppLanguage _lang = AppLanguage.vietnamese;
  void setLanguage(AppLanguage l) => _lang = l;

  static const Map<String, Map<String, String>> _strings = {
    // ── App ──
    'appTitle': {
      'vi': 'CARO',
      'en': 'CARO',
      'ja': '五目並べ',
      'zh': '五子棋',
    },
    'tagline': {
      'vi': 'CARO CLASSIC',
      'en': 'CARO CLASSIC',
      'ja': 'クラシック五目並べ',
      'zh': '经典五子棋',
    },
    // ── Home ──
    'twoPlayers': {
      'vi': 'HAI NGƯỜI CHƠI',
      'en': 'TWO PLAYERS',
      'ja': '二人プレイ',
      'zh': '双人游戏',
    },
    'twoPlayersSub': {
      'vi': 'Chơi cùng bạn bè',
      'en': 'Play with a friend',
      'ja': '友達と遊ぶ',
      'zh': '和朋友一起玩',
    },
    'vsAI': {
      'vi': 'CHƠI VỚI AI',
      'en': 'VS AI',
      'ja': 'AIと対戦',
      'zh': '对战电脑',
    },
    'vsAISub': {
      'vi': 'Thách đấu AI',
      'en': 'Challenge the AI',
      'ja': 'AIに挑戦',
      'zh': '挑战AI',
    },
    'settings': {
      'vi': 'CÀI ĐẶT',
      'en': 'SETTINGS',
      'ja': '設定',
      'zh': '设置',
    },
    'history': {
      'vi': 'LỊCH SỬ',
      'en': 'HISTORY',
      'ja': '履歴',
      'zh': '历史',
    },
    // ── Game ──
    'yourTurn': {
      'vi': 'Lượt của bạn (X)',
      'en': 'Your turn (X)',
      'ja': 'あなたの番 (X)',
      'zh': '你的回合 (X)',
    },
    'aiThinking': {
      'vi': 'Máy đang suy nghĩ...',
      'en': 'AI is thinking...',
      'ja': 'AIが考えています...',
      'zh': '电脑思考中...',
    },
    'turnX': {
      'vi': 'Lượt của X',
      'en': 'X\'s turn',
      'ja': 'Xの番',
      'zh': 'X的回合',
    },
    'turnO': {
      'vi': 'Lượt của O',
      'en': 'O\'s turn',
      'ja': 'Oの番',
      'zh': 'O的回合',
    },
    'youWin': {
      'vi': 'Bạn thắng!',
      'en': 'You win!',
      'ja': 'あなたの勝ち！',
      'zh': '你赢了！',
    },
    'aiWins': {
      'vi': 'Máy thắng!',
      'en': 'AI wins!',
      'ja': 'AIの勝ち！',
      'zh': '电脑赢了！',
    },
    'xWins': {
      'vi': 'X thắng!',
      'en': 'X wins!',
      'ja': 'Xの勝ち！',
      'zh': 'X赢了！',
    },
    'oWins': {
      'vi': 'O thắng!',
      'en': 'O wins!',
      'ja': 'Oの勝ち！',
      'zh': 'O赢了！',
    },
    'draw': {
      'vi': 'Hòa!',
      'en': 'Draw!',
      'ja': '引き分け！',
      'zh': '平局！',
    },
    'timeout': {
      'vi': 'Hết giờ!',
      'en': 'Time\'s up!',
      'ja': '時間切れ！',
      'zh': '时间到！',
    },
    'you': {
      'vi': 'BẠN (X)',
      'en': 'YOU (X)',
      'ja': 'あなた(X)',
      'zh': '你 (X)',
    },
    'ai': {
      'vi': 'MÁY (O)',
      'en': 'AI (O)',
      'ja': 'AI (O)',
      'zh': '电脑 (O)',
    },
    'draw_label': {
      'vi': 'HÒA',
      'en': 'DRAW',
      'ja': '引分',
      'zh': '平局',
    },
    // ── Settings ──
    'settingsTitle': {
      'vi': 'CÀI ĐẶT',
      'en': 'SETTINGS',
      'ja': '設定',
      'zh': '设置',
    },
    'turnTime': {
      'vi': 'Thời gian mỗi lượt',
      'en': 'Turn time limit',
      'ja': '1手の制限時間',
      'zh': '每回合时间',
    },
    'noLimit': {
      'vi': 'Không giới hạn',
      'en': 'No limit',
      'ja': '無制限',
      'zh': '无限制',
    },
    'skin': {
      'vi': 'Skin quân cờ',
      'en': 'Piece skin',
      'ja': '駒のスキン',
      'zh': '棋子外观',
    },
    'boardBackground': {
      'vi': 'Nền bàn cờ',
      'en': 'Board background',
      'ja': '盤の背景',
      'zh': '棋盘背景',
    },
    'boardSize': {
      'vi': 'Cỡ bàn cờ',
      'en': 'Board size',
      'ja': '盤のサイズ',
      'zh': '棋盘大小',
    },
    'boardPreset_n3': {
      'vi': '3×3 — 3 quân liên tiếp',
      'en': '3×3 — 3 in a row',
      'ja': '3×3 — 3連',
      'zh': '3×3 — 连三',
    },
    'boardPreset_n4': {
      'vi': '4×4 — 4 quân liên tiếp',
      'en': '4×4 — 4 in a row',
      'ja': '4×4 — 4連',
      'zh': '4×4 — 连四',
    },
    'boardPreset_n6': {
      'vi': '6×6 — 4 quân liên tiếp',
      'en': '6×6 — 4 in a row',
      'ja': '6×6 — 4連',
      'zh': '6×6 — 连四',
    },
    'boardPreset_n9': {
      'vi': '9×9 — 5 quân liên tiếp',
      'en': '9×9 — 5 in a row',
      'ja': '9×9 — 5連',
      'zh': '9×9 — 连五',
    },
    'boardPreset_n13': {
      'vi': '13×13 — 5 quân liên tiếp',
      'en': '13×13 — 5 in a row',
      'ja': '13×13 — 5連',
      'zh': '13×13 — 连五',
    },
    'boardPreset_n15': {
      'vi': '15×15 — 5 quân liên tiếp',
      'en': '15×15 — 5 in a row',
      'ja': '15×15 — 5連',
      'zh': '15×15 — 连五',
    },
    'skin_neon': {
      'vi': 'Neon',
      'en': 'Neon',
      'ja': 'ネオン',
      'zh': '霓虹',
    },
    'skin_fire': {
      'vi': 'Lửa',
      'en': 'Fire',
      'ja': '炎',
      'zh': '火焰',
    },
    'skin_forest': {
      'vi': 'Rừng',
      'en': 'Forest',
      'ja': '森',
      'zh': '森林',
    },
    'skin_royal': {
      'vi': 'Hoàng gia',
      'en': 'Royal',
      'ja': 'ロイヤル',
      'zh': '皇家',
    },
    'skin_mono': {
      'vi': 'Mono',
      'en': 'Mono',
      'ja': 'モノクロ',
      'zh': '单色',
    },
    'board_midnight': {
      'vi': 'Đêm',
      'en': 'Midnight',
      'ja': '夜',
      'zh': '午夜',
    },
    'board_ocean': {
      'vi': 'Đại dương',
      'en': 'Ocean',
      'ja': '海',
      'zh': '海洋',
    },
    'board_deepForest': {
      'vi': 'Rừng sâu',
      'en': 'Deep forest',
      'ja': '深い森',
      'zh': '深林',
    },
    'board_sunset': {
      'vi': 'Hoàng hôn',
      'en': 'Sunset',
      'ja': '夕焼け',
      'zh': '日落',
    },
    'board_wood': {
      'vi': 'Gỗ cổ',
      'en': 'Wood',
      'ja': '木目',
      'zh': '木纹',
    },
    'board_charcoal': {
      'vi': 'Than',
      'en': 'Charcoal',
      'ja': 'チャコール',
      'zh': '炭灰',
    },
    'language': {
      'vi': 'Ngôn ngữ',
      'en': 'Language',
      'ja': '言語',
      'zh': '语言',
    },
    'sound': {
      'vi': 'Âm thanh',
      'en': 'Sound',
      'ja': 'サウンド',
      'zh': '声音',
    },
    'soundOn': {
      'vi': 'Bật',
      'en': 'On',
      'ja': 'オン',
      'zh': '开启',
    },
    'soundOff': {
      'vi': 'Tắt',
      'en': 'Off',
      'ja': 'オフ',
      'zh': '关闭',
    },
    'resumeTitle': {
      'vi': 'Tiếp tục ván đang chơi?',
      'en': 'Resume game in progress?',
      'ja': '進行中のゲームを再開しますか？',
      'zh': '继续未完成的对局？',
    },
    'resumeBody': {
      'vi': 'Bạn có một ván chưa kết thúc. Muốn chơi tiếp hay bắt đầu ván mới?',
      'en': 'You have an unfinished game. Continue or start fresh?',
      'ja': '未完了のゲームがあります。続けますか、それとも新しいゲームを始めますか？',
      'zh': '您有一局未完成。继续还是开新局？',
    },
    'resumeMode': {
      'vi': 'Chế độ',
      'en': 'Mode',
      'ja': 'モード',
      'zh': '模式',
    },
    'resumeBoard': {
      'vi': 'Bàn cờ',
      'en': 'Board',
      'ja': '盤面',
      'zh': '棋盘',
    },
    'resumeMoves': {
      'vi': 'Số nước đã đi',
      'en': 'Moves played',
      'ja': '打った手数',
      'zh': '已走步数',
    },
    'resumeContinue': {
      'vi': 'Tiếp tục',
      'en': 'Continue',
      'ja': '続ける',
      'zh': '继续',
    },
    'resumeDiscard': {
      'vi': 'Bỏ ván',
      'en': 'Discard',
      'ja': '破棄',
      'zh': '放弃',
    },
    'resumeOtherModeTitle': {
      'vi': 'Có ván đang chơi dở',
      'en': 'You have a game in progress',
      'ja': '進行中のゲームがあります',
      'zh': '您有一局正在进行',
    },
    'resumeOtherModeBody': {
      'vi': 'Ván đang chơi là chế độ khác. Bắt đầu ván mới sẽ xóa ván đó.',
      'en': 'Your current game is in a different mode. Starting a new game will discard it.',
      'ja': '進行中のゲームは別のモードです。新しいゲームを始めると破棄されます。',
      'zh': '当前对局是其他模式。开始新对局将放弃旧对局。',
    },
    'resumeDiscardAndStart': {
      'vi': 'Bỏ và bắt đầu',
      'en': 'Discard & start',
      'ja': '破棄して開始',
      'zh': '放弃并开始',
    },
    'cancel': {
      'vi': 'Huỷ',
      'en': 'Cancel',
      'ja': 'キャンセル',
      'zh': '取消',
    },
    'close': {
      'vi': 'Đóng',
      'en': 'Close',
      'ja': '閉じる',
      'zh': '关闭',
    },
    // ── Achievements (US-004) ──
    'achievementsTitle': {
      'vi': 'Huy hiệu',
      'en': 'Achievements',
      'ja': '実績',
      'zh': '成就',
    },
    'badgeProgress': {
      'vi': 'Tiến độ',
      'en': 'Progress',
      'ja': '進捗',
      'zh': '进度',
    },
    'badgeUnlockedTitle': {
      'vi': 'HUY HIỆU MỚI',
      'en': 'NEW ACHIEVEMENT',
      'ja': '新しい実績',
      'zh': '新成就',
    },
    'badgeUnlockedOn': {
      'vi': 'Đạt ngày',
      'en': 'Unlocked on',
      'ja': '解除日',
      'zh': '解锁日期',
    },
    // Badge definitions — mỗi badge có 2 key: _name và _desc
    'badge_firstGame_name': {
      'vi': 'Khởi đầu',
      'en': 'First Game',
      'ja': '最初の一歩',
      'zh': '第一局',
    },
    'badge_firstGame_desc': {
      'vi': 'Chơi ván đầu tiên.',
      'en': 'Play your first game.',
      'ja': '初めてゲームをプレイ。',
      'zh': '完成第一局游戏。',
    },
    'badge_win10_name': {
      'vi': '10 chiến thắng',
      'en': '10 Wins',
      'ja': '10勝',
      'zh': '10 胜',
    },
    'badge_win10_desc': {
      'vi': 'Thắng 10 ván.',
      'en': 'Win 10 games.',
      'ja': '10ゲームに勝利。',
      'zh': '赢得 10 局。',
    },
    'badge_win50_name': {
      'vi': '50 chiến thắng',
      'en': '50 Wins',
      'ja': '50勝',
      'zh': '50 胜',
    },
    'badge_win50_desc': {
      'vi': 'Thắng 50 ván.',
      'en': 'Win 50 games.',
      'ja': '50ゲームに勝利。',
      'zh': '赢得 50 局。',
    },
    'badge_win100_name': {
      'vi': '100 chiến thắng',
      'en': '100 Wins',
      'ja': '100勝',
      'zh': '100 胜',
    },
    'badge_win100_desc': {
      'vi': 'Thắng 100 ván.',
      'en': 'Win 100 games.',
      'ja': '100ゲームに勝利。',
      'zh': '赢得 100 局。',
    },
    'badge_streak3_name': {
      'vi': '3 liên tiếp',
      'en': '3 Streak',
      'ja': '3連勝',
      'zh': '3 连胜',
    },
    'badge_streak3_desc': {
      'vi': 'Thắng 3 ván liên tiếp.',
      'en': 'Win 3 games in a row.',
      'ja': '3ゲーム連続勝利。',
      'zh': '连续赢得 3 局。',
    },
    'badge_streak7_name': {
      'vi': '7 liên tiếp',
      'en': '7 Streak',
      'ja': '7連勝',
      'zh': '7 连胜',
    },
    'badge_streak7_desc': {
      'vi': 'Thắng 7 ván liên tiếp.',
      'en': 'Win 7 games in a row.',
      'ja': '7ゲーム連続勝利。',
      'zh': '连续赢得 7 局。',
    },
    'badge_beatAiLow_name': {
      'vi': 'Hạ AI Dễ',
      'en': 'Beat AI Easy',
      'ja': 'AI 初級撃破',
      'zh': '击败初级 AI',
    },
    'badge_beatAiLow_desc': {
      'vi': 'Thắng AI độ khó Dễ.',
      'en': 'Defeat the AI on Easy.',
      'ja': 'AI初級に勝利。',
      'zh': '在初级难度击败 AI。',
    },
    'badge_beatAiMedium_name': {
      'vi': 'Hạ AI Trung',
      'en': 'Beat AI Medium',
      'ja': 'AI 中級撃破',
      'zh': '击败中级 AI',
    },
    'badge_beatAiMedium_desc': {
      'vi': 'Thắng AI độ khó Trung bình.',
      'en': 'Defeat the AI on Medium.',
      'ja': 'AI中級に勝利。',
      'zh': '在中级难度击败 AI。',
    },
    'badge_beatAiHigh_name': {
      'vi': 'Hạ AI Khó',
      'en': 'Beat AI Hard',
      'ja': 'AI 上級撃破',
      'zh': '击败高级 AI',
    },
    'badge_beatAiHigh_desc': {
      'vi': 'Thắng AI độ khó Khó.',
      'en': 'Defeat the AI on Hard.',
      'ja': 'AI上級に勝利。',
      'zh': '在高级难度击败 AI。',
    },
    'badge_played10_name': {
      'vi': 'Người chơi mới',
      'en': 'Newcomer',
      'ja': '新参者',
      'zh': '新手',
    },
    'badge_played10_desc': {
      'vi': 'Chơi 10 ván.',
      'en': 'Play 10 games.',
      'ja': '10ゲームプレイ。',
      'zh': '完成 10 局。',
    },
    'badge_played50_name': {
      'vi': 'Người chơi thân thiện',
      'en': 'Regular',
      'ja': '常連',
      'zh': '常客',
    },
    'badge_played50_desc': {
      'vi': 'Chơi 50 ván.',
      'en': 'Play 50 games.',
      'ja': '50ゲームプレイ。',
      'zh': '完成 50 局。',
    },
    'badge_fastWin_name': {
      'vi': 'Chớp nhoáng',
      'en': 'Quick Draw',
      'ja': '速攻勝利',
      'zh': '快速获胜',
    },
    'badge_fastWin_desc': {
      'vi': 'Thắng ván chỉ trong 10 nước hoặc ít hơn.',
      'en': 'Win a game in 10 moves or fewer.',
      'ja': '10手以内で勝利。',
      'zh': '10 手或更少获胜。',
    },
    'badge_blitzWin_name': {
      'vi': 'Blitz',
      'en': 'Blitz',
      'ja': 'ブリッツ',
      'zh': '闪电战',
    },
    'badge_blitzWin_desc': {
      'vi': 'Thắng ván dưới 60 giây.',
      'en': 'Win a game in under 60 seconds.',
      'ja': '60秒以内に勝利。',
      'zh': '60 秒内获胜。',
    },
    'badge_allBoardSizes_name': {
      'vi': 'Khám phá bàn cờ',
      'en': 'Board Explorer',
      'ja': '盤面探検家',
      'zh': '棋盘探索者',
    },
    'badge_allBoardSizes_desc': {
      'vi': 'Chơi ở cả 6 kích thước bàn cờ.',
      'en': 'Play all 6 board sizes.',
      'ja': '6種類すべての盤面でプレイ。',
      'zh': '在所有 6 种棋盘尺寸上游玩。',
    },
    'badge_slidingCapWinner_name': {
      'vi': 'Vua bàn nhỏ',
      'en': 'Small Board King',
      'ja': '小盤面の王',
      'zh': '小棋盘之王',
    },
    'badge_slidingCapWinner_desc': {
      'vi': 'Thắng trên bàn 3×3 hoặc 4×4.',
      'en': 'Win on a 3×3 or 4×4 board.',
      'ja': '3×3または4×4で勝利。',
      'zh': '在 3×3 或 4×4 棋盘上获胜。',
    },
    'badge_bigBoardWinner_name': {
      'vi': 'Vua bàn lớn',
      'en': 'Big Board Ace',
      'ja': '大盤面の達人',
      'zh': '大棋盘达人',
    },
    'badge_bigBoardWinner_desc': {
      'vi': 'Thắng trên bàn 13×13 hoặc 15×15.',
      'en': 'Win on a 13×13 or 15×15 board.',
      'ja': '13×13または15×15で勝利。',
      'zh': '在 13×13 或 15×15 棋盘上获胜。',
    },
    'badge_modeVariety_name': {
      'vi': 'Đa năng',
      'en': 'Versatile',
      'ja': '多才',
      'zh': '多面手',
    },
    'badge_modeVariety_desc': {
      'vi': 'Chơi cả 2 chế độ PvP và vs AI.',
      'en': 'Play both PvP and vs AI modes.',
      'ja': 'PvPとAI対戦の両方をプレイ。',
      'zh': '玩过 PvP 和 AI 对战模式。',
    },
    'badge_skinExplorer_name': {
      'vi': 'Nhà sưu tập skin',
      'en': 'Skin Collector',
      'ja': 'スキンコレクター',
      'zh': '皮肤收藏家',
    },
    'badge_skinExplorer_desc': {
      'vi': 'Chơi với 3 skin trở lên.',
      'en': 'Play with 3 or more skins.',
      'ja': '3種類以上のスキンでプレイ。',
      'zh': '使用 3 种或更多皮肤。',
    },
    'aiDifficulty': {
      'vi': 'Độ khó AI',
      'en': 'AI difficulty',
      'ja': 'AIの難易度',
      'zh': 'AI 难度',
    },
    'aiDifficultyLow': {
      'vi': 'Dễ',
      'en': 'Easy',
      'ja': 'かんたん',
      'zh': '简单',
    },
    'aiDifficultyMedium': {
      'vi': 'Trung bình',
      'en': 'Normal',
      'ja': 'ふつう',
      'zh': '普通',
    },
    'aiDifficultyHigh': {
      'vi': 'Khó',
      'en': 'Hard',
      'ja': 'むずかしい',
      'zh': '困难',
    },
    // ── History ──
    'historyTitle': {
      'vi': 'LỊCH SỬ VÁN ĐẤU',
      'en': 'GAME HISTORY',
      'ja': '対局履歴',
      'zh': '对局历史',
    },
    'noHistory': {
      'vi': 'Chưa có ván đấu nào',
      'en': 'No games played yet',
      'ja': 'まだ対局がありません',
      'zh': '还没有对局记录',
    },
    'clearHistory': {
      'vi': 'Xóa lịch sử',
      'en': 'Clear history',
      'ja': '履歴をクリア',
      'zh': '清除历史',
    },
    'moves': {
      'vi': 'nước',
      'en': 'moves',
      'ja': '手',
      'zh': '步',
    },
    // Short marks for history / result badge (no emoji; safe fonts).
    'resultMarkX': {
      'vi': 'X',
      'en': 'X',
      'ja': 'X',
      'zh': 'X',
    },
    'resultMarkO': {
      'vi': 'O',
      'en': 'O',
      'ja': 'O',
      'zh': 'O',
    },
    'resultMarkDraw': {
      'vi': '=',
      'en': '=',
      'ja': '分',
      'zh': '平',
    },
    'resultMarkTimeout': {
      'vi': 'T',
      'en': 'T',
      'ja': '時',
      'zh': '时',
    },
    // ── Result ──
    'playAgain': {
      'vi': 'CHƠI LẠI',
      'en': 'PLAY AGAIN',
      'ja': 'もう一度',
      'zh': '再来一局',
    },
    'backHome': {
      'vi': 'VỀ TRANG CHỦ',
      'en': 'HOME',
      'ja': 'ホーム',
      'zh': '回主页',
    },
    'winner': {
      'vi': 'NGƯỜI CHIẾN THẮNG',
      'en': 'WINNER',
      'ja': '勝者',
      'zh': '获胜者',
    },
    'totalMoves': {
      'vi': 'Tổng số nước',
      'en': 'Total moves',
      'ja': '総手数',
      'zh': '总步数',
    },
    'duration': {
      'vi': 'Thời gian',
      'en': 'Duration',
      'ja': '対局時間',
      'zh': '时长',
    },

    // ── Onboarding ──
    'onboarding_skip': {
      'vi': 'Bỏ qua',
      'en': 'Skip',
      'ja': 'スキップ',
      'zh': '跳过',
    },
    'onboarding_next': {
      'vi': 'Tiếp tục',
      'en': 'Next',
      'ja': '次へ',
      'zh': '下一步',
    },
    'onboarding_start': {
      'vi': 'Bắt đầu chơi',
      'en': 'Get Started',
      'ja': 'はじめる',
      'zh': '开始',
    },
    'onboarding_title1': {
      'vi': 'Chào mừng đến Caro!',
      'en': 'Welcome to Caro!',
      'ja': '五目並べへようこそ',
      'zh': '欢迎来到五子棋',
    },
    'onboarding_body1': {
      'vi': 'Trò chơi cờ caro cổ điển với giao diện hiện đại. Chơi cùng bạn bè hoặc thử thách AI.',
      'en': 'Classic Caro (Gomoku) with a modern look. Play with a friend or challenge the AI.',
      'ja': '懐かしの五目並べをモダンなUIで。友達と対戦したり、AIに挑戦しよう。',
      'zh': '经典五子棋的现代演绎。与朋友对战或挑战AI。',
    },
    'onboarding_title2': {
      'vi': 'Hai chế độ chơi',
      'en': 'Two game modes',
      'ja': '2つのモード',
      'zh': '两种模式',
    },
    'onboarding_body2': {
      'vi': 'Hai người chơi thay phiên trên cùng một máy, hoặc đối đầu với AI với 3 mức độ khó.',
      'en': 'Two players take turns on one device, or face an AI with 3 difficulty levels.',
      'ja': '1台で2人対戦、または3段階の難易度のAIと対戦できます。',
      'zh': '双人同机对战，或挑战三种难度的AI。',
    },
    'onboarding_title3': {
      'vi': 'Luật thắng linh hoạt',
      'en': 'Flexible win rules',
      'ja': '柔軟な勝利条件',
      'zh': '灵活的胜负规则',
    },
    'onboarding_body3': {
      'vi': 'Bàn 3×3 thắng khi 3 liên tiếp, 4×4 cần 4, 6×6 trở lên cần 4–5. Bàn nhỏ còn có luật gỡ quân cũ.',
      'en': '3×3 wins with 3 in a row, 4×4 needs 4, and 6×6+ needs 4–5. Smaller boards add a sliding-cap rule.',
      'ja': '3×3は3連、4×4は4連、6×6以上は4–5連で勝利。小盤面では古い駒が取り除かれるルールも。',
      'zh': '3×3需3连,4×4需4连,6×6以上需4–5连。小棋盘还有移除旧子的规则。',
    },

    // ── Statistics ──
    'statisticsTitle': {
      'vi': 'Thống kê',
      'en': 'Statistics',
      'ja': '統計',
      'zh': '统计',
    },
    'stat_totalGames': {
      'vi': 'Tổng số ván',
      'en': 'Total games',
      'ja': '総対局数',
      'zh': '总局数',
    },
    'stat_wins': {
      'vi': 'Thắng',
      'en': 'Wins',
      'ja': '勝利',
      'zh': '胜',
    },
    'stat_losses': {
      'vi': 'Thua',
      'en': 'Losses',
      'ja': '敗北',
      'zh': '负',
    },
    'stat_draws': {
      'vi': 'Hòa',
      'en': 'Draws',
      'ja': '引き分け',
      'zh': '和',
    },
    'stat_winRate': {
      'vi': 'Tỉ lệ thắng',
      'en': 'Win rate',
      'ja': '勝率',
      'zh': '胜率',
    },
    'stat_bestStreak': {
      'vi': 'Chuỗi thắng dài nhất',
      'en': 'Longest win streak',
      'ja': '最長連勝',
      'zh': '最长连胜',
    },
    'stat_totalPlayTime': {
      'vi': 'Tổng thời gian chơi',
      'en': 'Total play time',
      'ja': '総プレイ時間',
      'zh': '总游戏时间',
    },
    'stat_byMode': {
      'vi': 'Theo chế độ',
      'en': 'By mode',
      'ja': 'モード別',
      'zh': '按模式',
    },
    'stat_byDifficulty': {
      'vi': 'Theo độ khó AI',
      'en': 'By AI difficulty',
      'ja': 'AI難易度別',
      'zh': '按AI难度',
    },
    'stat_noData': {
      'vi': 'Chưa có dữ liệu. Hãy chơi vài ván để xem thống kê.',
      'en': 'No data yet. Play a few games to see your stats.',
      'ja': 'データがありません。まず何局か対局してください。',
      'zh': '还没有数据。先对几局吧。',
    },

    // ── Replay ──
    'replay_title': {
      'vi': 'Phát lại',
      'en': 'Replay',
      'ja': 'リプレイ',
      'zh': '回放',
    },
    'replay_play': {
      'vi': 'Phát',
      'en': 'Play',
      'ja': '再生',
      'zh': '播放',
    },
    'replay_pause': {
      'vi': 'Tạm dừng',
      'en': 'Pause',
      'ja': '一時停止',
      'zh': '暂停',
    },
    'replay_restart': {
      'vi': 'Về đầu',
      'en': 'Restart',
      'ja': '最初から',
      'zh': '重新开始',
    },
    'replay_speed': {
      'vi': 'Tốc độ',
      'en': 'Speed',
      'ja': '速度',
      'zh': '速度',
    },
    'replay_moveCounter': {
      'vi': 'Nước',
      'en': 'Move',
      'ja': '手',
      'zh': '步',
    },

    // ── Share ──
    'share_button': {
      'vi': 'Chia sẻ',
      'en': 'Share',
      'ja': '共有',
      'zh': '分享',
    },
    'share_subject': {
      'vi': 'Trận Caro của tôi',
      'en': 'My Caro match',
      'ja': '私の五目並べ対局',
      'zh': '我的五子棋对局',
    },
    'share_message_win_ai': {
      'vi': 'Tôi vừa hạ AI trong Caro Classic!',
      'en': 'I just beat the AI in Caro Classic!',
      'ja': 'Caro Classic でAIに勝ちました!',
      'zh': '我刚在Caro Classic中击败了AI!',
    },
    'share_message_lose_ai': {
      'vi': 'AI quá mạnh rồi... thử lại sau!',
      'en': 'The AI was too strong this time!',
      'ja': 'AI強すぎた…また挑戦します!',
      'zh': 'AI太强了,下次再战!',
    },
    'share_message_pvp': {
      'vi': 'Vừa có một ván Caro hay!',
      'en': 'Just had a great Caro match!',
      'ja': '白熱の五目並べでした!',
      'zh': '刚打了一局精彩的五子棋!',
    },
    'share_error': {
      'vi': 'Không thể chia sẻ, thử lại sau.',
      'en': 'Share failed, please try again.',
      'ja': '共有に失敗しました。',
      'zh': '分享失败,请重试。',
    },

    // ── Navigation extras ──
    'openStatistics': {
      'vi': 'Xem thống kê',
      'en': 'View Statistics',
      'ja': '統計を見る',
      'zh': '查看统计',
    },
    'replayGame': {
      'vi': 'Phát lại',
      'en': 'Replay',
      'ja': 'リプレイ',
      'zh': '回放',
    },

    // ── Phân tích ván đấu (US-005) ──
    'analysis_title': {
      'vi': 'PHÂN TÍCH VÁN',
      'en': 'GAME ANALYSIS',
      'ja': '対局分析',
      'zh': '对局分析',
    },
    'analysis_button': {
      'vi': 'PHÂN TÍCH VÁN',
      'en': 'ANALYSE GAME',
      'ja': '対局を分析',
      'zh': '分析对局',
    },
    'analysis_viewButton': {
      'vi': 'XEM PHÂN TÍCH',
      'en': 'VIEW ANALYSIS',
      'ja': '分析を見る',
      'zh': '查看分析',
    },
    'analysis_running': {
      'vi': 'ĐANG PHÂN TÍCH VÁN',
      'en': 'ANALYSING GAME',
      'ja': '対局を分析中',
      'zh': '正在分析对局',
    },
    'analysis_phaseDeep': {
      'vi': 'Đang kiểm tra kỹ các nước quan trọng…',
      'en': 'Taking a closer look at the key moves…',
      'ja': '重要な手を詳しく調べています…',
      'zh': '正在细查关键着法…',
    },
    'analysis_phaseFinishing': {
      'vi': 'Sắp xong…',
      'en': 'Almost done…',
      'ja': 'まもなく完了…',
      'zh': '即将完成…',
    },
    'analysis_cancel': {
      'vi': 'Huỷ',
      'en': 'Cancel',
      'ja': 'キャンセル',
      'zh': '取消',
    },
    'analysis_errorTitle': {
      'vi': 'Không phân tích được ván này',
      'en': 'Could not analyse this game',
      'ja': 'この対局を分析できませんでした',
      'zh': '无法分析这局对局',
    },
    'analysis_retry': {
      'vi': 'Thử lại',
      'en': 'Try again',
      'ja': '再試行',
      'zh': '重试',
    },
    'analysis_close': {
      'vi': 'Đóng',
      'en': 'Close',
      'ja': '閉じる',
      'zh': '关闭',
    },
    'analysis_accuracy': {
      'vi': 'ĐỘ CHÍNH XÁC',
      'en': 'ACCURACY',
      'ja': '正確度',
      'zh': '准确率',
    },
    'analysis_turningPoint': {
      'vi': 'Bước ngoặt',
      'en': 'Turning point',
      'ja': '分岐点',
      'zh': '转折点',
    },
    'analysis_analyzedAt': {
      'vi': 'Phân tích lúc',
      'en': 'Analysed at',
      'ja': '分析日時',
      'zh': '分析时间',
    },
    'analysis_shareSummary': {
      'vi': 'CHIA SẺ KẾT QUẢ PHÂN TÍCH',
      'en': 'SHARE ANALYSIS',
      'ja': '分析結果を共有',
      'zh': '分享分析结果',
    },
    'analysis_disclaimer': {
      'vi': 'Đánh giá bởi AI mức Khó — chỉ mang tính tham khảo.',
      'en': 'Evaluated by the Hard AI — for reference only.',
      'ja': '難しいレベルのAIによる評価です。参考程度にご覧ください。',
      'zh': '由「困难」级AI评估,仅供参考。',
    },
    'analysis_shallowWarning': {
      'vi': 'Phân tích nhanh — kết quả có thể kém chính xác',
      'en': 'Quick analysis — results may be less accurate',
      'ja': '簡易分析 — 精度が落ちる場合があります',
      'zh': '快速分析 — 结果可能不够准确',
    },
    'analysis_redoDeep': {
      'vi': 'Phân tích lại kỹ hơn',
      'en': 'Analyse more deeply',
      'ja': '詳しく分析し直す',
      'zh': '重新深入分析',
    },
    'analysis_tooShort': {
      'vi': 'Ván quá ngắn để phân tích',
      'en': 'This game is too short to analyse',
      'ja': 'この対局は短すぎて分析できません',
      'zh': '对局过短,无法分析',
    },
    'analysis_aiMove': {
      'vi': 'Nước của máy — không chấm điểm',
      'en': 'Computer move — not scored',
      'ja': 'コンピュータの手 — 採点対象外',
      'zh': '电脑的着法 — 不评分',
    },
    'analysis_startHint': {
      'vi': 'Kéo thanh trượt để xem từng nước',
      'en': 'Drag the slider to step through the moves',
      'ja': 'スライダーで一手ずつ確認できます',
      'zh': '拖动滑块逐手查看',
    },
    'analysis_betterMove': {
      'vi': 'Nước tốt hơn',
      'en': 'Better move',
      'ja': 'より良い手',
      'zh': '更好的着法',
    },
    'analysis_howToRead': {
      'vi': 'Cách đọc phân tích',
      'en': 'How to read this',
      'ja': '分析の見方',
      'zh': '如何看懂分析',
    },
    'analysis_gotIt': {
      'vi': 'Đã hiểu',
      'en': 'Got it',
      'ja': '了解',
      'zh': '明白了',
    },
    'analysis_timeoutNote': {
      'vi': 'Ván kết thúc do hết giờ',
      'en': 'Game ended on the clock',
      'ja': '時間切れで終了した対局',
      'zh': '因超时结束的对局',
    },
    'analysis_speed': {
      'vi': 'Tốc độ phát lại',
      'en': 'Playback speed',
      'ja': '再生速度',
      'zh': '播放速度',
    },
    'analysis_playerX': {
      'vi': 'Người X',
      'en': 'Player X',
      'ja': 'プレイヤーX',
      'zh': '玩家X',
    },
    'analysis_playerO': {
      'vi': 'Người O',
      'en': 'Player O',
      'ja': 'プレイヤーO',
      'zh': '玩家O',
    },
    'analysis_chartHelp': {
      'vi': 'Vùng phía trên đường 0 là lúc X đang thắng thế, phía dưới là O. Chạm vào biểu đồ để nhảy tới nước đó.',
      'en': 'Above the zero line means X is ahead, below means O. Tap the chart to jump to that move.',
      'ja': '0の線より上はXが優勢、下はOが優勢です。グラフをタップするとその手に移動します。',
      'zh': '零线以上表示X占优,以下表示O占优。点击图表可跳到该手。',
    },
    'analysis_betterHelp': {
      'vi': 'Vòng tím nét đứt là ô mà máy cho rằng đáng lẽ nên đánh.',
      'en': 'The dashed purple ring marks the square the engine would have played.',
      'ja': '紫の破線の円は、エンジンが指すべきだと考えたマスです。',
      'zh': '紫色虚线圆圈是引擎认为应该落子的位置。',
    },
    'quality_brilliant': {
      'vi': 'Xuất sắc',
      'en': 'Brilliant',
      'ja': '妙手',
      'zh': '妙手',
    },
    'quality_good': {
      'vi': 'Tốt',
      'en': 'Good',
      'ja': '好手',
      'zh': '好手',
    },
    'quality_inaccuracy': {
      'vi': 'Thiếu chính xác',
      'en': 'Inaccuracy',
      'ja': '不正確',
      'zh': '不精确',
    },
    'quality_mistake': {
      'vi': 'Sai lầm',
      'en': 'Mistake',
      'ja': '悪手',
      'zh': '错着',
    },
    'quality_blunder': {
      'vi': 'Thảm hoạ',
      'en': 'Blunder',
      'ja': '大悪手',
      'zh': '大错着',
    },
    'quality_brilliant_desc': {
      'vi': 'Nước duy nhất đúng trong thế cờ đó.',
      'en': 'The only move that worked in that position.',
      'ja': 'その局面で唯一の正解手。',
      'zh': '该局面下唯一正确的一手。',
    },
    'quality_good_desc': {
      'vi': 'Giữ nguyên hoặc cải thiện thế cờ.',
      'en': 'Keeps or improves your position.',
      'ja': '形勢を維持または改善する手。',
      'zh': '保持或改善了局面。',
    },
    'quality_inaccuracy_desc': {
      'vi': 'Có nước tốt hơn nhưng chưa mất gì nhiều.',
      'en': 'There was better, but nothing serious was lost.',
      'ja': 'より良い手がありましたが、大きな損はありません。',
      'zh': '有更好的选择,但损失不大。',
    },
    'quality_mistake_desc': {
      'vi': 'Đánh mất một phần thế cờ đang có.',
      'en': 'Gives away part of your position.',
      'ja': '有利な形勢の一部を手放しました。',
      'zh': '让出了部分优势。',
    },
    'quality_blunder_desc': {
      'vi': 'Đảo ngược cục diện ván đấu.',
      'en': 'Turns the game around.',
      'ja': '勝敗をひっくり返す一手。',
      'zh': '扭转了整局形势。',
    },
    'badge_perfectGame_name': {
      'vi': 'Ván hoàn hảo',
      'en': 'Perfect Game',
      'ja': '完璧な対局',
      'zh': '完美对局',
    },
    'badge_perfectGame_desc': {
      'vi': 'Thắng một ván với độ chính xác từ 95% và không mắc sai lầm nào.',
      'en': 'Win a game with 95%+ accuracy and no mistakes.',
      'ja': '正確度95%以上、ミスなしで対局を終える。',
      'zh': '以95%以上准确率且无错着完成一局。',
    },
    'badge_analyst_name': {
      'vi': 'Nhà phân tích',
      'en': 'Analyst',
      'ja': 'アナリスト',
      'zh': '分析师',
    },
    'badge_analyst_desc': {
      'vi': 'Phân tích 10 ván đấu.',
      'en': 'Analyse 10 games.',
      'ja': '10局を分析する。',
      'zh': '分析10局对局。',
    },
  };

  String get(String key) {
    return _strings[key]?[_lang.code] ?? _strings[key]?['vi'] ?? key;
  }

  /// History row: "N moves" with natural spacing (ja/zh attach the counter to the number).
  String formatHistoryMoveCount(int totalMoves) {
    switch (_lang) {
      case AppLanguage.vietnamese:
        return '$totalMoves nước';
      case AppLanguage.english:
        return '$totalMoves moves';
      case AppLanguage.japanese:
        return '$totalMoves手';
      case AppLanguage.chinese:
        return '$totalMoves步';
    }
  }

  /// Compact result glyph for list rows and result dialog (text only, no emoji).
  String resultListMark(GameResult result) {
    switch (result) {
      case GameResult.xWins:
        return get('resultMarkX');
      case GameResult.oWins:
        return get('resultMarkO');
      case GameResult.draw:
        return get('resultMarkDraw');
      case GameResult.timeout:
        return get('resultMarkTimeout');
    }
  }

  String skinLabel(PieceSkin skin) {
    switch (skin) {
      case PieceSkin.neon:
        return get('skin_neon');
      case PieceSkin.fire:
        return get('skin_fire');
      case PieceSkin.forest:
        return get('skin_forest');
      case PieceSkin.royal:
        return get('skin_royal');
      case PieceSkin.mono:
        return get('skin_mono');
    }
  }

  String boardBackgroundLabel(BoardBackground bg) {
    switch (bg) {
      case BoardBackground.midnight:
        return get('board_midnight');
      case BoardBackground.ocean:
        return get('board_ocean');
      case BoardBackground.deepForest:
        return get('board_deepForest');
      case BoardBackground.sunset:
        return get('board_sunset');
      case BoardBackground.wood:
        return get('board_wood');
      case BoardBackground.charcoal:
        return get('board_charcoal');
    }
  }

  String boardSizePresetLabel(BoardSizePreset preset) {
    switch (preset) {
      case BoardSizePreset.n3:
        return get('boardPreset_n3');
      case BoardSizePreset.n4:
        return get('boardPreset_n4');
      case BoardSizePreset.n6:
        return get('boardPreset_n6');
      case BoardSizePreset.n9:
        return get('boardPreset_n9');
      case BoardSizePreset.n13:
        return get('boardPreset_n13');
      case BoardSizePreset.n15:
        return get('boardPreset_n15');
    }
  }

  /// History row fragment: board dimensions and win rule.
  String formatHistoryBoardLine(int side, int winLength) {
    switch (_lang) {
      case AppLanguage.vietnamese:
        return '$side×$side · $winLength liên tiếp';
      case AppLanguage.english:
        return '$side×$side · $winLength in a row';
      case AppLanguage.japanese:
        return '$side×$side · $winLength連';
      case AppLanguage.chinese:
        return '$side×$side · 连$winLength';
    }
  }

  // Convenience getters
  String get appTitle => get('appTitle');
  String get tagline => get('tagline');
  String get twoPlayers => get('twoPlayers');
  String get twoPlayersSub => get('twoPlayersSub');
  String get vsAI => get('vsAI');
  String get vsAISub => get('vsAISub');
  String get settings => get('settings');
  String get history => get('history');
  String get yourTurn => get('yourTurn');
  String get aiThinking => get('aiThinking');
  String get turnX => get('turnX');
  String get turnO => get('turnO');
  String get youWin => get('youWin');
  String get aiWins => get('aiWins');
  String get xWins => get('xWins');
  String get oWins => get('oWins');
  String get draw => get('draw');
  String get timeout => get('timeout');
  String get you => get('you');
  String get ai => get('ai');
  String get drawLabel => get('draw_label');
  String get settingsTitle => get('settingsTitle');
  String get turnTime => get('turnTime');
  String get noLimit => get('noLimit');
  String get skin => get('skin');
  String get boardBackground => get('boardBackground');
  String get boardSize => get('boardSize');
  String get language => get('language');
  String get sound => get('sound');
  String get soundOn => get('soundOn');
  String get soundOff => get('soundOff');
  String get resumeTitle => get('resumeTitle');
  String get resumeBody => get('resumeBody');
  String get resumeMode => get('resumeMode');
  String get resumeBoard => get('resumeBoard');
  String get resumeMoves => get('resumeMoves');
  String get resumeContinue => get('resumeContinue');
  String get resumeDiscard => get('resumeDiscard');
  String get resumeOtherModeTitle => get('resumeOtherModeTitle');
  String get resumeOtherModeBody => get('resumeOtherModeBody');
  String get resumeDiscardAndStart => get('resumeDiscardAndStart');
  String get cancel => get('cancel');
  String get close => get('close');
  String get achievementsTitle => get('achievementsTitle');
  String get badgeProgress => get('badgeProgress');
  String get badgeUnlockedTitle => get('badgeUnlockedTitle');
  String get badgeUnlockedOn => get('badgeUnlockedOn');
  String get aiDifficulty => get('aiDifficulty');
  String get aiDifficultyLow => get('aiDifficultyLow');
  String get aiDifficultyMedium => get('aiDifficultyMedium');
  String get aiDifficultyHigh => get('aiDifficultyHigh');
  String get historyTitle => get('historyTitle');
  String get noHistory => get('noHistory');
  String get clearHistory => get('clearHistory');
  String get moves => get('moves');
  String get playAgain => get('playAgain');
  String get backHome => get('backHome');
  String get winner => get('winner');
  String get totalMoves => get('totalMoves');
  String get duration => get('duration');

  // Onboarding
  String get onboardingSkip => get('onboarding_skip');
  String get onboardingNext => get('onboarding_next');
  String get onboardingStart => get('onboarding_start');
  String get onboardingTitle1 => get('onboarding_title1');
  String get onboardingBody1 => get('onboarding_body1');
  String get onboardingTitle2 => get('onboarding_title2');
  String get onboardingBody2 => get('onboarding_body2');
  String get onboardingTitle3 => get('onboarding_title3');
  String get onboardingBody3 => get('onboarding_body3');

  // Statistics
  String get statisticsTitle => get('statisticsTitle');
  String get statTotalGames => get('stat_totalGames');
  String get statWins => get('stat_wins');
  String get statLosses => get('stat_losses');
  String get statDraws => get('stat_draws');
  String get statWinRate => get('stat_winRate');
  String get statBestStreak => get('stat_bestStreak');
  String get statTotalPlayTime => get('stat_totalPlayTime');
  String get statByMode => get('stat_byMode');
  String get statByDifficulty => get('stat_byDifficulty');
  String get statNoData => get('stat_noData');

  // Replay
  String get replayTitle => get('replay_title');
  String get replayPlay => get('replay_play');
  String get replayPause => get('replay_pause');
  String get replayRestart => get('replay_restart');
  String get replaySpeed => get('replay_speed');
  String get replayMoveCounter => get('replay_moveCounter');

  // Share
  String get shareButton => get('share_button');
  String get shareSubject => get('share_subject');
  String get shareMessageWinAi => get('share_message_win_ai');
  String get shareMessageLoseAi => get('share_message_lose_ai');
  String get shareMessagePvp => get('share_message_pvp');
  String get shareError => get('share_error');

  // Navigation extras
  String get openStatistics => get('openStatistics');
  String get replayGame => get('replayGame');

  // ── Phân tích ván đấu (US-005) ──
  String get analysisTitle => get('analysis_title');
  String get analysisButton => get('analysis_button');
  String get analysisViewButton => get('analysis_viewButton');
  String get analysisRunning => get('analysis_running');
  String get analysisPhaseDeep => get('analysis_phaseDeep');
  String get analysisPhaseFinishing => get('analysis_phaseFinishing');
  String get analysisCancel => get('analysis_cancel');
  String get analysisErrorTitle => get('analysis_errorTitle');
  String get analysisRetry => get('analysis_retry');
  String get analysisClose => get('analysis_close');
  String get analysisAccuracy => get('analysis_accuracy');
  String get analysisTurningPoint => get('analysis_turningPoint');
  String get analysisAnalyzedAt => get('analysis_analyzedAt');
  String get analysisShareSummary => get('analysis_shareSummary');
  String get analysisDisclaimer => get('analysis_disclaimer');
  String get analysisShallowWarning => get('analysis_shallowWarning');
  String get analysisRedoDeep => get('analysis_redoDeep');
  String get analysisTooShort => get('analysis_tooShort');
  String get analysisAiMove => get('analysis_aiMove');
  String get analysisStartHint => get('analysis_startHint');
  String get analysisBetterMove => get('analysis_betterMove');
  String get analysisHowToRead => get('analysis_howToRead');
  String get analysisGotIt => get('analysis_gotIt');
  String get analysisTimeoutNote => get('analysis_timeoutNote');
  String get analysisSpeed => get('analysis_speed');
  String get analysisPlayerX => get('analysis_playerX');
  String get analysisPlayerO => get('analysis_playerO');
  String get analysisChartHelp => get('analysis_chartHelp');
  String get analysisBetterHelp => get('analysis_betterHelp');

  /// Tên nhãn chất lượng. Nhận index của `MoveQuality` để l10n không phải
  /// import tầng model (tránh phụ thuộc vòng).
  String qualityName(int qualityIndex) {
    const List<String> keys = <String>[
      'quality_brilliant',
      'quality_good',
      'quality_inaccuracy',
      'quality_mistake',
      'quality_blunder',
    ];
    if (qualityIndex < 0 || qualityIndex >= keys.length) return '';
    return get(keys[qualityIndex]);
  }

  String qualityDesc(int qualityIndex) {
    const List<String> keys = <String>[
      'quality_brilliant_desc',
      'quality_good_desc',
      'quality_inaccuracy_desc',
      'quality_mistake_desc',
      'quality_blunder_desc',
    ];
    if (qualityIndex < 0 || qualityIndex >= keys.length) return '';
    return get(keys[qualityIndex]);
  }

  /// "nước 14 (H8)" — ja/zh gắn liền số với đơn vị, không có dấu cách.
  String formatAnalysisMove(int moveNumber, String coord) {
    switch (_lang) {
      case AppLanguage.vietnamese:
        return 'nước $moveNumber ($coord)';
      case AppLanguage.english:
        return 'move $moveNumber ($coord)';
      case AppLanguage.japanese:
        return '$moveNumber手目 ($coord)';
      case AppLanguage.chinese:
        return '第$moveNumber手 ($coord)';
    }
  }

  /// "Đang xem xét nước 24 / 38"
  String formatAnalysisProgress(int current, int total) {
    switch (_lang) {
      case AppLanguage.vietnamese:
        return 'Đang xem xét nước $current / $total';
      case AppLanguage.english:
        return 'Reviewing move $current / $total';
      case AppLanguage.japanese:
        return '$current / $total 手目を確認中';
      case AppLanguage.chinese:
        return '正在检查第 $current / $total 手';
    }
  }

  /// "Bước ngoặt — nước 14"
  String formatTurningPoint(int moveNumber) {
    switch (_lang) {
      case AppLanguage.vietnamese:
        return 'Bước ngoặt — nước $moveNumber';
      case AppLanguage.english:
        return 'Turning point — move $moveNumber';
      case AppLanguage.japanese:
        return '分岐点 — $moveNumber手目';
      case AppLanguage.chinese:
        return '转折点 — 第$moveNumber手';
    }
  }

  /// Dòng thêm vào nội dung chia sẻ khi ván đã được phân tích.
  String formatAccuracyLine(int accuracy) {
    switch (_lang) {
      case AppLanguage.vietnamese:
        return 'Độ chính xác: $accuracy%';
      case AppLanguage.english:
        return 'Accuracy: $accuracy%';
      case AppLanguage.japanese:
        return '正確度: $accuracy%';
      case AppLanguage.chinese:
        return '准确率: $accuracy%';
    }
  }

  /// Build a natural share caption based on mode + result + stats.
  String shareMessage({
    required bool vsAI,
    required GameResult result,
    required int totalMoves,
    required int durationSecs,
    required int boardSide,
    required int winLength,
  }) {
    final String lead;
    if (vsAI) {
      lead = (result == GameResult.xWins) ? shareMessageWinAi : shareMessageLoseAi;
    } else {
      lead = shareMessagePvp;
    }
    final String boardLine = formatHistoryBoardLine(boardSide, winLength);
    final String movesLine = formatHistoryMoveCount(totalMoves);
    return '$lead\n$boardLine · $movesLine';
  }
}

// Global instance
final l10n = L10n();
