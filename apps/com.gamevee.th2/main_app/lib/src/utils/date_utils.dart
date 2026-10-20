/// Calendar/date helpers (mirrors Flutter Material [DateUtils.dateOnly] behavior).
abstract final class DateUtils {
  DateUtils._();

  /// Returns a [DateTime] with the same calendar date as [date] and time set
  /// to 00:00:00.000.
  ///
  /// If [date] is UTC, the result is UTC; otherwise the result is local.
  static DateTime dateOnly(DateTime date) {
    return date.isUtc
        ? DateTime.utc(date.year, date.month, date.day)
        : DateTime(date.year, date.month, date.day);
  }
}

/// "18/08 14:32" — định dạng ngắn dùng cho thẻ tổng kết phân tích (US-005).
///
/// Cố ý không dùng `package:intl`: app chưa phụ thuộc intl và thêm vào chỉ vì
/// một chuỗi ngày là không đáng. Định dạng số thuần đọc được ở cả 4 ngôn ngữ.
String formatDateTimeShort(DateTime dt) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(dt.day)}/${two(dt.month)} ${two(dt.hour)}:${two(dt.minute)}';
}
