// Test [AppDynmodGate] với manifest dùng chung (docs/release_registry_design.md
// §5): boot LUÔN fetch manifest mới (lỗi → bản đã lưu), force chặn trước
// khi nạp, chỉ tải đúng patch của dòng bản build, check nền đọc lại manifest.
//
// Loader giả: KHÔNG mạng (manifest/bytecode trả từ bộ nhớ) và KHÔNG engine
// (loadFromBytes trả entry giả) — máy dev/CI không có engine ddm.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:app/shell/dynmod_gate_impl.dart';
import 'package:content_kit/content_kit.dart';
import 'package:dyn_loader/dyn_loader.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loading_kit/flow/dynmod_gate.dart';
import 'package:loading_kit/flow/update_policy.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeEntry implements ContentEntry {
  @override
  String get version => '1.0.0';
  @override
  int get contractVersion => kContentContractVersion;
  @override
  Future<void> init(HostServices host) async {}
  @override
  Widget buildView(BuildContext context) => const SizedBox();
  @override
  Future<Object?> invoke(String method, Map<String, Object?> args) async =>
      null;
}

class _FakeLoader extends DynModuleLoader {
  _FakeLoader({
    required Directory dir,
    this.cachedManifest,
    this.networkManifest,
    required this.files,
  }) : super(baseUrl: 'http://test.local', cacheDirOverride: dir);

  final String? cachedManifest;
  final String? networkManifest;
  final Map<String, Uint8List> files;
  int fetchCalls = 0;
  final List<String> downloads = <String>[];

  @override
  Future<ReleaseManifest?> readCachedManifest() async => cachedManifest == null
      ? null
      : ReleaseManifest.parse(cachedManifest!, baseUrl: baseUrl);

  @override
  Future<ManifestFetch?> fetchManifest() async {
    fetchCalls++;
    final String? body = networkManifest;
    if (body == null) {
      // Như loader thật: mạng lỗi → manifest đã lưu (không có → null).
      final String? cached = cachedManifest;
      if (cached == null) return null;
      return (
        manifest: ReleaseManifest.parse(cached, baseUrl: baseUrl),
        source: ManifestSource.cache,
      );
    }
    return (
      manifest: ReleaseManifest.parse(body, baseUrl: baseUrl),
      source: ManifestSource.network,
    );
  }

  @override
  Future<Uint8List> download(String url) async {
    downloads.add(url);
    final Uint8List? bytes = files[url.split('/').last];
    if (bytes == null) throw ModuleVerifyException('404 $url');
    return bytes;
  }

  @override
  Future<ContentEntry?> loadFromBytes(Uint8List bytes) async => _FakeEntry();
}

void main() {
  final Uint8List v7 = Uint8List.fromList(utf8.encode('bytecode-v7'));
  final Uint8List v14 = Uint8List.fromList(utf8.encode('bytecode-v14'));
  // sha256 hex của 2 chuỗi trên (app không depend `crypto` trực tiếp —
  // tính sẵn bằng `printf 'bytecode-v7' | shasum -a 256`).
  const String h7 =
      '400a39689a636b7923c8265051f0968775464860b89abd4256b8ac2f19b7c385';
  const String h14 =
      '3e3e54caea2304400f56865af34fc3db8fe9df3a22b9e4003cf063d6e7416265';
  final Map<String, Uint8List> files = <String, Uint8List>{
    'p7.bytecode': v7,
    'p14.bytecode': v14,
  };

  const HostIdentity host = HostIdentity(
    bundleId: 'com.example.host1',
    platform: 'android',
    buildNumber: '13',
  );

  String manifest({
    int patch = 7,
    String? action,
    String? url,
    int minForceUpdate14 = 0,
    int latest = 14,
  }) =>
      jsonEncode(<String, Object?>{
        'schema': 1,
        'latest': latest,
        'min_allowed_patch': 0,
        'soft_prompt_interval_hours': 24,
        'patches': <String, Object?>{
          '7': <String, Object?>{'file': 'p7.bytecode', 'hash': h7, 'size': 1},
          '14': <String, Object?>{
            'file': 'p14.bytecode',
            'hash': h14,
            'size': 1,
            'min_force_update': minForceUpdate14,
          },
        },
        'hosts': <String, Object?>{
          'com.example.host1': <String, Object?>{
            'android': <String, Object?>{
              '13': <String, Object?>{
                'patch': patch,
                'action': ?action,
                'url': ?url,
              },
            },
          },
        },
      });

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('dynmod_gate_impl_test');
    SharedPreferences.setMockInitialValues(<String, Object>{});
    PackageInfo.setMockInitialValues(
      appName: 'app',
      packageName: 'com.example.host1',
      version: '1.0.13',
      buildNumber: '13',
      buildSignature: '',
    );
    dynmodCurrentEntry = null;
    dynmodHostServices = null;
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  AppDynmodGate gateWith(_FakeLoader loader) => AppDynmodGate(
        stateDirOverride: tempDir,
        hostIdentityProvider: () async => host,
        loaderFactory: (_) => loader,
      );

  Future<DynmodGateResult> boot(AppDynmodGate gate) => gate.execute(
        rsDomain: 'http://test.local',
        isActive: () => true,
        onSyncVisibilityChanged: ({required bool isSyncing}) {},
        tracker: null,
      );

  /// Máy đã có v[n] trên đĩa + state (fast path).
  Future<void> seedInstalled(int n, Uint8List bytes, String hash) async {
    final _FakeLoader seed = _FakeLoader(dir: tempDir, files: files);
    await seed.saveCache(bytes);
    File('${tempDir.path}/dynmod_state.json')
        .writeAsStringSync(jsonEncode(<String, Object>{'number': n, 'hash': hash}));
  }

  group('execute (boot)', () {
    test('lần đầu (chưa cache manifest) → GET manifest, tải đúng patch đích',
        () async {
      final _FakeLoader loader = _FakeLoader(
        dir: tempDir,
        networkManifest: manifest(),
        files: files,
      );

      final DynmodGateResult r = await boot(gateWith(loader));

      expect(r.loaded, isTrue);
      expect(r.moduleVersion, 7);
      expect(r.decision.action, UpdateAction.none);
      expect(loader.fetchCalls, 1);
      expect(loader.downloads.single, endsWith('/app/p7.bytecode'));
    });

    test('manifest cache ra FORCE, refresh lỗi → vẫn force, không nạp',
        () async {
      await seedInstalled(7, v7, h7);
      final _FakeLoader loader = _FakeLoader(
        dir: tempDir,
        cachedManifest: manifest(
          action: 'force',
          url: 'market://details?id=com.example.hostD',
        ),
        files: files,
      );

      final DynmodGateResult r = await boot(gateWith(loader));

      expect(r.loaded, isFalse);
      expect(r.decision.isForce, isTrue);
      expect(r.decision.url, 'market://details?id=com.example.hostD');
      // Boot luôn fetch 1 lần; lỗi → dùng manifest đã lưu (force).
      expect(loader.fetchCalls, 1);
      expect(dynmodCurrentEntry, isNull);
    });

    test('manifest cache ra FORCE nhưng server đã gỡ force → fast path live',
        () async {
      await seedInstalled(7, v7, h7);
      final _FakeLoader loader = _FakeLoader(
        dir: tempDir,
        cachedManifest: manifest(
          action: 'force',
          url: 'market://details?id=com.example.hostD',
        ),
        networkManifest: manifest(),
        files: files,
      );

      final DynmodGateResult r = await boot(gateWith(loader));

      expect(r.loaded, isTrue);
      expect(r.moduleVersion, 7);
      expect(r.decision.action, UpdateAction.none);
      expect(loader.fetchCalls, 1);
      expect(loader.downloads, isEmpty);
    });

    test('fast path: cache bytecode + mạng lỗi, manifest đã lưu SOFT → live '
        'ngay, decision soft, không tải', () async {
      await seedInstalled(7, v7, h7);
      final _FakeLoader loader = _FakeLoader(
        dir: tempDir,
        cachedManifest: manifest(
          action: 'soft',
          url: 'https://apps.apple.com/app/id1',
        ),
        files: files,
      );

      final DynmodGateResult r = await boot(gateWith(loader));

      expect(r.loaded, isTrue);
      expect(r.moduleVersion, 7);
      expect(r.decision.isSoft, isTrue);
      expect(loader.fetchCalls, 1);
      expect(loader.downloads, isEmpty);
    });

    test('không có dòng cho bản build → demo, không tải', () async {
      final _FakeLoader loader = _FakeLoader(
        dir: tempDir,
        networkManifest: manifest(),
        files: files,
      );
      final AppDynmodGate gate = AppDynmodGate(
        stateDirOverride: tempDir,
        hostIdentityProvider: () async => const HostIdentity(
          bundleId: 'com.other',
          platform: 'android',
          buildNumber: '1',
        ),
        loaderFactory: (_) => loader,
      );

      final DynmodGateResult r = await boot(gate);

      expect(r.loaded, isFalse);
      expect(r.decision, UpdateDecision.none);
      expect(loader.downloads, isEmpty);
    });

    test('manifest 404 lần đầu → demo (fail-open)', () async {
      final _FakeLoader loader = _FakeLoader(dir: tempDir, files: files);

      final DynmodGateResult r = await boot(gateWith(loader));

      expect(r.loaded, isFalse);
      expect(r.decision, UpdateDecision.none);
    });
  });

  group('executeBackground', () {
    Future<DynmodBackgroundResult> bg(_FakeLoader loader) =>
        gateWith(loader).executeBackground(
          rsDomain: 'http://test.local',
          isActive: () => false,
        );

    test('manifest mới ra FORCE → decision force, KHÔNG tải patch', () async {
      await seedInstalled(7, v7, h7);
      dynmodCurrentEntry = _FakeEntry();
      final _FakeLoader loader = _FakeLoader(
        dir: tempDir,
        networkManifest: manifest(
          patch: 14,
          action: 'force',
          url: 'market://details?id=com.example.hostD',
        ),
        files: files,
      );

      final DynmodBackgroundResult r = await bg(loader);

      expect(r.decision!.isForce, isTrue);
      expect(r.restartVersion, isNull);
      expect(loader.downloads, isEmpty);
    });

    test('patch đích mới + dưới min_force_update → tải + restartVersion',
        () async {
      await seedInstalled(7, v7, h7);
      dynmodCurrentEntry = _FakeEntry();
      final _FakeLoader loader = _FakeLoader(
        dir: tempDir,
        networkManifest: manifest(patch: 14, minForceUpdate14: 10),
        files: files,
      );

      final DynmodBackgroundResult r = await bg(loader);

      expect(r.restartVersion, 14);
      expect(r.decision!.action, UpdateAction.none);
      expect(await loader.readCache(), v14);
    });

    test('patch đích mới, đủ ngưỡng → tải nhưng không popup restart', () async {
      await seedInstalled(7, v7, h7);
      dynmodCurrentEntry = _FakeEntry();
      final _FakeLoader loader = _FakeLoader(
        dir: tempDir,
        networkManifest: manifest(patch: 14),
        files: files,
      );

      final DynmodBackgroundResult r = await bg(loader);

      expect(r.restartVersion, isNull);
      expect(loader.downloads.single, endsWith('/app/p14.bytecode'));
    });

    test('không có manifest (404) → (null, null)', () async {
      dynmodCurrentEntry = _FakeEntry();
      final _FakeLoader loader = _FakeLoader(dir: tempDir, files: files);

      final DynmodBackgroundResult r = await bg(loader);

      expect(r.decision, isNull);
      expect(r.restartVersion, isNull);
    });

    test('phiên không live → không làm gì', () async {
      final _FakeLoader loader = _FakeLoader(
        dir: tempDir,
        networkManifest: manifest(patch: 14),
        files: files,
      );

      final DynmodBackgroundResult r = await bg(loader);

      expect(r.decision, isNull);
      expect(loader.fetchCalls, 0);
    });
  });

  test('readHostIdentity: platform android + package_info → key tra manifest',
      () async {
    final HostIdentity? id =
        await AppDynmodGate.readHostIdentity(platformOverride: 'android');
    expect(id!.bundleId, 'com.example.host1');
    expect(id.platform, 'android');
    expect(id.buildKey, '13');
  });
}
