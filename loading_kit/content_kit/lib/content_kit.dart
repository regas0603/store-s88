import 'package:flutter/widgets.dart';

/// Version hop dong host <-> module (docs/dynmod_build_once_plan.md P3).
///
/// Host build 1 lan → hop dong nay DONG BANG cung host. Module khai
/// [ContentEntry.contractVersion] lon hon version host dang chay → host tu
/// choi (fail-open). Tinh nang moi KHONG them member vao day ma di qua
/// [HostServices.invoke] / [ContentEntry.invoke].
const int kContentContractVersion = 2;

/// Nhung gi CHI host moi biet / moi lam duoc, dua cho module.
///
/// Module chay chung isolate voi host nen da tu dung duoc lifecycle, Navigator,
/// moi package cua host (qua dynamic interface) — khong can di qua day.
abstract interface class HostServices {
  /// [kContentContractVersion] cua host dang chay.
  int get contractVersion;

  /// Version app host, vd '1.0.4+4'.
  String get hostVersion;

  /// So version module dang chay (theo bytecode.manifest), 0 = khong ro.
  int get moduleVersion;

  /// Cau hinh per-app host dang dung (Git JSON), vd `rs_domain`.
  Map<String, Object?> get appConfig;

  /// Ten package host co san (plugin native + package dong bang) — module
  /// dung de bat/tat tinh nang theo doi host.
  Set<String> get capabilities;

  /// Kenh mo rong module → host. Method host khong biet → [UnsupportedError].
  Future<Object?> invoke(String method, Map<String, Object?> args);

  /// Module bao da khoi dong on (vd sau first frame vai giay). Host khong
  /// nhan duoc sau nhieu lan mo lien tiep → coi ban module nay hong, bo qua.
  void markHealthy();

  /// Module bao loi nghiem trong (log + bao cao ve host).
  void reportError(Object error, StackTrace stack);
}

/// Hop dong 1 man noi dung dang ky vao shell cua app.
/// Ca app lan cac goi noi dung deu depend package nay, khong ai depend ai.
abstract interface class ContentEntry {
  /// Version semver dang '1.0.0'. Chon max khi co nhieu ban.
  String get version;

  /// [kContentContractVersion] luc module duoc compile.
  int get contractVersion;

  /// Goi 1 lan truoc khi hien man.
  Future<void> init(HostServices host);

  /// Dung 1 lan sau init(). Tra ve root widget cua man.
  Widget buildView(BuildContext context);

  /// Kenh mo rong host → module. Method module khong biet → tra null.
  Future<Object?> invoke(String method, Map<String, Object?> args);
}

/// Registry nam giu cac man noi dung.
abstract interface class ContentRegistry {
  void register(ContentEntry e);
}

/// Kieu entrypoint cua module: `@pragma('dyn-module:entry-point')` tra ve ham
/// nay — loader goi voi registry cuc bo. Kieu tra ve `void` nen moi closure
/// `(ContentRegistry r) => r.register(...)` deu khop.
typedef ContentEntrypoint = void Function(ContentRegistry registry);

/// Registry mac dinh, tao san luc khoi dong.
class LocalContentRegistry implements ContentRegistry {
  final List<ContentEntry> entries = [];

  @override
  void register(ContentEntry e) => entries.add(e);

  /// Entry version cao nhat, null neu chua co man nao.
  ContentEntry? get latest {
    if (entries.isEmpty) return null;
    ContentEntry best = entries.first;
    for (final e in entries.skip(1)) {
      if (compareVersions(e.version, best.version) > 0) best = e;
    }
    return best;
  }
}

/// So sanh semver don gian 'x.y.z'. Tra ve >0 neu a moi hon b.
int compareVersions(String a, String b) {
  List<int> parse(String v) => v
      .split('+')
      .first
      .split('.')
      .map((s) => int.tryParse(s) ?? 0)
      .toList();
  final pa = parse(a);
  final pb = parse(b);
  for (var i = 0; i < 3; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}
