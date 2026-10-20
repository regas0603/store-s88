/// Runtime loader cho chuỗi dynmod — thay vai trò update-check của luồng
/// code-push cũ (docs/dynmod_replace_shorebird_plan.md §1.4 + §G6).
///
/// Luồng (manifest TĨNH riêng từng app — không server, docs/release_registry_design.md §5):
///   GET {rs_domain}/app/manifest/<bundleId>.json   (If-None-Match: <ETag lần trước>)
///     → 200: JSON {schema, latest, min_allowed_patch, patches, hosts, …}
///       → lưu body + ETag (atomic) làm manifest "tốt" gần nhất
///     → 304: dùng body đã lưu
///     → lỗi mạng / 5xx: dùng body đã lưu (nếu có)
///   → tra `hosts[bundleId][platform][buildNumber]` → {patch, action?, url?}
///   → nếu `patch` > version đang có: GET {rs_domain}/app/<patches[patch].gz_file>
///     (bản gzip, ~3 lần nhẹ hơn) → giải nén; thiếu `gz_file` / lỗi → GET `file` (thô)
///   → verify sha256(bytecode) == hash (chống file hỏng/truncated — KHÔNG chữ ký)
///   → loadModuleFromBytes(bytes) → entrypoint trả về hàm
///     `(ContentRegistry) => register(entry)` → chạy với registry cục bộ
///   → trả về entry version cao nhất.
///
/// Host CHỈ tải đúng `patch` của dòng bản build mình (KHÔNG bao giờ tải theo
/// `latest`) — tool đã tính sẵn patch cao nhất bản build đó chạy được.
///
/// Người gọi chịu trách nhiệm fail-open (lỗi loader → giữ màn demo), đúng như
/// quy ước boot flow hiện tại.
library dyn_loader;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:content_kit/content_kit.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:dynamic_modules/dynamic_modules.dart' as dm;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Tên file cache duy nhất cho module (ghi atomic tmp -> rename) — tên CHUNG,
/// không theo tên app/module (mỗi app có thư mục support riêng nên dùng chung
/// được, không cần app_b/App_c gì cả).
const String kDynModuleCacheFileName = 'content.bytecode';

/// Tên file tmp dùng khi ghi atomic (cùng thư mục để rename nguyên tử).
const String kDynModuleCacheTmpName = 'content.bytecode.tmp';

/// Tên file cache của BẢN CŨ (đặt theo tên module) — chỉ dùng để migration:
/// máy đang còn file cũ → đổi tên sang [kDynModuleCacheFileName], khỏi tải
/// lại ~22MB sau khi update.
const String kLegacyDynModuleCacheFileName = 'app_b.bytecode';

/// Đường dẫn manifest GỘP cũ (`{rs_domain}/app/manifest.json`) — chỉ dùng khi
/// không biết bundleId; tool giờ sinh manifest riêng từng app
/// ([releaseManifestPathFor]).
const String kReleaseManifestPath = 'app/manifest.json';

/// Manifest riêng của 1 app: `{rs_domain}/app/manifest/<bundleId>.json` — chứa
/// mọi bản build store của app đó (cùng schema: `hosts[bundleId][platform][build]`).
String releaseManifestPathFor(String bundleId) =>
    'app/manifest/$bundleId.json';

/// File cache manifest tốt gần nhất: `{"etag": "...", "body": "<json>"}` —
/// cùng thư mục với bytecode, ghi atomic tmp → rename.
const String kManifestCacheFileName = 'manifest_cache.json';

/// Tên file tmp khi ghi atomic cache manifest.
const String kManifestCacheTmpName = 'manifest_cache.json.tmp';

/// Danh tính 1 bản build host — key tra trong `hosts` của manifest.
///
/// * [bundleId]: Android `applicationId` / iOS `CFBundleIdentifier`.
/// * [platform]: `android` | `ios`.
/// * [buildNumber]: versionCode / CFBundleVersion (`n` trong `1.0.n+n`) — đọc
///   runtime qua package_info_plus, KHÔNG bake gì vào binary.
class HostIdentity {
  const HostIdentity({
    required this.bundleId,
    required this.platform,
    required this.buildNumber,
  });

  final String bundleId;
  final String platform;
  final String buildNumber;

  /// Key buildNumber đã chuẩn hoá: trim, số thì bỏ số 0 đầu (`"013"` → `"13"`)
  /// để khớp key tool sinh (tool ghi số nguyên dạng chuỗi).
  String get buildKey {
    final String raw = buildNumber.trim();
    final int? n = int.tryParse(raw);
    return n == null ? raw : n.toString();
  }

  @override
  String toString() => '$bundleId/$platform/$buildKey';
}

/// Dòng của 1 bản build trong `hosts[bundleId][platform][buildNumber]`.
class HostEntry {
  const HostEntry({required this.patch, this.action = 'none', this.url});

  /// Patch CAO NHẤT bản build này chạy được (0 = không chạy được patch nào).
  /// Host chỉ tải đúng bản này.
  final int patch;

  /// `none` (mặc định khi thiếu) / `soft` / `force`. Giá trị lạ → `none`
  /// (fail-open).
  final String action;

  /// Link store đầy đủ cho nút popup — chỉ có khi [action] != `none`.
  final String? url;

  /// Parse 1 dòng; sai kiểu → null (coi như không có dòng → fail-open).
  static HostEntry? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final Object? patch = json['patch'];
    if (patch is! num || patch < 0) return null;
    final Object? rawAction = json['action'];
    final String action = switch (rawAction) {
      'soft' => 'soft',
      'force' => 'force',
      _ => 'none',
    };
    final Object? rawUrl = json['url'];
    final String? url =
        rawUrl is String && rawUrl.trim().isNotEmpty ? rawUrl.trim() : null;
    return HostEntry(patch: patch.toInt(), action: action, url: url);
  }

  @override
  String toString() => 'HostEntry(patch=$patch, action=$action, url=$url)';
}

/// Thông tin tải 1 patch (`patches[str(n)]` của manifest).
class ModuleInfo {
  const ModuleInfo({
    required this.number,
    required this.downloadUrl,
    required this.hash,
    this.size = 0,
    this.minForceUpdate = 0,
    this.gzDownloadUrl,
    this.gzSize = 0,
  });

  final int number;

  /// URL tuyệt đối của file `.bytecode`: `file` ghép tương đối
  /// `<rs_domain>/app/<file>`, hoặc nguyên văn nếu `file` đã là http(s) URL.
  final String downloadUrl;
  final String hash; // hex sha256 của .bytecode

  /// Kích thước byte (thông tin / log; 0 = không khai).
  final int size;

  /// URL bản gzip của `.bytecode` (`gz_file`); null = manifest không có bản
  /// nén → tải [downloadUrl]. [hash] vẫn là sha256 của bytecode ĐÃ giải nén.
  final String? gzDownloadUrl;

  /// Kích thước bản gzip (thông tin / log; 0 = không khai).
  final int gzSize;

  /// Ngưỡng force restart (module version) của patch đích: máy đang chạy
  /// version NHỎ HƠN ngưỡng này thì popup restart mới hiện sau khi tải bản
  /// mới. 0 (hoặc manifest thiếu field) = không ép restart.
  final int minForceUpdate;

  /// Parse `patches[key]`; thiếu `file`/`hash` → null (patch không tải được).
  static ModuleInfo? fromManifest(
    int number,
    Object? json, {
    required String baseUrl,
  }) {
    if (json is! Map<String, dynamic> || number <= 0) return null;
    final Object? rawFile = json['file'];
    final Object? rawHash = json['hash'];
    final String file = rawFile is String ? rawFile.trim() : '';
    final String hash = rawHash is String ? rawHash.trim() : '';
    if (file.isEmpty || hash.isEmpty) return null;
    final Object? rawGz = json['gz_file'];
    final String gzFile = rawGz is String ? rawGz.trim() : '';
    return ModuleInfo(
      number: number,
      downloadUrl: _absUrl(file, baseUrl),
      hash: hash,
      size: (json['size'] as num?)?.toInt() ?? 0,
      minForceUpdate: (json['min_force_update'] as num?)?.toInt() ?? 0,
      gzDownloadUrl: gzFile.isEmpty ? null : _absUrl(gzFile, baseUrl),
      gzSize: (json['gz_size'] as num?)?.toInt() ?? 0,
    );
  }

  static String _absUrl(String file, String baseUrl) =>
      file.startsWith('http://') || file.startsWith('https://')
          ? file
          : '$baseUrl/app/$file';
}

/// `manifest.json` đã parse (schema 1 — docs/release_registry_design.md §5).
class ReleaseManifest {
  const ReleaseManifest({
    required this.schema,
    required this.latest,
    required this.minAllowedPatch,
    required this.softPromptIntervalHours,
    required this.patches,
    required this.hosts,
    this.generatedAt,
  });

  final int schema;
  final String? generatedAt;

  /// Patch mới nhất đã phát hành — client CHỈ dùng để thông tin / log và để
  /// hỏi lại SOFT đã bị từ chối khi số này tăng. Host KHÔNG tải theo số này.
  final int latest;

  /// Thông tin (quyết định force đã tính sẵn vào `action`).
  final int minAllowedPatch;

  /// Khoảng không hỏi lại SOFT sau khi user bấm "Để sau".
  final int softPromptIntervalHours;

  /// `patches` đã parse (key = số patch); patch hỏng field bị bỏ qua.
  final Map<int, ModuleInfo> patches;

  /// `hosts` nguyên văn (tra lười trong [lookup] — dòng hỏng chỉ ảnh hưởng
  /// đúng bản build đó).
  final Map<String, dynamic> hosts;

  /// Parse body; JSON sai / không phải object / thiếu `patches`|`hosts` →
  /// ném [FormatException] (caller coi như không có manifest — fail-open).
  static ReleaseManifest parse(String body, {required String baseUrl}) {
    final Object? json = jsonDecode(body);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('manifest.json không phải JSON object');
    }
    final Object? rawPatches = json['patches'];
    final Object? rawHosts = json['hosts'];
    if (rawPatches is! Map<String, dynamic> ||
        rawHosts is! Map<String, dynamic>) {
      throw const FormatException('manifest.json thiếu patches/hosts');
    }
    final Map<int, ModuleInfo> patches = <int, ModuleInfo>{};
    rawPatches.forEach((String key, Object? value) {
      final int? n = int.tryParse(key.trim());
      if (n == null) return;
      final ModuleInfo? info =
          ModuleInfo.fromManifest(n, value, baseUrl: baseUrl);
      if (info != null) patches[n] = info;
    });
    return ReleaseManifest(
      schema: (json['schema'] as num?)?.toInt() ?? 0,
      generatedAt: json['generated_at'] as String?,
      latest: (json['latest'] as num?)?.toInt() ?? 0,
      minAllowedPatch: (json['min_allowed_patch'] as num?)?.toInt() ?? 0,
      softPromptIntervalHours:
          (json['soft_prompt_interval_hours'] as num?)?.toInt() ?? 24,
      patches: patches,
      hosts: rawHosts,
    );
  }

  /// Dòng của bản build [host]; null = không có (hoặc sai kiểu) → fail-open.
  HostEntry? lookup(HostIdentity host) {
    final Object? byBundle = hosts[host.bundleId];
    if (byBundle is! Map<String, dynamic>) return null;
    final Object? byPlatform = byBundle[host.platform];
    if (byPlatform is! Map<String, dynamic>) return null;
    return HostEntry.fromJson(byPlatform[host.buildKey]);
  }
}

/// Manifest lấy từ đâu (log / test).
enum ManifestSource {
  /// 200 — body mới vừa tải.
  network,

  /// 304 — dùng body đã lưu (ETag khớp).
  notModified,

  /// Lỗi mạng / 5xx — dùng body đã lưu lần trước.
  cache,
}

/// Kết quả [DynModuleLoader.fetchManifest].
typedef ManifestFetch = ({ReleaseManifest manifest, ManifestSource source});

/// Kết quả tra manifest cho 1 bản build (thuần — không I/O).
class ModuleCheck {
  const ModuleCheck({
    required this.updateAvailable,
    this.module,
    this.forceRestart = false,
    this.entry,
    this.latest = 0,
    this.minAllowedPatch = 0,
    this.softPromptIntervalHours = 24,
  });

  /// Không có manifest / không có dòng → không làm gì (fail-open).
  static const ModuleCheck none = ModuleCheck(updateAvailable: false);

  /// true = `entry.patch` > version đang có VÀ patch đó có thông tin tải.
  final bool updateAvailable;

  /// Thông tin tải của patch đích (`patches[entry.patch]`); null khi patch 0
  /// hoặc manifest thiếu patch đó.
  final ModuleInfo? module;

  /// true = CÓ bản mới và version hiện tại < `min_force_update` của patch
  /// đích → host hiện popup restart (ép chạy bản mới ngay). false = không có
  /// bản mới, hoặc bản mới KHÔNG ép (ver hiện tại đã >= ngưỡng) → chỉ lưu
  /// disk, tự áp ở lần mở app sau.
  final bool forceRestart;

  /// Dòng của bản build này (null = không có → không popup, không tải).
  final HostEntry? entry;

  /// `latest` / `min_allowed_patch` / `soft_prompt_interval_hours` của
  /// manifest — host dùng cho quyết định popup SOFT.
  final int latest;
  final int minAllowedPatch;
  final int softPromptIntervalHours;

  /// Tra [manifest] cho [host] đang chạy [currentModuleVersion].
  ///
  /// Loader chỉ đi TỚI: target <= version hiện tại → không tải (KHÔNG
  /// downgrade dù manifest chỉ patch thấp hơn).
  factory ModuleCheck.evaluate(
    ReleaseManifest manifest, {
    required HostIdentity host,
    required int currentModuleVersion,
  }) {
    final HostEntry? entry = manifest.lookup(host);
    if (entry == null) {
      return ModuleCheck(
        updateAvailable: false,
        latest: manifest.latest,
        minAllowedPatch: manifest.minAllowedPatch,
        softPromptIntervalHours: manifest.softPromptIntervalHours,
      );
    }
    final ModuleInfo? module =
        entry.patch > 0 ? manifest.patches[entry.patch] : null;
    final bool updateAvailable =
        module != null && module.number > currentModuleVersion;
    return ModuleCheck(
      updateAvailable: updateAvailable,
      module: module,
      // Ép restart CHỈ khi có bản mới và máy đang chạy dưới ngưỡng
      // min_force_update của patch đích (ver hiện tại >= ngưỡng → không
      // popup, bản mới tự áp ở lần mở app sau).
      forceRestart: module != null &&
          updateAvailable &&
          currentModuleVersion < module.minForceUpdate,
      entry: entry,
      latest: manifest.latest,
      minAllowedPatch: manifest.minAllowedPatch,
      softPromptIntervalHours: manifest.softPromptIntervalHours,
    );
  }

  @override
  String toString() => 'ModuleCheck(updateAvailable=$updateAvailable, '
      'target=${module?.number}, forceRestart=$forceRestart, entry=$entry, '
      'latest=$latest)';
}

/// Lỗi verify (hash) — app bắt riêng để log + fail-open.
class ModuleVerifyException implements Exception {
  ModuleVerifyException(this.message);
  final String message;
  @override
  String toString() => 'ModuleVerifyException: $message';
}

class DynModuleLoader {
  DynModuleLoader({
    required this.baseUrl,
    this.bundleId,
    http.Client? client,
    Directory? cacheDirOverride,
  }) : _client = client ?? http.Client(),
       cacheDirOverride = cacheDirOverride;

  /// Base URL host TĨNH (`rs_domain`) — chứa `app/manifest/<bundleId>.json`
  /// + file `.bytecode` (KHÔNG có server API). Có/không `/` cuối đều được.
  final String baseUrl;

  /// Bundle id của app → tải manifest riêng của app; null/rỗng → manifest
  /// gộp cũ [kReleaseManifestPath].
  final String? bundleId;

  /// [baseUrl] bỏ `/` cuối — ghép `'$_base/app/…'` không sinh `//`.
  String get _base => baseUrl.replaceFirst(RegExp(r'/+$'), '');

  /// Đường dẫn manifest của loader này (tương đối [baseUrl]).
  String get manifestPath {
    final String? b = bundleId?.trim();
    return (b == null || b.isEmpty)
        ? kReleaseManifestPath
        : releaseManifestPathFor(b);
  }

  final http.Client _client;

  // ── Manifest (ETag + cache body tốt gần nhất) ───────────────────────────

  /// Đọc manifest đã lưu (KHÔNG chạm mạng) — boot dùng ngay để quyết định
  /// nhanh, rồi refresh nền. null = chưa có / file hỏng.
  Future<ReleaseManifest?> readCachedManifest() async {
    final ({String? etag, String body})? cached = await _readManifestCache();
    if (cached == null) return null;
    try {
      return ReleaseManifest.parse(cached.body, baseUrl: _base);
    } catch (_) {
      return null;
    }
  }

  /// GET `{rs_domain}/`[manifestPath] kèm `If-None-Match` (ETag lần trước).
  ///
  /// * 200 + parse OK → lưu body + ETag (atomic), trả [ManifestSource.network].
  /// * 304 → body đã lưu ([ManifestSource.notModified]).
  /// * MỌI lỗi khác (mạng / 404 / 5xx / body 200 hỏng) → body đã lưu gần nhất
  ///   ([ManifestSource.cache]): máy chạy tiếp patch đã tải, vẫn áp được
  ///   quyết định đã biết (vd `force`). Body hỏng KHÔNG ghi đè cache tốt.
  /// * Không có body đã lưu → null: gate giữ patch đang có trên đĩa.
  ///
  /// KHÔNG throw.
  /// Gate fetch manifest MỖI lần boot → mạng chập chờn không được giữ
  /// splash lâu: quá hạn → dùng bản đã lưu như lỗi mạng.
  static const Duration manifestTimeout = Duration(seconds: 8);

  Future<ManifestFetch?> fetchManifest() async {
    final ({String? etag, String body})? cached = await _readManifestCache();
    ReleaseManifest? fromCache() {
      if (cached == null) return null;
      try {
        return ReleaseManifest.parse(cached.body, baseUrl: _base);
      } catch (_) {
        return null;
      }
    }

    ManifestFetch? fallbackToCache(String why) {
      final ReleaseManifest? m = fromCache();
      // print('[DynLoader] $why → '
      //     '${m == null ? 'khong co manifest da luu (giu patch dang co)' : 'dung manifest da luu'}');
      return m == null ? null : (manifest: m, source: ManifestSource.cache);
    }

    final http.Response resp;
    try {
      final String? etag = cached?.etag;
      resp = await _client.get(
        Uri.parse('$_base/$manifestPath'),
        headers: <String, String>{
          if (etag != null && etag.isNotEmpty) 'If-None-Match': etag,
        },
      ).timeout(manifestTimeout);
    } catch (e) {
      return fallbackToCache('manifest loi mang ($e)');
    }

    if (resp.statusCode == 304) {
      final ReleaseManifest? m = fromCache();
      // 304 mà cache mất/hỏng (hiếm — cache bị xoá giữa 2 lần đọc) → không
      // có gì để dùng, fail-open; lần sau gửi không ETag sẽ nhận 200.
      if (m == null) return null;
      return (manifest: m, source: ManifestSource.notModified);
    }
    if (resp.statusCode == 200) {
      final ReleaseManifest manifest;
      try {
        manifest = ReleaseManifest.parse(resp.body, baseUrl: _base);
      } catch (e) {
        // Body hỏng: KHÔNG ghi đè cache tốt — chạy theo manifest đã lưu.
        return fallbackToCache('manifest.json hong ($e)');
      }
      await _writeManifestCache(etag: resp.headers['etag'], body: resp.body);
      return (manifest: manifest, source: ManifestSource.network);
    }
    // MỌI lỗi manifest (404 / 5xx / mã lạ) xử lý như lỗi mạng: dùng manifest
    // đã lưu gần nhất → máy vẫn chạy patch đã tải và giữ quyết định đã biết
    // (vd force). Không có cache → null: gate giữ patch đang có trên đĩa.
    return fallbackToCache('manifest HTTP ${resp.statusCode}');
  }

  /// Tra manifest cho [host]. [manifest] null → [fetchManifest] (mạng, có
  /// fallback cache). Không có manifest → [ModuleCheck.none]. KHÔNG throw.
  Future<ModuleCheck> check({
    required HostIdentity host,
    required int currentModuleVersion,
    ReleaseManifest? manifest,
  }) async {
    final ReleaseManifest? m = manifest ?? (await fetchManifest())?.manifest;
    if (m == null) return ModuleCheck.none;
    return ModuleCheck.evaluate(
      m,
      host: host,
      currentModuleVersion: currentModuleVersion,
    );
  }

  /// Check + tải + verify + LƯU DISK — KHÔNG load vào VM. Dùng cả lúc boot
  /// (chưa có cache hợp lệ) lẫn check nền: VM additive-only nên nạp chồng 2
  /// version cùng phiên dễ đụng khai báo — bản mới tự áp ở lần mở sau qua
  /// [readCache] + [loadFromBytes]/[loadFromCache].
  ///
  /// [onCheck] luôn được gọi với kết quả tra manifest (kể cả khi không tải) —
  /// caller lấy `action`/`url` từ đó. [accept] = caller từ chối patch TRƯỚC
  /// khi tải (vd. hash đã bị đánh dấu hỏng — dynmod_health).
  ///
  /// Trả info để caller persist version/hash + cờ `forceRestart`
  /// (ver hiện tại < `min_force_update` của patch đích → mới cần hiện popup
  /// restart); null = không có update. Lỗi tải / hash lệch → ném
  /// [ModuleVerifyException] (caller fail-open).
  Future<({int number, String hash, bool forceRestart})?> checkAndPrefetch({
    required HostIdentity host,
    required int currentModuleVersion,
    ReleaseManifest? manifest,
    void Function(ModuleCheck)? onCheck,
    bool Function(ModuleInfo module)? accept,
  }) async {
    final ModuleCheck checkResult = await check(
      host: host,
      currentModuleVersion: currentModuleVersion,
      manifest: manifest,
    );
    onCheck?.call(checkResult);
    final ModuleInfo? module = checkResult.module;
    if (!checkResult.updateAvailable || module == null) return null;
    if (module.number <= currentModuleVersion) return null;
    if (accept != null && !accept(module)) return null;

    final Uint8List bytes = await downloadModule(module);
    await saveCache(bytes);
    return (
      number: module.number,
      // Hash lowercase chuẩn để lần sau verify cache (so sánh
      // case-insensitive ở verifyBytes, nhưng persist lowercase cho nhất quán).
      hash: module.hash.toLowerCase(),
      forceRestart: checkResult.forceRestart,
    );
  }

  Future<({String? etag, String body})?> _readManifestCache() async {
    try {
      final Directory dir = await _cacheDir();
      final File file = File('${dir.path}/$kManifestCacheFileName');
      if (!await file.exists()) return null;
      final Object? json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return null;
      final Object? body = json['body'];
      if (body is! String || body.isEmpty) return null;
      final Object? etag = json['etag'];
      return (etag: etag is String ? etag : null, body: body);
    } catch (_) {
      return null;
    }
  }

  /// Ghi atomic (tmp → rename). Lỗi → bỏ qua (lần sau tải lại không ETag).
  Future<void> _writeManifestCache({
    required String? etag,
    required String body,
  }) async {
    try {
      final Directory dir = await _cacheDir();
      final File tmp = File('${dir.path}/$kManifestCacheTmpName');
      await tmp.writeAsString(
        jsonEncode(<String, Object?>{'etag': etag, 'body': body}),
        flush: true,
      );
      await tmp.rename('${dir.path}/$kManifestCacheFileName');
    } catch (e) {
      // print('[DynLoader] khong ghi duoc cache manifest: $e');
      print(e);
    }
  }

  // ── Disk cache (1 file duy nhất, ghi atomic) ────────────────────────────
  //
  // Lần đầu: tải 22MB -> verify -> lưu disk -> load. Lần sau: đọc disk
  // (~ms) -> load ngay, rồi mới check manifest nền xem có bản mới không.
  // Không cache = mỗi lần mở app tải lại 22MB.

  /// Thư mục cache (override trong test; mặc định ApplicationSupport/dynmod).
  final Directory? cacheDirOverride;

  Future<Directory> _cacheDir() async {
    final override = cacheDirOverride;
    if (override != null) return override;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/dynmod');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// File cache bytecode duy nhất (`content.bytecode`).
  ///
  /// Máy đang còn file tên cũ ([kLegacyDynModuleCacheFileName] — bản trước
  /// đặt theo tên module) → đổi tên sang tên chung (best-effort), khỏi tải
  /// lại ~22MB sau khi update.
  Future<File> cacheFile() async {
    final Directory dir = await _cacheDir();
    final File file = File('${dir.path}/$kDynModuleCacheFileName');
    if (!await file.exists()) {
      final File legacy = File('${dir.path}/$kLegacyDynModuleCacheFileName');
      if (await legacy.exists()) {
        try {
          await legacy.rename(file.path);
        } catch (_) {
          // Đổi tên lỗi → bỏ qua; lần tải sau ghi đè bình thường.
        }
      }
    }
    return file;
  }

  /// Ghi atomic: tmp -> rename (tránh file dở khi crash giữa chừng).
  Future<void> saveCache(Uint8List bytes) async {
    final dir = await _cacheDir();
    final tmp = File('${dir.path}/$kDynModuleCacheTmpName');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename('${dir.path}/$kDynModuleCacheFileName');
    // Dọn file tên cũ (migration lỡ chưa chạy) — best-effort.
    try {
      final legacy = File('${dir.path}/$kLegacyDynModuleCacheFileName');
      if (await legacy.exists()) await legacy.delete();
    } catch (_) {}
  }

  /// Đọc cache, null nếu chưa có. KHÔNG verify ở đây — caller gọi
  /// [verifyBytes] với hash đã persist trước khi load.
  Future<Uint8List?> readCache() async {
    final file = await cacheFile();
    if (!await file.exists()) return null;
    try {
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  /// Xóa cache (hash lệch / file hỏng) — kể cả file tên cũ còn sót.
  Future<void> clearCache() async {
    try {
      final file = await cacheFile();
      if (await file.exists()) await file.delete();
      final legacy =
          File('${(await _cacheDir()).path}/$kLegacyDynModuleCacheFileName');
      if (await legacy.exists()) await legacy.delete();
    } catch (_) {}
  }

  /// Verify bytes trong cache với hash đã persist từ lần tải trước.
  void verifyCacheBytes(Uint8List bytes, String hash) {
    verifyBytes(
      bytes,
      ModuleInfo(number: 0, downloadUrl: '', hash: hash),
    );
  }

  /// Đọc cache + load vào VM. Ném [ModuleVerifyException]/UnsupportedError
  /// để caller fail-open — KHÔNG tự xóa cache ở đây.
  Future<ContentEntry?> loadFromCache() async {
    final bytes = await readCache();
    if (bytes == null || bytes.isEmpty) return null;
    return loadFromBytes(bytes);
  }

  /// Tải bytecode của [module] đã verify hash: ưu tiên bản gzip (giải nén
  /// rồi verify), lỗi bất kỳ (404, gzip hỏng, hash lệch) → tải bản thô.
  Future<Uint8List> downloadModule(ModuleInfo module) async {
    final String? gzUrl = module.gzDownloadUrl;
    if (gzUrl != null) {
      try {
        final Uint8List bytes = decodeGzip(await download(gzUrl));
        verifyBytes(bytes, module);
        return bytes;
      } catch (_) {
        // rơi xuống bản thô
      }
    }
    final Uint8List bytes = await download(module.downloadUrl);
    verifyBytes(bytes, module);
    return bytes;
  }

  /// Giải nén gzip. Không có magic gzip (1f 8b) → trả nguyên (server / http
  /// client đã tự giải nén theo Content-Encoding).
  static Uint8List decodeGzip(Uint8List bytes) {
    if (bytes.length < 2 || bytes[0] != 0x1f || bytes[1] != 0x8b) return bytes;
    return Uint8List.fromList(gzip.decode(bytes));
  }

  /// GET 1 file (bytecode / bản gzip) từ url.
  Future<Uint8List> download(String url) async {
    final resp = await _client.get(Uri.parse(url));
    if (resp.statusCode != 200) {
      throw ModuleVerifyException('tải module HTTP ${resp.statusCode}');
    }
    return resp.bodyBytes;
  }

  /// sha256(bytes) == hash — chống file hỏng/truncated. KHÔNG verify chữ ký
  /// (app tải bytecode về là chạy — manifest do chính host phục vụ).
  void verifyBytes(Uint8List bytes, ModuleInfo module) {
    final digest = crypto.sha256.convert(bytes);
    if (digest.toString() != module.hash.toLowerCase()) {
      throw ModuleVerifyException('hash mismatch');
    }
  }

  /// loadModuleFromBytes + chạy entrypoint `(ContentRegistry) => register(...)`
  /// với registry cục bộ, trả entry version cao nhất.
  ///
  /// Entrypoint wrapper (../app_package/modules/home_content.dart) trả về
  /// `Object? infoEntrypoint() => (ContentRegistry r) => r.register(entry)` —
  /// dynmod entrypoint payload. Trên engine stock call này ném
  /// UnsupportedError — caller fail-open (đúng kịch bản "đối chứng âm" G4).
  Future<ContentEntry?> loadFromBytes(Uint8List bytes) async {
    final result = await dm.loadModuleFromBytes(bytes);
    // [ContentEntrypoint] trả về void: closure `(r) => r.register(e)` có kiểu
    // `void Function(ContentRegistry)` — KHÔNG là `ContentEntry Function(...)`
    // (bản check cũ từ chối mọi entrypoint thật).
    if (result is! ContentEntrypoint) {
      throw ModuleVerifyException(
          'entrypoint sai kiểu: ${result.runtimeType} '
          '(mong ContentEntrypoint = void Function(ContentRegistry))');
    }
    final registry = LocalContentRegistry();
    result(registry);
    return registry.latest;
  }
}