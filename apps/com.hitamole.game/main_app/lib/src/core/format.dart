/// Định dạng thời lượng thành mm:ss (hoặc h:mm:ss khi vượt một giờ).
String formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');

  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}

/// Định dạng mili-giây đã lưu trong kỷ lục.
String formatMillis(int? milliseconds) =>
    milliseconds == null ? '--:--' : formatDuration(Duration(milliseconds: milliseconds));
