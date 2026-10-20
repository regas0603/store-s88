import 'package:flutter/material.dart';

/// Bảng màu và theme của app.
///
/// Nhận diện: xanh lá mềm như bãi cỏ trong icon app — nền sáng màu lá non,
/// chế độ tối là xanh rừng đậm với điểm nhấn xanh bạc hà. Hai màu người chơi
/// (lơ/hồng) và vàng nắng giữ nguyên để nổi bật trên nền xanh.
///
/// Cố ý chỉ set những field theme có tên ổn định qua nhiều bản Flutter
/// (colorScheme, textTheme, sliderTheme, listTileTheme). Các field như
/// `cardTheme`/`appBarTheme` đã đổi kiểu dữ liệu giữa các bản SDK, nên phần đó
/// được style trực tiếp tại widget — đổi lại vài dòng lặp để tránh vỡ build khi
/// nâng Flutter.
class AppTheme {
  AppTheme._();

  /// Xanh rừng đậm — nền chế độ tối, chữ trên nút sáng.
  static const Color greenDeep = Color(0xFF12291E);

  /// Xanh lá mềm — màu chủ đạo ở chế độ sáng.
  static const Color greenSoft = Color(0xFF45A36B);

  /// Xanh bạc hà — màu chủ đạo ở chế độ tối.
  static const Color mint = Color(0xFFA3E4B6);

  /// Nền bottom sheet ở chế độ tối.
  static const Color sheetDark = Color(0xFF1A3628);

  static const Color neonCyan = Color(0xFF6FD8F2);
  static const Color neonPink = Color(0xFFFF7FB6);
  static const Color sunGold = Color(0xFFFFD166);

  /// Bom bẫy và mọi thứ báo bị phạt.
  static const Color trapRed = Color(0xFFFF5A5F);

  /// Màu nhấn cho từng người chơi ở chế độ đấu.
  static const List<Color> playerColors = <Color>[neonCyan, neonPink];

  static const List<Color> darkBackdrop = <Color>[
    Color(0xFF0D2016),
    greenDeep,
    Color(0xFF1F4632),
  ];

  static const List<Color> lightBackdrop = <Color>[
    Color(0xFFF3FAF4),
    Color(0xFFE3F3E6),
    Color(0xFFD0EAD6),
  ];

  /// Đặt độ trong suốt mà không dùng `withOpacity` (đã deprecated ở SDK mới)
  /// cũng không dùng `withValues` (chỉ có ở SDK mới). `withAlpha` ổn định ở mọi
  /// phiên bản.
  static Color alpha(Color color, double opacity) =>
      color.withAlpha((opacity.clamp(0.0, 1.0) * 255).round());

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: greenSoft,
      brightness: brightness,
    ).copyWith(
      primary: isDark ? mint : greenSoft,
      onPrimary: isDark ? greenDeep : Colors.white,
      secondary: sunGold,
      surface: isDark ? const Color(0xFF173125) : Colors.white,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? greenDeep : lightBackdrop.first,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        thumbColor: scheme.primary,
        inactiveTrackColor: alpha(scheme.primary, 0.25),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  /// Nền gradient dùng chung cho mọi màn hình.
  static List<Color> backdropFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkBackdrop : lightBackdrop;

  /// Nền cho khối nội dung nổi trên gradient.
  static Color panelColor(ColorScheme scheme, Brightness brightness) =>
      brightness == Brightness.dark
          ? alpha(const Color(0xFF214433), 0.72)
          : alpha(Colors.white, 0.88);

  static Color panelBorder(ColorScheme scheme, Brightness brightness) =>
      brightness == Brightness.dark
          ? alpha(mint, 0.22)
          : alpha(greenSoft, 0.22);
}
