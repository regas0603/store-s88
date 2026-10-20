// Implementation phía host cho interface [DynmodGate] của
// loading_kit (dependency inversion: loading_kit không biết dyn_loader).
//
// Base URL: dùng `rs_domain` từ Git JSON per-app (host tĩnh chứa
// `app/manifest/<bundleId>.json` riêng từng app + file `.bytecode` — không có server API).
// Bản build tra dòng của mình bằng bundleId + platform + buildNumber
// (docs/release_registry_design.md §5) — KHÔNG bake gì vào binary.
//
// Fail-open: MỌI lỗi (mạng, hash, engine stock không hỗ trợ
// loadModuleFromBytes) → trả loaded=false → shell về demo, KHÔNG crash.
import 'dart:io';

import 'package:content_kit/content_kit.dart';
import 'package:dyn_loader/dyn_loader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:loading_kit/flow/boot_config.dart';
import 'package:loading_kit/flow/boot_step.dart';
import 'package:loading_kit/flow/dynmod_gate.dart';
import 'package:loading_kit/flow/update_policy.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dynmod_health.dart';
import 'dynmod_host_services.dart';
import 'dynmod_state_store.dart';

/// Version module hiện tại đã cài (persist), key SharedPreferences.
const String _kDynmodVersionKey = 'dynmod_module_version';

/// sha256 hex của bytecode đã lưu cache (để verify lại sau restart).
const String _kDynmodHashKey = 'dynmod_module_hash';

/// Entry của module đang chạy (null = chưa có) — [DynmodLiveView] đọc để render.
ContentEntry? dynmodCurrentEntry;

/// [HostServices] đưa cho module đang chạy (content_kit v2) — set cùng lúc
/// với [dynmodCurrentEntry].
HostServices? dynmodHostServices;

/// Gate dynmod chạy thay gate update OTA.
class AppDynmodGate implements DynmodGate {
  AppDynmodGate({
    this.stateDirOverride,
    this.hostIdentityProvider,
    this.loaderFactory,
  });

  /// Ghi file state `dynmod_state.json` vào thư mục này; null = app support
  /// dir (platform). Chỉ test inject — app thật không truyền.
  final Directory? stateDirOverride;

  /// Danh tính bản build (bundleId/platform/buildNumber); null = đọc platform
  /// thật ([readHostIdentity]). Chỉ test inject.
  final Future<HostIdentity?> Function()? hostIdentityProvider;

  /// Dựng [DynModuleLoader] cho rs_domain (test inject HTTP giả + thư mục
  /// cache tạm); null = loader thật.
  final DynModuleLoader Function(String baseUrl)? loaderFactory;

  /// true = isolate này đã nạp module hỏng 1 lần (VM additive-only: lib đã
  /// đăng ký dở vẫn ở lại) → KHÔNG thử load lần 2 cùng phiên (chắc chắn dính
  /// "already loaded"), chờ cold start sau.
  static bool _loadPoisoned = false;

  DynmodStateStore? _stateStore;
  DynmodStateStore get _store => _stateStore ??=
      DynmodStateStore(dirOverride: stateDirOverride);

  /// Danh tính bản build đang chạy — key tra `hosts` của manifest:
  /// bundleId ([BootConfig.loadAppBundleId]), platform (`android`/`ios`),
  /// buildNumber (versionCode / CFBundleVersion qua package_info_plus).
  ///
  /// [platformOverride] chỉ cho test. Platform khác / đọc lỗi / buildNumber
  /// rỗng → null (không tra được dòng → fail-open: không popup, không tải).
  static Future<HostIdentity?> readHostIdentity({
    String? platformOverride,
  }) async {
    final String? platform = platformOverride ??
        (Platform.isAndroid
            ? 'android'
            : Platform.isIOS
                ? 'ios'
                : null);
    if (platform == null) return null;
    try {
      final String bundleId = await BootConfig.loadAppBundleId();
      final PackageInfo info = await PackageInfo.fromPlatform();
      final String buildNumber = info.buildNumber.trim();
      if (bundleId.isEmpty || buildNumber.isEmpty) return null;
      return HostIdentity(
        bundleId: bundleId,
        platform: platform,
        buildNumber: buildNumber,
      );
    } catch (e) {
      // print('[DynmodGate] doc bundleId/buildNumber loi → fail-open: $e');
      print(e);
      return null;
    }
  }

  Future<HostIdentity?> _host() async {
    final provider = hostIdentityProvider;
    return provider != null ? provider() : readHostIdentity();
  }

  @override
  Future<DynmodGateResult> execute({
    required String? rsDomain,
    required bool Function() isActive,
    required void Function({required bool isSyncing})
        onSyncVisibilityChanged,
    required BootStepTracker? tracker,
  }) async {
    final String? baseUrl = rsDomain;
    if (baseUrl == null || baseUrl.isEmpty) {
      // print('[DynmodGate] khong co rs_domain → fail-open (demo)');
      return (loaded: false, moduleVersion: 0, decision: UpdateDecision.none);
    }
    // Phiên này đã nạp hỏng 1 lần: VM giữ lib đăng ký dở → thử lại chỉ dính
    // "already loaded". Fail-open ngay, chờ cold start sau (gate đã xóa cache
    // + state ở lần lỗi trước nên lần mở sau sẽ tải bản mới).
    if (_loadPoisoned) {
      // print('[DynmodGate] isolate da poisoned (load hong truoc do) '
      //     '→ fail-open, cho cold start');
      return (loaded: false, moduleVersion: 0, decision: UpdateDecision.none);
    }
    UpdateDecision decision = UpdateDecision.none;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final DynmodState? state = await _readState(prefs);
      final int currentVersion = state?.number ?? 0;

      final HostIdentity? host = await _host();
      final loader = _buildLoader(baseUrl, host?.bundleId);
      final DynmodHealth health = DynmodHealth(prefs);

      // (A) LUÔN fetch manifest mới lúc boot (ETag → thường 304, rẻ): có thể
      // vừa ra patch mới / đổi force-soft. Lỗi mạng / timeout / HTTP lỗi →
      // fetchManifest tự dùng bản đã lưu → máy offline vẫn chạy cache.
      // Patch mới hơn cache KHÔNG tải ở đây: fast path chạy cache, bản mới
      // tải nền (executeBackground) và áp ở lần mở sau.
      final ReleaseManifest? manifest = (await loader.fetchManifest())?.manifest;
      decision = _decisionOf(_evaluate(manifest, host, currentVersion));
      // print('[DynmodGate] host=$host manifest='
      //     '${manifest == null ? '(khong co)' : 'ok'} → $decision');
      // FORCE: không nạp, không tải — coordinator chặn bằng dialog, không live.
      if (decision.isForce) {
        return (loaded: false, moduleVersion: currentVersion, decision: decision);
      }

      // (0) Fast path: bytecode còn trên disk -> verify lại bằng hash đã
      // persist -> load ngay -> LIVE NGAY, KHÔNG chờ mạng. Check bản mới
      // do executeBackground() làm nền SAU khi host đã vào live.
      if (currentVersion > 0 && state != null) {
        final String savedHash = state.hash;
        if (savedHash.isNotEmpty) {
          try {
            final Uint8List? cached = await loader.readCache();
            if (cached != null && cached.isNotEmpty) {
              loader.verifyCacheBytes(cached, savedHash);
              if (!await health.beginBoot(savedHash)) {
                // P6: bản này mở nhiều lần liền không báo khoẻ → bỏ, không
                // tải lại đúng hash này (chờ manifest ra bản khác).
                // print('[DynmodGate] cache v$currentVersion bi danh dau HONG '
                //     '(khong bao khoe) → bo, cho ban moi tu manifest');
                await loader.clearCache();
                await _writeState(prefs, (number: 0, hash: ''));
              } else {
                final ContentEntry? cachedEntry =
                    await loader.loadFromBytes(cached);
                if (cachedEntry != null) {
                  if (await _activate(cachedEntry,
                      number: currentVersion,
                      hash: savedHash,
                      baseUrl: baseUrl,
                      health: health)) {
                    // print('[DynmodGate] cache v$currentVersion OK → live ngay '
                    //     '(check ban moi sau nen)');
                    return (
                      loaded: true,
                      moduleVersion: currentVersion,
                      decision: decision,
                    );
                  }
                  await loader.clearCache();
                  await _writeState(prefs, (number: 0, hash: ''));
                  return (loaded: false, moduleVersion: 0, decision: decision);
                }
                // File rỗng / entry lạ → coi như hỏng, tải lại.
                await loader.clearCache();
              }
            }
          } on UnsupportedError {
            // Engine stock không load được — mạng KHÔNG sửa được lỗi này →
            // fail-open ngay, KHÔNG tải phí 22MB (file cache giữ nguyên).
            // print('[DynmodGate] engine khong ho tro loadModuleFromBytes '
            //     '→ fail-open (khong tai phi)');
            return (
              loaded: false,
              moduleVersion: currentVersion,
              decision: decision,
            );
          } on StateError catch (e) {
            // VM từ chối bytecode (vd. "already loaded" do anchor cũ/host
            // lệch): cache + state hiện tại đã lỗi → xóa, rơi xuống (1) tải
            // lại bản mới thay vì kẹt file hỏng.
            // print('[DynmodGate] VM tu choi bytecode → xoa cache, tai moi: $e');
            print(e);
            await loader.clearCache();
            await _store.write((number: 0, hash: ''));
          } catch (e) {
            // Cache hỏng/hash lệch → xóa, rơi xuống (1) tải lại.
            // print('[DynmodGate] cache loi → bo qua, tai moi: $e');
            print(e);
            await loader.clearCache();
          }
        }
      }

      // (1) Không có cache hợp lệ (lần đầu / cache hỏng): tải theo manifest
      // vừa fetch ở (A).
      if (manifest == null || host == null) {
        // print('[DynmodGate] khong co manifest / khong doc duoc host '
        //     '→ fail-open (demo)');
        return (loaded: false, moduleVersion: currentVersion, decision: decision);
      }

      // Check + TẢI BLOCKING 1 lần (verify + LƯU DISK, chưa load).
      // currentModuleVersion=0 để lấy patch đích kể cả bằng version đã
      // persist — cache vừa bị xóa thì version cũ không còn ý nghĩa.
      final pref = await loader.checkAndPrefetch(
        host: host,
        currentModuleVersion: 0,
        manifest: manifest,
        onCheck: (ModuleCheck check) {
          if (check.updateAvailable) {
            tracker?.advanceTo(BootStep.download);
          }
        },
        // P6: hash đã bị đánh dấu hỏng → không tải lại (chờ manifest ra bản khác).
        accept: (ModuleInfo m) => !health.isBad(m.hash),
      );
      if (pref == null) {
        // print('[DynmodGate] manifest khong co patch cho $host '
        //     '(current=v$currentVersion)');
        return (loaded: false, moduleVersion: currentVersion, decision: decision);
      }
      if (!isActive()) {
        return (loaded: false, moduleVersion: currentVersion, decision: decision);
      }

      // (2) Persist TRƯỚC khi load: kể cả engine stock không load được thì
      // lần mở sau fast path fail-open ngay, không tải lại 22MB. Ghi FILE
      // trước (atomic), prefs sau — 2 nguồn self-heal khi 1 nguồn mất.
      await _writeState(
        prefs,
        (number: pref.number, hash: pref.hash),
      );

      // (3) Load từ cache vừa ghi + giữ entry cho [DynmodLiveView].
      if (!await health.beginBoot(pref.hash)) {
        await loader.clearCache();
        return (loaded: false, moduleVersion: pref.number, decision: decision);
      }
      ContentEntry? entry;
      try {
        entry = await loader.loadFromCache();
      } on UnsupportedError {
        // Engine stock — cache giữ nguyên cho fast path lần sau fail-open sớm.
        rethrow;
      } catch (e) {
        // VM từ chối (vd. "already loaded" do anchor cũ/host lệch): xóa cache
        // + state để lần mở sau tải lại bản mới thay vì kẹt file lỗi.
        // print('[DynmodGate] load that bai → xoa cache + state: $e');
        print(e);
        await loader.clearCache();
        await _store.write((number: 0, hash: ''));
        rethrow;
      }
      if (entry == null) {
        await loader.clearCache();
        return (loaded: false, moduleVersion: pref.number, decision: decision);
      }
      if (!await _activate(entry,
          number: pref.number,
          hash: pref.hash,
          baseUrl: baseUrl,
          health: health)) {
        await loader.clearCache();
        await _writeState(prefs, (number: 0, hash: ''));
        return (loaded: false, moduleVersion: 0, decision: decision);
      }
      // print('[DynmodGate] module v${pref.number} da nap + luu disk '
      //     '(khong restart)');
      return (loaded: true, moduleVersion: pref.number, decision: decision);
    } catch (e) {
      // Engine stock ném UnsupportedError từ loadModuleFromBytes — đúng
      // kịch bản đối chứng âm G4: bắt ở đây → fail-open, không crash.
      // StateError (vd. "already loaded") = VM đã đăng ký dở lib của module
      // hỏng vào isolate → đánh dấu poisoned để không thử lại cùng phiên.
      if (e is StateError) _loadPoisoned = true;
      // print('[DynmodGate] LOI → fail-open (demo): $e\n$st');
      print(e);
      return (loaded: false, moduleVersion: 0, decision: decision);
    }
  }

  // ── Giai đoạn 2: check bản mới NỀN ────────────────────────────────────────

  /// Refresh manifest (ETag) + tải bản mới NỀN.
  ///
  /// * `decision` = quyết định đọc lại từ manifest mới (BootShell hiện popup
  ///   soft/force trên màn live); null = không có manifest (404 / lỗi mạng mà
  ///   chưa có cache) → giữ nguyên, không popup.
  /// * `restartVersion` CHỈ KHI cần hiện popup restart — tức là ver hiện tại
  ///   < `min_force_update` của patch đích (`forceRestart`); nếu ver hiện tại
  ///   đã >= ngưỡng thì null (bản mới vẫn đã tải + lưu disk → tự áp ở lần mở
  ///   app sau, KHÔNG làm phiền user).
  @override
  Future<DynmodBackgroundResult> executeBackground({
    required String? rsDomain,
    required bool Function() isActive,
  }) async {
    final String? baseUrl = rsDomain;
    if (baseUrl == null || baseUrl.isEmpty) {
      return (restartVersion: null, decision: null);
    }
    // Chỉ chạy khi phiên này ĐANG LIVE (đã nạp được module) — fail-open
    // (engine stock / server lỗi) mà tải về cũng không load được → tránh phí.
    if (dynmodCurrentEntry == null) {
      return (restartVersion: null, decision: null);
    }
    UpdateDecision? decision;
    try {
      final prefs = await SharedPreferences.getInstance();
      final int currentVersion = (await _readState(prefs))?.number ?? 0;
      final HostIdentity? host = await _host();
      if (host == null) return (restartVersion: null, decision: null);
      final loader = _buildLoader(baseUrl, host.bundleId);
      final DynmodHealth health = DynmodHealth(prefs);

      final ManifestFetch? fetched = await loader.fetchManifest();
      if (fetched == null) {
        // print('[DynmodGate-bg] loi manifest + chua co ban da luu → giu nguyen patch dang chay');
        return (restartVersion: null, decision: null);
      }
      final ModuleCheck check = ModuleCheck.evaluate(
        fetched.manifest,
        host: host,
        currentModuleVersion: currentVersion,
      );
      decision = _decisionOf(check);
      // print('[DynmodGate-bg] manifest ${fetched.source.name} → $decision');
      // FORCE: user phải cài app khác/bản mới — tải patch là phí.
      if (decision.isForce) {
        return (restartVersion: null, decision: decision);
      }

      final pref = await loader.checkAndPrefetch(
        host: host,
        currentModuleVersion: currentVersion,
        manifest: fetched.manifest,
        accept: (ModuleInfo m) => !health.isBad(m.hash),
      );
      if (pref == null) {
        // print('[DynmodGate-bg] khong co ban moi (dang chay v$currentVersion)');
        return (restartVersion: null, decision: decision);
      }
      // KHÔNG check isActive() ở đây: bg chỉ chạy khi đã live → splash đã bị
      // unmount → isActive() (mounted của splash) luôn false. Ghi state là
      // best-effort (atomic, an toàn kể cả khi widget host đã tháo) — popup
      // restart do BootShell (root) trình bày.
      // Chỉ LƯU DISK — KHÔNG load vào phiên này (VM additive-only: nạp chồng
      // 2 version dễ đụng khai báo). Bản mới tự áp ở lần mở sau qua fast path.
      // Ghi FILE trước (atomic), prefs sau — 2 nguồn self-heal khi 1 nguồn mất.
      await _writeState(
        prefs,
        (number: pref.number, hash: pref.hash),
      );
      // Quyết định popup: CHỈ ép restart khi ver hiện tại < min_force_update
      // của patch đích. Đã đủ ngưỡng → không popup, bản mới tự áp lần mở sau.
      if (!pref.forceRestart) {
        // print('[DynmodGate-bg] da tai v${pref.number} ve disk — hien tai '
        //     'v$currentVersion khong nho hon min_force_update → KHONG hien '
        //     'popup, tu ap o lan mo app sau');
        return (restartVersion: null, decision: decision);
      }
      // print('[DynmodGate-bg] da tai v${pref.number} ve disk — ver hien tai '
      //     'v$currentVersion < min_force_update → gui version cho popup restart');
      return (restartVersion: pref.number, decision: decision);
    } catch (e) {
      // print('[DynmodGate-bg] loi (bo qua, van chay ver cu): $e');
      print(e);
      return (restartVersion: null, decision: decision);
    }
  }

  /// Tra manifest (null-safe): thiếu manifest / host → [ModuleCheck.none].
  static ModuleCheck _evaluate(
    ReleaseManifest? manifest,
    HostIdentity? host,
    int currentVersion,
  ) {
    if (manifest == null || host == null) return ModuleCheck.none;
    return ModuleCheck.evaluate(
      manifest,
      host: host,
      currentModuleVersion: currentVersion,
    );
  }

  /// Dòng bản build → [UpdateDecision] của loading_kit (không có dòng → none).
  static UpdateDecision _decisionOf(ModuleCheck check) {
    final HostEntry? e = check.entry;
    if (e == null) return UpdateDecision.none;
    return UpdateDecision.fromManifest(
      action: e.action,
      url: e.url,
      targetPatch: e.patch,
      latest: check.latest,
    );
  }

  /// Nhận entry vừa nạp: kiểm hợp đồng (content_kit v2) rồi dựng
  /// [HostServices]. false = module đòi hợp đồng mới hơn host → đánh dấu
  /// hỏng (không tải lại) + poisoned (lib đã nạp vào isolate, không gỡ được).
  Future<bool> _activate(
    ContentEntry entry, {
    required int number,
    required String hash,
    required String baseUrl,
    required DynmodHealth health,
  }) async {
    if (entry.contractVersion > kContentContractVersion) {
      // print('[DynmodGate] module v$number doi hop dong '
      //     'v${entry.contractVersion} > host v$kContentContractVersion '
      //     '→ bo (can host moi)');
      await health.markBad(hash);
      _loadPoisoned = true;
      return false;
    }
    dynmodHostServices = await AppHostServices.create(
      moduleVersion: number,
      moduleHash: hash,
      appConfig: <String, Object?>{'rs_domain': baseUrl},
      health: health,
    );
    dynmodCurrentEntry = entry;
    return true;
  }

  // ── State 2 nguồn: file backup (dynmod_state.json) + SharedPreferences ──

  /// Đọc state module từ CẢ 2 nguồn rồi gộp (lấy number lớn nhất — nguồn đã
  /// khớp bytecode trên đĩa, vì `_writeState` ghi file TRƯỚC prefs sau khi
  /// `saveCache` xong). File hỏng → prefs cứu; prefs mất (update store) →
  /// file cứu; cả 2 thiếu → null (chưa từng cài). Tự sửa nguồn yếu hơn.
  Future<DynmodState?> _readState(SharedPreferences prefs) async {
    final DynmodState? fromFile = await _store.read();
    final String? savedHash = prefs.getString(_kDynmodHashKey);
    final int savedNumber = prefs.getInt(_kDynmodVersionKey) ?? 0;
    final DynmodState? fromPrefs =
        (savedNumber > 0 && savedHash != null && savedHash.isNotEmpty)
            ? (number: savedNumber, hash: savedHash)
            : null;
    final DynmodState? merged = DynmodStateStore.merge(fromFile, fromPrefs);
    if (merged == null) return null;
    if (fromFile == null ||
        fromFile.number != merged.number ||
        fromFile.hash != merged.hash) {
      await _store.write(merged); // best-effort — lỗi thì prefs vẫn đúng
    }
    if (fromPrefs == null ||
        fromPrefs.number != merged.number ||
        fromPrefs.hash != merged.hash) {
      await _persistPrefs(prefs, merged);
    }
    return merged;
  }

  /// Ghi state: FILE trước (atomic tmp→rename, bản sao sống qua store update),
  /// prefs sau — đúng thứ tự đã dùng khi persist ngay sau `saveCache`.
  Future<void> _writeState(SharedPreferences prefs, DynmodState state) async {
    await _store.write(state);
    await _persistPrefs(prefs, state);
  }

  Future<void> _persistPrefs(SharedPreferences prefs, DynmodState s) async {
    await prefs.setInt(_kDynmodVersionKey, s.number);
    await prefs.setString(_kDynmodHashKey, s.hash);
  }

  /// Loader với rs_domain (host tĩnh manifest) — tải manifest RIÊNG của app
  /// `{rs_domain}/app/manifest/<bundleId>.json`.
  ///
  /// Nhiều app (mỗi app 1 `main_app` khác nhau) dùng CHUNG 1 bytecode — tool
  /// đã tính sẵn patch cao nhất mỗi bản build chạy được (theo ABI) vào
  /// `hosts` của manifest, client không tự so anchor
  /// (docs/release_registry_design.md §3).
  DynModuleLoader _buildLoader(String baseUrl, String? bundleId) =>
      loaderFactory?.call(baseUrl) ??
      DynModuleLoader(baseUrl: baseUrl, bundleId: bundleId);
}

/// Màn live khi dynmod BẬT: render entry của module (nếu có). Module tự bọc
/// ProviderScope / khởi tạo nội bộ bên trong buildView() — host KHÔNG còn
/// nhận/ung `List<Override>` (biên giới hẹp: ContentEntry + HostServices + Widget).
/// Entry null (dynmod tắt / chưa nạp) → fallback màn "sạch" cũ.
class DynmodLiveView extends StatefulWidget {
  const DynmodLiveView({super.key, required this.fallback});

  /// Màn fallback (TrueScreen của bản release) khi chưa có module nào.
  final WidgetBuilder fallback;

  @override
  State<DynmodLiveView> createState() => _DynmodLiveViewState();
}

class _DynmodLiveViewState extends State<DynmodLiveView> {
  ContentEntry? _entry;
  bool _initing = false;

  @override
  void initState() {
    super.initState();
    _entry = dynmodCurrentEntry;
    if (_entry != null) {
      _initing = true;
      _entry!.init(dynmodHostServices!).then((_) {
        if (!mounted) return;
        setState(() => _initing = false);
      }).catchError((Object e) {
        if (!mounted) return;
        // init() lỗi → vẫn vào buildView: module tự xử lý/fail-open bên trong.
        // print('[DynmodLiveView] init() lỗi → vào buildView luôn: $e');
        print(e);
        setState(() => _initing = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_entry == null || _initing) {
      // Chưa có module (hoặc đang init) → màn fallback phải TỰ dựng
      // MaterialApp: `BootShell` render live ở ROOT mà KHÔNG bọc MaterialApp
      // (module khi có sẽ tự dựng app của nó) nên fallback không có Material
      // ancestor.
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: widget.fallback(context),
      );
    }
    // Module (game) tự dựng MaterialApp.router của nó — BootShell phải dùng
    // ownRootMaterialApp=false khi dynmod bật (tránh lồng 2 MaterialApp,
    // flutter/flutter#142585).
    return _entry!.buildView(context);
  }
}