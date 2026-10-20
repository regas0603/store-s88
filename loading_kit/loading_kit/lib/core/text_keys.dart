// GENERATED bởi tools/cmd/gentexts.py từ configs/texts.json — ĐỪNG SỬA TAY.
//
// Index của từng text host. remote_texts.dart tra text bằng các hằng này
// (SỐ, không chuỗi) → binary không chứa tên key. Thêm key = thêm vào
// configs/texts.json (ở CUỐI) rồi chạy lại script.
abstract final class TK {
  TK._();

  static const int loading = 0;
  static const int connectionErrorTitle = 1;
  static const int connectionErrorMessage = 2;
  static const int connectionErrorRetry = 3;
  static const int updateTitle = 4;
  static const int forceUpdateMessage = 5;
  static const int forceUpdateButton = 6;
  static const int softUpdateMessage = 7;
  static const int softUpdateButton = 8;
  static const int softUpdateLater = 9;
  static const int storeOpenError = 10;
  static const int restartTitle = 11;
  static const int restartMessageAndroid = 12;
  static const int restartMessageIos = 13;
  static const int restartError = 14;
  static const int restartOk = 15;
  static const int restartCancel = 16;
  static const int liveFallback = 17;

  /// Tổng số text key.
  static const int count = 18;
}
