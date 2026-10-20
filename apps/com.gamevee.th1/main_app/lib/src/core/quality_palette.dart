import 'package:flutter/material.dart';

import 'game_analysis.dart';

/// Bảng màu và ký hiệu cho tính năng Phân tích ván đấu (US-005).
///
/// ─────────────────────────────────────────────────────────────────────────
/// QUY TẮC SỐNG CÒN: màu chất lượng KHÔNG BAO GIỜ được vẽ trực tiếp lên nền
/// bàn cờ. Luôn đặt trên [surfaceMarkerDisc] hoặc bọc trong hào tối
/// ([haloDark]) 3 lớp.
///
/// Lý do là số đo, không phải thẩm mỹ: nền bàn cờ có 6 biến thể
/// (`BoardBackground`) từ #0d0d22 tới #5d4037. Màu [blunder] chỉ đạt
/// **2.68:1** trên nền `ocean` — trượt chuẩn tương phản 3:1. Trên đế tối, mọi
/// màu trong bảng này đạt **>= 6.5:1**.
///
/// Bảng màu cũng đã được kiểm khoảng cách cảm nhận (ΔE, CIE76): cặp gần nhau
/// nhất là Sai lầm ↔ Thảm hoạ = 39.7, thừa ngưỡng an toàn 25.
/// ─────────────────────────────────────────────────────────────────────────
class QualityPalette {
  QualityPalette._();

  // ── Bề mặt ──
  static const Color surfaceMarkerDisc = Color(0xEB0B0B18); // 92% alpha
  static const Color surfaceChart = Color(0xFF12122A);
  static const Color surfaceCard = Color(0xFF14142B);
  static const Color surfaceScreen = Color(0xFF070714);
  static const Color haloDark = Color(0xD90B0B18); // 85% alpha
  static const Color strokeHairline = Color(0x1AFFFFFF); // 10% trắng

  // ── Màu chất lượng ──
  static const Color brilliant = Color(0xFF22D3EE);
  static const Color good = Color(0xFF4ADE80);
  static const Color inaccuracy = Color(0xFFFACC15);
  static const Color mistake = Color(0xFFFB923C);
  static const Color blunder = Color(0xFFF87171);

  /// Màu của lớp phủ "nước tốt hơn".
  static const Color better = Color(0xFFC4B5FD);

  static Color colorOf(MoveQuality q) {
    switch (q) {
      case MoveQuality.brilliant:
        return brilliant;
      case MoveQuality.good:
        return good;
      case MoveQuality.inaccuracy:
        return inaccuracy;
      case MoveQuality.mistake:
        return mistake;
      case MoveQuality.blunder:
        return blunder;
    }
  }

  /// Ký hiệu vẽ trên bàn cờ và trong băng chất lượng.
  ///
  /// Ký hiệu là **dấu hiệu thứ hai không dựa vào màu** — người mù màu vẫn phân
  /// biệt được. Chỉ dùng ký tự có trong font Noto Sans, không dùng emoji.
  static String glyphOf(MoveQuality q) {
    switch (q) {
      case MoveQuality.brilliant:
        return '✦'; // ✦
      case MoveQuality.good:
        return '✓'; // ✓
      case MoveQuality.inaccuracy:
        return '!';
      case MoveQuality.mistake:
        return '‼'; // ‼
      case MoveQuality.blunder:
        return '✕'; // ✕
    }
  }

  /// Vòng của nước xấu vẽ nét đứt — dấu hiệu thứ hai không dựa vào màu.
  static bool dashedFor(MoveQuality q) => q.isBad;

  /// Màu của con số Độ chính xác, theo dải.
  static Color accuracyColor(int accuracy) {
    if (accuracy >= 90) return brilliant;
    if (accuracy >= 75) return good;
    if (accuracy >= 60) return inaccuracy;
    if (accuracy >= 40) return mistake;
    return blunder;
  }

  /// Ngưỡng bề rộng ô để đổi chế độ hiển thị nhãn trên bàn cờ.
  ///
  /// Ô >= ngưỡng: huy hiệu ở góc. Ô < ngưỡng: đổi màu vòng nước cuối.
  ///
  /// Con số đến từ đo đạc: trên màn 360dp, bàn 15x15 có ô 21.3dp và quân cờ đã
  /// chiếm 13.7dp — không huy hiệu nào đọc được ở đó. Bàn 9x9 có ô 35.6dp thì
  /// vừa đủ. Ngưỡng đặt ở 30 để 9x9 vẫn dùng huy hiệu trên cả màn 320dp.
  static const double badgeModeMinCell = 30.0;
}
