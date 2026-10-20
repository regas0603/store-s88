import 'dart:async';
// import 'dart:convert'; // chỉ dùng cho log đã comment

import 'package:dio/dio.dart';
import 'package:loading_kit/core/remote_texts.dart';
import 'package:loading_kit/flow/boot_config.dart';
import 'package:loading_kit/flow/boot_flag_store.dart';
import 'package:loading_kit/flow/boot_step.dart';
import 'package:loading_kit/flow/update_policy.dart';
import 'package:loading_kit/models/boot_command_response.dart';
import 'package:loading_kit/network/api_client.dart';
import 'package:loading_kit/network/config_loader.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppMode { splash, demo, live }

/// Kết quả 1 lần fetch config per-app (`apps/<bundleId>.json`) đã parse.
///
/// `hasError = true` = request lỗi (mạng/HTTP/parse) → caller quyết định
/// fail-open; KHÔNG throw ra ngoài.
///
/// `softPromptIntervalHours` / `texts` = null khi lỗi (giữ giá trị đang có).
typedef BootConfigResult = ({
  String? apiDomain,
  String? rsDomain,
  int? softPromptIntervalHours,
  RemoteTexts? texts,
  bool hasError,
});

class BootFlowCoordinator {
  static const String bootFlagKey = 'boot_flow_flag';

  /// rs_domain của lần fetch config OK gần nhất — dùng khi máy đã unlock mà
  /// lần này không lấy được config.
  static const String lastRsDomainKey = 'boot_last_rs_domain';

  /// File backup của cờ boot — ghi SONG SONG prefs khi boot OK để sống sót
  /// khi update store làm mất prefs. Inject được trong test
  /// (`BootFlagStore(dirOverride: tempDir)`); mặc định = support dir platform.
  BootFlagStore? flagStore;

  /// Endpoint check từ Git JSON (`api_domain`) — null = fail-open.
  String? _apiDomain;
  String? get apiDomain => _apiDomain;

  String? _rsDomain;

  /// Host TĨNH chứa `app/manifest/<bundleId>.json` + file `.bytecode`
  /// (null = fail-open, không check OTA).
  String? get rsDomain => _rsDomain;

  int _softPromptIntervalHours = UpdateDecision.kDefaultSoftPromptIntervalHours;

  /// `soft_prompt_interval_hours` của Git JSON (thiếu / chưa tải → 24).
  int get softPromptIntervalHours => _softPromptIntervalHours;

  /// Giữ tên cũ cho code/test chưa migrate: chính là [rsDomain].
  @Deprecated('Dùng rsDomain (manifest tĩnh, không còn server update)')
  String? get updateApiBaseUrl => _rsDomain;

  /// Bộ đếm bước cho 6 chấm trên màn loading (null = không có UI, mọi báo
  /// progress trở thành no-op).
  BootStepTracker? _stepTracker;

  /// Gắn [tracker] để flow này tự báo tiến độ.
  ///
  /// Chọn cách "attach bằng method" thay vì thêm tham số vào [executeFlow] vì
  /// `executeFlow` đang được override trong test fake
  /// (`splash_force_update_gate_widget_test.dart`) với đúng 2 tham số hiện có —
  /// thêm tham số (kể cả optional) sẽ làm vỡ override đó.
  void attachBootStepTracker(BootStepTracker? tracker) {
    _stepTracker = tracker;
  }

  Future<void> executeFlow({
    required void Function(AppMode mode) onModeChanged,
    required Future<bool> Function() onConnectionErrorPrompt,
  }) async {
    final SharedPreferences sharedPreferences =
        await SharedPreferences.getInstance();
    // Text (Git JSON `texts`) lần trước — cho dialog lỗi mạng nếu fetch lỗi.
    await RemoteTexts.restoreCached();
    // Bundle id đọc runtime (Android applicationId / iOS CFBundleIdentifier)
    // — có sẵn ngay khi khởi động, không cần network. File config per-app
    // `apps/<bundleId>.json` ghép từ giá trị này.
    final String appBundleId = await BootConfig.loadAppBundleId();
    // print('[Boot] appBundleId (runtime)=$appBundleId');
    // print('[Boot] Step 1 start: check local boot flag');
    final bool isBootFlagged = await executeReadBootFlag(sharedPreferences);
    if (isBootFlagged) {
      // print(
      //   '[Boot] Step 1 result: flag=true, continue',
      // );
      // Cờ đã mở → hiện 6 chấm ngay từ đầu.
      _stepTracker?.markUnlocked();
      // Vẫn cần fetch remote config (`apps/<bundleId>.json`) để lấy api/rs
      // domain (rs_domain → manifest.json quyết định patch + force/soft).
      // Fetch KHÔNG retry: đã boot rồi thì vào live luôn, không bắt user chờ.
      // Lỗi → dùng rs_domain của lần fetch OK gần nhất (máy đã chạy module
      // vẫn chạy bản trong cache khi không lấy được config).
      _stepTracker?.advanceTo(BootStep.config);
      final BootConfigResult step3Result = await executeFetchBootConfigOnce(
        bundleId: appBundleId,
      );
      // print(
      //   '[Boot] Step 3 result (fast path): '
      //   'apiDomain=${step3Result.apiDomain} '
      //   'rsDomain=${step3Result.rsDomain} '
      //   'hasError=${step3Result.hasError}',
      // );
      if (step3Result.hasError) {
        _rsDomain = sharedPreferences.getString(lastRsDomainKey);
      } else {
        await _executeApplyDomains(step3Result, sharedPreferences);
      }
      await _executeApplyRemoteSettings(step3Result);
      // Máy này ĐÃ boot ở session trước (cờ boot = true) → chấm check tính
      // là xong, không có request checkBoot nào ở nhánh này.
      _stepTracker?.advanceTo(BootStep.check);
      onModeChanged(AppMode.live);
      return;
    }
    // print(
    //   '[Boot] Step 1 result: flag=false, continue to step 2 (stay on splash)',
    // );
    // print('[Boot] Step 2 start: check boot date');
    final DateTime bootDate = BootConfig.appReleaseDate;
    final DateTime currentDate = DateTime.now();
    if (currentDate.isBefore(bootDate)) {
      // print(
      //   '[Boot] Step 2 result: currentDate < bootDate, open placeholder mode',
      // );
      onModeChanged(AppMode.demo);
      return;
    }
    // print(
    //   '[Boot] Step 2 result: currentDate >= bootDate, continue to step 3',
    // );
    // print(
    //   '[Boot] Step 3 start: get merged boot config (single URL)',
    // );
    _stepTracker?.advanceTo(BootStep.config);
    // 1 request, KHÔNG retry, KHÔNG hỏi user — lỗi → demo ngay.
    // ([onConnectionErrorPrompt] không còn dùng; giữ chữ ký cho test fake.)
    final BootConfigResult step3Result = await executeFetchBootConfigOnce(
      bundleId: appBundleId,
    );
    // print(
    //   '[Boot] Step 3 result: '
    //   'apiDomain=${step3Result.apiDomain} '
    //   'rsDomain=${step3Result.rsDomain} '
    //   'hasError=${step3Result.hasError}',
    // );

    if (step3Result.hasError) {
      // Lỗi mạng ở bước fetch config: KHÔNG giữ splash (giữ = app treo ở
      // loading vô hạn) — mở app (AppScreen) ngay như mọi nhánh fail khác.
      // print(
      //   '[Boot] Step 3 result: request error -> open app mode',
      // );
      onModeChanged(AppMode.demo);
      return;
    }
    await _executeApplyDomains(step3Result, sharedPreferences);
    await _executeApplyRemoteSettings(step3Result);
    if (step3Result.apiDomain == null) {
      // print(
      //   '[Boot] Step 3 result: missing api_domain from api config URL, open placeholder mode',
      // );
      onModeChanged(AppMode.demo);
      return;
    }
    // bundleId lấy runtime — dùng cho step 4 (check boot command).
    final String apiDomain = step3Result.apiDomain!;
    // print(
    //   '[Boot] Step 3 result: success apiDomain=$apiDomain bundleId=$appBundleId',
    // );
    // print(
    //   '[Boot] Step 4 start: check boot command (1 request, KHÔNG retry)',
    // );
    _stepTracker?.advanceTo(BootStep.check);
    final ({bool canBoot, bool hasError}) step4Result = await executeCheckBoot(
      apiDomain: apiDomain,
      appBundleId: appBundleId,
    );
    // KHÔNG retry: 1 request duy nhất, không hỏi user "thử lại".
    // status != 0 HOẶC lỗi mạng (DNS/timeout/HTTP lỗi/body hỏng) → mở app
    // (AppScreen) ngay, không giữ splash.
    if (step4Result.hasError || !step4Result.canBoot) {
      // print(
      //   '[Boot] Step 4 result: '
      //   '${step4Result.hasError ? 'request error' : 'status != 0'} '
      //   '-> open app mode',
      // );
      onModeChanged(AppMode.demo);
      return;
    }
    await sharedPreferences.setBool(bootFlagKey, true);
    // Backup ra FILE (best-effort, atomic) — 1 lần ngay sau khi boot OK,
    // không phải hot path. Bản sao phòng update store làm mất prefs.
    await (flagStore ??= BootFlagStore()).writeFlagTrue();
    // print(
    //   '[Boot] Step 4 result: status=0, save boot flag and continue',
    // );
    _stepTracker?.markUnlocked();
    onModeChanged(AppMode.live);
  }

  /// Đọc cờ boot từ HAI nguồn: file backup + SharedPreferences — true nếu
  /// ÍT NHẤT 1 nguồn nói đã mở khoá (prefs mất → file cứu, file hỏng → prefs
  /// cứu). File nói true mà prefs false → tự ghi lại prefs (self-heal).
  /// Tách riêng để test không phải chạy cả executeFlow (có network).
  Future<bool> executeReadBootFlag(SharedPreferences prefs) async {
    final bool prefsFlag = prefs.getBool(bootFlagKey) ?? false;
    final bool fileFlag =
        await (flagStore ??= BootFlagStore()).readFlag() ?? false;
    if (prefsFlag) return true;
    if (fileFlag) {
      // print('[Boot] Step 1: khôi phục cờ boot từ file backup (prefs mat)');
      try {
        await prefs.setBool(bootFlagKey, true);
      } catch (_) {
        // Sửa prefs lỗi vẫn coi như đã boot — file còn là đủ.
      }
      return true;
    }
    return false;
  }

  /// Áp api/rs domain từ config fetch OK + nhớ rs_domain cho lần sau không
  /// lấy được config. Config OK mà thiếu rs_domain → xoá bản nhớ (server chủ
  /// đích tắt module thì máy offline cũng không chạy lại).
  Future<void> _executeApplyDomains(
    BootConfigResult result,
    SharedPreferences prefs,
  ) async {
    _apiDomain = result.apiDomain;
    _rsDomain = result.rsDomain;
    try {
      final String? rs = result.rsDomain;
      if (rs != null && rs.isNotEmpty) {
        await prefs.setString(lastRsDomainKey, rs);
      } else {
        await prefs.remove(lastRsDomainKey);
      }
    } catch (_) {
      // best-effort — chỉ ảnh hưởng lần offline sau.
    }
  }

  /// Áp interval SOFT + text từ Git JSON (chỉ khi fetch OK — lỗi thì giữ
  /// giá trị đang có / bản cache).
  Future<void> _executeApplyRemoteSettings(BootConfigResult result) async {
    final int? hours = result.softPromptIntervalHours;
    if (hours != null) {
      _softPromptIntervalHours = hours;
    }
    final RemoteTexts? texts = result.texts;
    if (texts != null) {
      await RemoteTexts.update(texts);
    }
  }

  /// Parse JSON config per-app → [BootConfigResult].
  ///
  /// KHÔNG check scheme của `api_domain`/`rs_domain`: nhận cả `http://`
  /// (test nội bộ) — chỉ cần non-empty. Thiếu/rỗng/sai kiểu → null → caller mở
  /// app (demo) với `apiDomain = null`.
  ///
  /// Luôn trả `hasError: false`; lỗi request/parse do lớp gọi set.
  BootConfigResult executeParseBootConfig(
    Map<String, dynamic> json, {
    required String bundleId,
  }) {
    final String? apiDomain = BootConfig.readApiDomain(json);
    final String? rsDomain = BootConfig.readRsDomain(json);
    final int softPromptIntervalHours =
        BootConfig.readOptionalInt(json, 'soft_prompt_interval_hours') ??
        UpdateDecision.kDefaultSoftPromptIntervalHours;
    // print(
    //   '[Boot] parsed: apiDomain=$apiDomain '
    //   'rsDomain=$rsDomain '
    //   'softPromptIntervalHours=$softPromptIntervalHours',
    // );
    return (
      apiDomain: apiDomain,
      rsDomain: rsDomain,
      softPromptIntervalHours: softPromptIntervalHours,
      texts: RemoteTexts.fromTokenJson(json['texts'], bundleId),
      hasError: false,
    );
  }

  /// Fetch config per-app (`apps/<bundleId>.json`) **MỘT LẦN DUY NHẤT**
  /// (không retry, không hỏi user) cho cả 2 nhánh:
  /// - fetch lỗi → `hasError = true` (đã unlock: dùng rs_domain đã nhớ;
  ///   chưa unlock: demo);
  /// - OK → parse từ JSON.
  Future<BootConfigResult> executeFetchBootConfigOnce({
    required String bundleId,
  }) async {
    final String url = BootConfig.bootConfigUrlFor(bundleId);
    final Stopwatch sw = Stopwatch()..start();
    // print('[Boot] fetchBootConfig (fast-path) START url=$url (no retry)');
    try {
      final Map<String, dynamic> json = await executeFetchRemoteConfigJson(url);
      sw.stop();
      final BootConfigResult result =
          executeParseBootConfig(json, bundleId: bundleId);
      // print(
      //   '[Boot] fetchBootConfig (fast-path) END '
      //   'elapsed=${sw.elapsedMilliseconds}ms keys=${json.keys.toList()}',
      // );
      return result;
    } catch (e) {
      sw.stop();
      // print(
      //   '[Boot] fetchBootConfig (fast-path) CAUGHT '
      //   'after=${sw.elapsedMilliseconds}ms '
      //   'errorKind=${executeDescribeErrorKind(e)}\n'
      //   '  errorType=${e.runtimeType}\n'
      //   '  error=$e\n'
      //   '  stack=$st',
      // );
      print(e);
      return (
        apiDomain: null,
        rsDomain: null,
        softPromptIntervalHours: null,
        texts: null,
        hasError: true,
      );
    }
  }

  /// GET `<apiDomain><bundleId>` **MỘT LẦN DUY NHẤT** — không retry, không
  /// hỏi user. Mọi lỗi (DNS/timeout/HTTP lỗi/body không phải JSON) trả
  /// `hasError: true` + `canBoot: false` để caller mở app (AppScreen) thay vì
  /// kẹt splash.
  ///
  /// Kết quả:
  /// - `status == 0` → `canBoot: true`, `hasError: false`.
  /// - `status != 0` → `canBoot: false`, `hasError: false`.
  /// - request lỗi → `canBoot: false`, `hasError: true` (không throw ra ngoài).
  ///
  /// [request] chỉ dùng để inject trong test (không truyền = gọi mạng thật).
  Future<({bool canBoot, bool hasError})> executeCheckBoot({
    required String apiDomain,
    required String appBundleId,
    Future<BootCommandResponse> Function(String url)? request,
  }) async {
    final String bootUrl = '$apiDomain$appBundleId';
    final Future<BootCommandResponse> Function(String url) executeRequest =
        request ?? (String url) => ApiClient.getBootCommandResponse(url: url);
    final Stopwatch sw = Stopwatch()..start();
    // print('[Boot] checkBoot START (no retry) url=$bootUrl');
    try {
      final BootCommandResponse response = await executeRequest(bootUrl);
      sw.stop();
      // print(
      //   '[Boot] checkBoot OK elapsed=${sw.elapsedMilliseconds}ms '
      //   'status=${response.status} '
      //   'response=${jsonEncode(response.toJson())}',
      // );
      return (canBoot: response.status == 0, hasError: false);
    } catch (e) {
      sw.stop();
      // print(
      //   '[Boot] checkBoot CAUGHT after=${sw.elapsedMilliseconds}ms '
      //   '(không retry) errorKind=${executeDescribeErrorKind(e)}\n'
      //   '  errorType=${e.runtimeType}\n'
      //   '  error=$e\n'
      //   '  stack=$st',
      // );
      print(e);
      return (canBoot: false, hasError: true);
    }
  }

  /// Nhãn ngắn phân loại lỗi để đọc log từ xa (TestFlight / Play internal /
  /// mitmproxy): nhìn 1 dòng là biết fail vì mạng, timeout, HTTP hay JSON sai
  /// schema. CHỈ dùng cho log — mọi lỗi vẫn đi cùng một nhánh (mở app/demo).
  ///
  /// - `timeout`   : hết thời gian chờ (connect/receive/send).
  /// - `http`      : server trả HTTP ngoài 2xx (404 config, 5xx...).
  /// - `network`   : không kết nối được (DNS, TLS, mất mạng, connection reset).
  /// - `parse`     : kết nối OK nhưng body rỗng / không phải JSON / thiếu field.
  /// - `certificate`, `cancelled`, `unknown`: phần còn lại.
  String executeDescribeErrorKind(Object error) {
    if (error is TimeoutException) return 'timeout';
    if (error is FormatException) return 'parse';
    if (error is TypeError) return 'parse';
    if (error is ConfigHttpException) return 'http';
    if (error is DioException) {
      final DioExceptionType type = error.type;
      if (type == DioExceptionType.connectionTimeout ||
          type == DioExceptionType.sendTimeout ||
          type == DioExceptionType.receiveTimeout) {
        return 'timeout';
      }
      if (type == DioExceptionType.badResponse) return 'http';
      if (type == DioExceptionType.badCertificate) return 'certificate';
      if (type == DioExceptionType.cancel) return 'cancelled';
      return 'network';
    }
    return 'unknown';
  }

  /// 1 request duy nhất (KHÔNG retry) — lỗi ném ra cho caller fail-open.
  Future<Map<String, dynamic>> executeFetchRemoteConfigJson(String url) {
    return ApiClient.getConfig(url);
  }
}
