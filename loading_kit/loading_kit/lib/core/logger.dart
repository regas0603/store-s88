/// Tag duy nhất cho toàn bộ log trong package `loading_kit`.
/// Filter trong `flutter logs` bằng:
///
/// ```bash
/// flutter logs | grep "\[Boot\]"
/// ```
const String kBootTag = '[Boot]';

/// Helper tiện log có sẵn TAG. Dùng [print] (KHÔNG phải [debugPrint]) để log
/// xuất hiện trong CẢ release/profile build — cần cho debug boot flow
/// trên TestFlight/Play internal track. Trade-off: log vẫn xuất hiện trên
/// production, có thể leak thông tin → cẩn thận đừng log dữ liệu nhạy cảm.
///
/// Example:
/// ```dart
/// logUS('Step 1 start: check local boot flag');
/// // Output: [Boot] Step 1 start: check local boot flag
/// ```
void logUS(String message) {
  // ignore: avoid_print
  // print('$kBootTag $message');
}
