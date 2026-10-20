// Test manifest dùng chung `{rs_domain}/app/manifest.json`
// (docs/release_registry_design.md §5): tra dòng bản build theo
// bundleId/platform/buildNumber, chỉ tải đúng `patch` của dòng, ETag + cache
// body tốt gần nhất; lỗi manifest (mạng / 404 / 5xx / body hỏng) → dùng bản
// đã lưu, không có thì fail-open (giữ patch đang có).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dyn_loader/dyn_loader.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  final Uint8List bytesV7 = Uint8List.fromList(utf8.encode('module-bytecode-v7'));
  final Uint8List bytesV14 =
      Uint8List.fromList(utf8.encode('module-bytecode-v14'));
  final String hashV7 = crypto.sha256.convert(bytesV7).toString();
  final String hashV14 = crypto.sha256.convert(bytesV14).toString();

  const HostIdentity hostA = HostIdentity(
    bundleId: 'com.example.hostA',
    platform: 'android',
    buildNumber: '12',
  );
  const HostIdentity hostAIos = HostIdentity(
    bundleId: 'com.example.hostA',
    platform: 'ios',
    buildNumber: '9',
  );
  const HostIdentity host1 = HostIdentity(
    bundleId: 'com.example.host1',
    platform: 'android',
    buildNumber: '13',
  );

  late Directory tempDir;

  Map<String, Object?> manifestMap({
    int minForceUpdate14 = 0,
    String file14 = 'app_content_ab12cd34.bytecode',
    String? hash14,
    bool gz14 = false,
  }) =>
      <String, Object?>{
        'schema': 1,
        'generated_at': '2026-12-01T00:00:00Z',
        'latest': 14,
        'min_allowed_patch': 8,
        'soft_prompt_interval_hours': 24,
        'patches': <String, Object?>{
          '7': <String, Object?>{
            'file': 'app_content_73ffe17f.bytecode',
            'hash': hashV7,
            'size': 7500000,
            'min_force_update': 0,
          },
          '14': <String, Object?>{
            'file': file14,
            'hash': hash14 ?? hashV14,
            'size': 7700000,
            'min_force_update': minForceUpdate14,
            if (gz14) 'gz_file': '$file14.gz',
            if (gz14) 'gz_size': 3000000,
          },
        },
        'hosts': <String, Object?>{
          'com.example.hostA': <String, Object?>{
            'android': <String, Object?>{
              '12': <String, Object?>{
                'patch': 7,
                'action': 'force',
                'url': 'market://details?id=com.example.hostD',
              },
            },
            'ios': <String, Object?>{
              '9': <String, Object?>{
                'patch': 7,
                'action': 'soft',
                'url': 'https://apps.apple.com/app/id1234567890',
              },
            },
          },
          'com.example.host1': <String, Object?>{
            'android': <String, Object?>{
              '13': <String, Object?>{'patch': 14},
              '5': <String, Object?>{'patch': 0},
            },
          },
        },
      };

  /// Server giả: manifest + ETag + 2 file bytecode; ghi lại request.
  /// [manifestStatus] != 200 để giả 404/5xx; [throwOnManifest] giả lỗi mạng.
  final List<http.Request> requests = <http.Request>[];
  MockClient server({
    String? manifestBody,
    String etag = '"v1"',
    int manifestStatus = 200,
    bool throwOnManifest = false,
    bool serveGz = true,
  }) =>
      MockClient((http.Request req) async {
        requests.add(req);
        final String path = req.url.toString();
        if (path.endsWith('/app/manifest.json')) {
          if (throwOnManifest) {
            throw const SocketException('offline');
          }
          if (manifestStatus != 200) {
            return http.Response('err', manifestStatus);
          }
          if (req.headers['If-None-Match'] == etag) {
            return http.Response('', 304);
          }
          return http.Response(
            manifestBody ?? jsonEncode(manifestMap()),
            200,
            headers: <String, String>{'etag': etag},
          );
        }
        if (path.endsWith('app_content_73ffe17f.bytecode')) {
          return http.Response.bytes(bytesV7, 200);
        }
        if (path.endsWith('app_content_ab12cd34.bytecode.gz')) {
          return serveGz
              ? http.Response.bytes(gzip.encode(bytesV14), 200)
              : http.Response('not found', 404);
        }
        if (path.contains('app_content_ab12cd34.bytecode')) {
          return http.Response.bytes(bytesV14, 200);
        }
        return http.Response('not found', 404);
      });

  DynModuleLoader loaderWith(http.Client client) => DynModuleLoader(
        baseUrl: 'http://test.local',
        client: client,
        cacheDirOverride: tempDir,
      );

  setUp(() {
    requests.clear();
    tempDir = Directory.systemTemp.createTempSync('dyn_manifest_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('ReleaseManifest.parse + lookup', () {
    test('parse đủ field top-level + patches', () {
      final ReleaseManifest m = ReleaseManifest.parse(
        jsonEncode(manifestMap()),
        baseUrl: 'http://test.local',
      );
      expect(m.schema, 1);
      expect(m.latest, 14);
      expect(m.minAllowedPatch, 8);
      expect(m.softPromptIntervalHours, 24);
      expect(m.patches.keys, unorderedEquals(<int>[7, 14]));
      expect(m.patches[7]!.size, 7500000);
      expect(m.patches[7]!.hash, hashV7);
    });

    test('file tương đối → ghép <rs>/app/<file>', () {
      final ReleaseManifest m = ReleaseManifest.parse(
        jsonEncode(manifestMap()),
        baseUrl: 'http://test.local',
      );
      expect(m.patches[7]!.downloadUrl,
          'http://test.local/app/app_content_73ffe17f.bytecode');
    });

    test('file là URL tuyệt đối (http/https) → nhận nguyên văn', () {
      const String abs = 'https://cdn.other/x/app_content_ab12cd34.bytecode';
      final ReleaseManifest m = ReleaseManifest.parse(
        jsonEncode(manifestMap(file14: abs)),
        baseUrl: 'http://test.local',
      );
      expect(m.patches[14]!.downloadUrl, abs);
    });

    test('tra dòng: action/url/patch; thiếu action → none', () {
      final ReleaseManifest m = ReleaseManifest.parse(
        jsonEncode(manifestMap()),
        baseUrl: 'http://test.local',
      );
      final HostEntry a = m.lookup(hostA)!;
      expect(a.patch, 7);
      expect(a.action, 'force');
      expect(a.url, 'market://details?id=com.example.hostD');
      expect(m.lookup(hostAIos)!.action, 'soft');
      final HostEntry h1 = m.lookup(host1)!;
      expect(h1.patch, 14);
      expect(h1.action, 'none');
      expect(h1.url, isNull);
    });

    test('buildNumber có số 0 đầu / khoảng trắng → vẫn khớp key', () {
      final ReleaseManifest m = ReleaseManifest.parse(
        jsonEncode(manifestMap()),
        baseUrl: 'http://test.local',
      );
      expect(
        m.lookup(const HostIdentity(
          bundleId: 'com.example.host1',
          platform: 'android',
          buildNumber: ' 013 ',
        ))!
            .patch,
        14,
      );
    });

    test('không có bundle / platform / build → null', () {
      final ReleaseManifest m = ReleaseManifest.parse(
        jsonEncode(manifestMap()),
        baseUrl: 'http://test.local',
      );
      expect(
        m.lookup(const HostIdentity(
            bundleId: 'com.nope', platform: 'android', buildNumber: '1')),
        isNull,
      );
      expect(
        m.lookup(const HostIdentity(
            bundleId: 'com.example.host1', platform: 'ios', buildNumber: '13')),
        isNull,
      );
      expect(
        m.lookup(const HostIdentity(
            bundleId: 'com.example.host1',
            platform: 'android',
            buildNumber: '99')),
        isNull,
      );
    });

    test('JSON hỏng / thiếu hosts → FormatException', () {
      expect(() => ReleaseManifest.parse('{nope', baseUrl: 'x'),
          throwsFormatException);
      expect(
        () => ReleaseManifest.parse('{"patches": {}}', baseUrl: 'x'),
        throwsFormatException,
      );
    });
  });

  group('ModuleCheck.evaluate', () {
    final ReleaseManifest m = ReleaseManifest.parse(
      jsonEncode(manifestMap(minForceUpdate14: 10)),
      baseUrl: 'http://test.local',
    );

    test('có dòng + target > current → updateAvailable, chỉ tải đúng patch',
        () {
      final ModuleCheck c =
          ModuleCheck.evaluate(m, host: hostA, currentModuleVersion: 3);
      expect(c.updateAvailable, isTrue);
      // latest = 14 nhưng bản build này chỉ chạy được v7.
      expect(c.module!.number, 7);
      expect(c.latest, 14);
      expect(c.entry!.action, 'force');
    });

    test('không có dòng → không update, không entry (fail-open)', () {
      final ModuleCheck c = ModuleCheck.evaluate(
        m,
        host: const HostIdentity(
            bundleId: 'com.nope', platform: 'android', buildNumber: '1'),
        currentModuleVersion: 0,
      );
      expect(c.updateAvailable, isFalse);
      expect(c.entry, isNull);
      expect(c.module, isNull);
    });

    test('patch 0 → không có gì để tải', () {
      final ModuleCheck c = ModuleCheck.evaluate(
        m,
        host: const HostIdentity(
            bundleId: 'com.example.host1',
            platform: 'android',
            buildNumber: '5'),
        currentModuleVersion: 0,
      );
      expect(c.entry!.patch, 0);
      expect(c.module, isNull);
      expect(c.updateAvailable, isFalse);
    });

    test('target <= current → không tải (KHÔNG downgrade)', () {
      expect(
        ModuleCheck.evaluate(m, host: hostA, currentModuleVersion: 7)
            .updateAvailable,
        isFalse,
      );
      expect(
        ModuleCheck.evaluate(m, host: hostA, currentModuleVersion: 9)
            .updateAvailable,
        isFalse,
      );
    });

    test('min_force_update lấy từ patch đích, so với version đang chạy', () {
      // current 9 < 10 → ép restart.
      expect(
        ModuleCheck.evaluate(m, host: host1, currentModuleVersion: 9)
            .forceRestart,
        isTrue,
      );
      // current 10 >= 10 → tải nhưng không ép.
      final ModuleCheck ok =
          ModuleCheck.evaluate(m, host: host1, currentModuleVersion: 10);
      expect(ok.updateAvailable, isTrue);
      expect(ok.forceRestart, isFalse);
      // Không có bản mới → không bao giờ ép.
      expect(
        ModuleCheck.evaluate(m, host: host1, currentModuleVersion: 14)
            .forceRestart,
        isFalse,
      );
      // Patch 7 có ngưỡng 0 → không ép.
      expect(
        ModuleCheck.evaluate(m, host: hostA, currentModuleVersion: 0)
            .forceRestart,
        isFalse,
      );
    });
  });

  group('manifest riêng từng app', () {
    test('có bundleId → GET app/manifest/<bundleId>.json; rs_domain có "/" '
        'cuối vẫn không sinh "//"', () async {
      final List<String> urls = <String>[];
      final DynModuleLoader loader = DynModuleLoader(
        baseUrl: 'http://test.local/',
        bundleId: host1.bundleId,
        client: MockClient((http.Request req) async {
          urls.add(req.url.toString());
          return http.Response(jsonEncode(manifestMap()), 200);
        }),
        cacheDirOverride: tempDir,
      );
      final ManifestFetch? got = await loader.fetchManifest();
      expect(urls.single,
          'http://test.local/app/manifest/${host1.bundleId}.json');
      expect(got!.manifest.patches[7]!.downloadUrl,
          'http://test.local/app/app_content_73ffe17f.bytecode');
    });

    test('không có bundleId → manifest gộp cũ app/manifest.json', () {
      expect(loaderWith(server()).manifestPath, kReleaseManifestPath);
      expect(
          DynModuleLoader(baseUrl: 'x', bundleId: ' ', cacheDirOverride: tempDir)
              .manifestPath,
          kReleaseManifestPath);
    });
  });

  group('fetchManifest: ETag + cache', () {
    test('200 → network, lưu body + ETag; lần sau gửi If-None-Match → 304 '
        'dùng cache', () async {
      final DynModuleLoader loader = loaderWith(server());

      final ManifestFetch? first = await loader.fetchManifest();
      expect(first!.source, ManifestSource.network);
      expect(requests.single.headers.containsKey('If-None-Match'), isFalse);
      expect(File('${tempDir.path}/$kManifestCacheFileName').existsSync(),
          isTrue);

      final ManifestFetch? second = await loader.fetchManifest();
      expect(second!.source, ManifestSource.notModified);
      expect(requests.last.headers['If-None-Match'], '"v1"');
      expect(second.manifest.latest, 14);
    });

    test('readCachedManifest: chưa có → null; sau 200 → đọc được không chạm '
        'mạng', () async {
      final DynModuleLoader loader = loaderWith(server());
      expect(await loader.readCachedManifest(), isNull);
      await loader.fetchManifest();
      requests.clear();
      final ReleaseManifest? cached = await loader.readCachedManifest();
      expect(cached!.lookup(host1)!.patch, 14);
      expect(requests, isEmpty);
    });

    test('lỗi mạng → dùng cache nếu có, không có cache → null', () async {
      expect(await loaderWith(server(throwOnManifest: true)).fetchManifest(),
          isNull);

      await loaderWith(server()).fetchManifest();
      final ManifestFetch? got =
          await loaderWith(server(throwOnManifest: true)).fetchManifest();
      expect(got!.source, ManifestSource.cache);
      expect(got.manifest.lookup(hostA)!.action, 'force');
    });

    test('5xx → dùng cache', () async {
      await loaderWith(server()).fetchManifest();
      final ManifestFetch? got =
          await loaderWith(server(manifestStatus: 503)).fetchManifest();
      expect(got!.source, ManifestSource.cache);
    });

    test('404 → dùng manifest đã lưu (giữ quyết định đã biết)', () async {
      expect(await loaderWith(server(manifestStatus: 404)).fetchManifest(),
          isNull);
      await loaderWith(server()).fetchManifest();
      final ManifestFetch? got =
          await loaderWith(server(manifestStatus: 404)).fetchManifest();
      expect(got!.source, ManifestSource.cache);
      expect(got.manifest.lookup(hostA)!.action, 'force');
    });

    test('200 nhưng body hỏng → dùng manifest đã lưu, KHÔNG ghi đè cache tốt',
        () async {
      await loaderWith(server()).fetchManifest();
      final ManifestFetch? got = await loaderWith(
        server(manifestBody: '{broken', etag: '"v2"'),
      ).fetchManifest();
      expect(got!.source, ManifestSource.cache);
      expect(got.manifest.latest, 14);
      expect((await loaderWith(server()).readCachedManifest())!.latest, 14);
    });

    test('ETag mới → 200 thay cache', () async {
      await loaderWith(server()).fetchManifest();
      final Map<String, Object?> changed = manifestMap()..['latest'] = 15;
      final ManifestFetch? got = await loaderWith(
        server(manifestBody: jsonEncode(changed), etag: '"v2"'),
      ).fetchManifest();
      expect(got!.source, ManifestSource.network);
      expect((await loaderWith(server()).readCachedManifest())!.latest, 15);
    });
  });

  group('checkAndPrefetch', () {
    test('có dòng → tải đúng patch đích, verify, lưu disk, onCheck có action',
        () async {
      ModuleCheck? seen;
      final DynModuleLoader loader = loaderWith(server());
      final pref = await loader.checkAndPrefetch(
        host: hostA,
        currentModuleVersion: 0,
        onCheck: (ModuleCheck c) => seen = c,
      );
      expect(pref!.number, 7);
      expect(pref.hash, hashV7);
      expect(pref.forceRestart, isFalse);
      expect(seen!.entry!.action, 'force');
      expect(await loader.readCache(), bytesV7);
      // KHÔNG bao giờ tải v14 (latest) cho bản build chỉ chạy được v7.
      expect(requests.any((r) => r.url.path.contains('ab12cd34')), isFalse);
    });

    test('không có dòng → null, không tải gì, onCheck có entry null', () async {
      ModuleCheck? seen;
      final pref = await loaderWith(server()).checkAndPrefetch(
        host: const HostIdentity(
            bundleId: 'com.nope', platform: 'android', buildNumber: '1'),
        currentModuleVersion: 0,
        onCheck: (ModuleCheck c) => seen = c,
      );
      expect(pref, isNull);
      expect(seen!.entry, isNull);
      expect(requests.where((r) => r.url.path.endsWith('.bytecode')), isEmpty);
    });

    test('target <= current → null, không tải', () async {
      final pref = await loaderWith(server()).checkAndPrefetch(
        host: host1,
        currentModuleVersion: 14,
      );
      expect(pref, isNull);
      expect(requests.where((r) => r.url.path.endsWith('.bytecode')), isEmpty);
    });

    test('manifest truyền sẵn (cache lúc boot) → KHÔNG GET manifest', () async {
      final DynModuleLoader loader = loaderWith(server());
      final ReleaseManifest m = ReleaseManifest.parse(
        jsonEncode(manifestMap()),
        baseUrl: 'http://test.local',
      );
      final pref = await loader.checkAndPrefetch(
        host: host1,
        currentModuleVersion: 7,
        manifest: m,
      );
      expect(pref!.number, 14);
      expect(requests.where((r) => r.url.path.endsWith('manifest.json')),
          isEmpty);
    });

    test('accept từ chối (hash hỏng) → null, không tải', () async {
      final pref = await loaderWith(server()).checkAndPrefetch(
        host: host1,
        currentModuleVersion: 0,
        accept: (ModuleInfo m) => false,
      );
      expect(pref, isNull);
      expect(requests.where((r) => r.url.path.endsWith('.bytecode')), isEmpty);
    });

    test('hash lệch → ModuleVerifyException, KHÔNG lưu disk', () async {
      final DynModuleLoader loader = loaderWith(
        server(manifestBody: jsonEncode(manifestMap(hash14: 'deadbeef'))),
      );
      await expectLater(
        loader.checkAndPrefetch(host: host1, currentModuleVersion: 0),
        throwsA(isA<ModuleVerifyException>()),
      );
      expect(await loader.readCache(), isNull);
    });

    test('có gz_file → chỉ tải bản gzip, giải nén, verify hash bytecode',
        () async {
      final DynModuleLoader loader = loaderWith(
        server(manifestBody: jsonEncode(manifestMap(gz14: true))),
      );
      final pref =
          await loader.checkAndPrefetch(host: host1, currentModuleVersion: 0);
      expect(pref!.number, 14);
      expect(await loader.readCache(), bytesV14);
      final List<String> got = requests
          .map((r) => r.url.path)
          .where((p) => p.contains('ab12cd34'))
          .toList();
      expect(got, <String>['/app/app_content_ab12cd34.bytecode.gz']);
    });

    test('gz lỗi (404) → tải bản thô', () async {
      final DynModuleLoader loader = loaderWith(server(
        manifestBody: jsonEncode(manifestMap(gz14: true)),
        serveGz: false,
      ));
      final pref =
          await loader.checkAndPrefetch(host: host1, currentModuleVersion: 0);
      expect(pref!.number, 14);
      expect(await loader.readCache(), bytesV14);
      expect(requests.last.url.path, '/app/app_content_ab12cd34.bytecode');
    });

    test('decodeGzip: không có magic gzip → trả nguyên', () {
      expect(DynModuleLoader.decodeGzip(bytesV14), bytesV14);
      expect(
          DynModuleLoader.decodeGzip(Uint8List.fromList(gzip.encode(bytesV14))),
          bytesV14);
    });

    test('dưới min_force_update của patch đích → forceRestart=true', () async {
      final pref = await loaderWith(
        server(manifestBody: jsonEncode(manifestMap(minForceUpdate14: 10))),
      ).checkAndPrefetch(host: host1, currentModuleVersion: 7);
      expect(pref!.number, 14);
      expect(pref.forceRestart, isTrue);
    });

    test('lỗi mạng + có cache manifest → vẫn quyết định theo cache', () async {
      await loaderWith(server()).fetchManifest();
      ModuleCheck? seen;
      final pref = await loaderWith(server(throwOnManifest: true))
          .checkAndPrefetch(
        host: hostA,
        currentModuleVersion: 7,
        onCheck: (ModuleCheck c) => seen = c,
      );
      expect(pref, isNull);
      expect(seen!.entry!.action, 'force');
    });

    test('404 và chưa có manifest đã lưu → ModuleCheck.none, không tải',
        () async {
      ModuleCheck? seen;
      final pref = await loaderWith(server(manifestStatus: 404))
          .checkAndPrefetch(
        host: host1,
        currentModuleVersion: 0,
        onCheck: (ModuleCheck c) => seen = c,
      );
      expect(pref, isNull);
      expect(seen!.entry, isNull);
    });
  });
}
