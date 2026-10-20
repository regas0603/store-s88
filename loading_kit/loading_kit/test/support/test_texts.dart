// Text giả lập cho test — code app KHÔNG chứa text (xem
// lib/core/remote_texts.dart). Đặt theo INDEX ([TK]) nên không có chuỗi tên key.
import 'package:loading_kit/core/text_keys.dart';
import 'package:loading_kit/loading_kit.dart';

const String kForceUpdateTitle = 'Cập nhật mới';
const String kForceUpdateLiveMessage =
    'Đã có bản cập nhật mới. Vui lòng cập nhật để tiếp tục sử dụng.';
const String kSoftUpdateMessage =
    'Đã có bản cập nhật mới với nhiều cải tiến. Bạn có muốn cập nhật ngay?';
const String kUpdateNowLabel = 'Cập nhật ngay';
const String kSoftUpdateNowLabel = 'Cập nhật';
const String kSoftUpdateLaterLabel = 'Để sau';

/// Mảng text theo index [TK] (giống bản gen từ configs/texts.json).
List<String?> testTextValues() {
  final List<String?> v = List<String?>.filled(TK.count, null);
  v[TK.loading] = 'Loading...';
  v[TK.connectionErrorTitle] = 'Lỗi Internet';
  v[TK.connectionErrorMessage] = 'Không thể kết nối đến server. Thử lại?';
  v[TK.connectionErrorRetry] = 'Thử lại';
  v[TK.updateTitle] = kForceUpdateTitle;
  v[TK.forceUpdateMessage] = kForceUpdateLiveMessage;
  v[TK.forceUpdateButton] = kUpdateNowLabel;
  v[TK.softUpdateMessage] = kSoftUpdateMessage;
  v[TK.softUpdateButton] = kSoftUpdateNowLabel;
  v[TK.softUpdateLater] = kSoftUpdateLaterLabel;
  v[TK.storeOpenError] = 'Không mở được cửa hàng ứng dụng. Vui lòng thử lại.';
  v[TK.restartTitle] = 'Cập nhật thành công';
  v[TK.restartMessageAndroid] = 'v{version} android';
  v[TK.restartMessageIos] = 'v{version} ios';
  v[TK.restartError] = 'err {code}';
  v[TK.restartOk] = 'OK';
  v[TK.restartCancel] = 'Cancel';
  v[TK.liveFallback] = 'Ready';
  return v;
}

/// Bơm text test như thể đã tải Git JSON.
void useTestTexts() {
  RemoteTexts.notifier.value = RemoteTexts.fromIndexed(testTextValues());
}
