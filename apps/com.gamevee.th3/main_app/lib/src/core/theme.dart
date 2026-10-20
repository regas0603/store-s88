import 'package:flutter/material.dart';

/// Bảng màu và theme của Flipmind.
///
/// Nhận diện: nền tím sâu, viền neon lơ/hồng. Cùng hệ với `card_back.svg` và
/// icon app, nên mặt sau lá bài trông như thuộc về giao diện chứ không phải
/// một ảnh dán vào.
///
/// Cố ý chỉ set những field theme có tên ổn định qua nhiều bản Flutter
/// (colorScheme, textTheme, sliderTheme, listTileTheme). Các field như
/// `cardTheme`/`appBarTheme` đã đổi kiểu dữ liệu giữa các bản SDK, nên phần đó
/// được style trực tiếp tại widget — đổi lại vài dòng lặp để tránh vỡ build khi
/// nâng Flutter.
class AppTheme {
  AppTheme._();

  static const Color violetDeep = Color(0xFF241A5E);
  static const Color violetMid = Color(0xFF4A2A8A);
  static const Color violetBright = Color(0xFF8A2FB0);
  static const Color neonCyan = Color(0xFF7CF5FF);
  static const Color neonPink = Color(0xFFFF5FD2);
  static const Color sunGold = Color(0xFFFFD166);

  /// Màu nhấn cho từng người chơi ở chế độ đấu.
  static const List<Color> playerColors = <Color>[neonCyan, neonPink];

  static const List<Color> darkBackdrop = <Color>[
    Color(0xFF15102F),
    violetDeep,
    Color(0xFF3A1F6B),
  ];

  static const List<Color> lightBackdrop = <Color>[
    Color(0xFFF5F1FF),
    Color(0xFFE8DFFC),
    Color(0xFFDACCF8),
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
      seedColor: violetBright,
      brightness: brightness,
    ).copyWith(
      primary: isDark ? neonCyan : violetBright,
      secondary: neonPink,
      surface: isDark ? const Color(0xFF1E1746) : Colors.white,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? violetDeep : const Color(0xFFF5F1FF),
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
          ? alpha(const Color(0xFF2A2060), 0.72)
          : alpha(Colors.white, 0.88);

  static Color panelBorder(ColorScheme scheme, Brightness brightness) =>
      brightness == Brightness.dark
          ? alpha(neonCyan, 0.22)
          : alpha(violetBright, 0.16);
}
