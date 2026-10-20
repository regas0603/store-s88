# Ke hoach thay the Shorebird bang Dart Dynamic Modules (dynmod)

> Muc tieu: bo chuoi Shorebird (fork shorebird-engine, fork updater,
> CLI shorebird, protocol patches/check, patch libapp.so diff),
> thay bang chuoi 100% public: engine upstream + .bytecode + CLI dynpush
> mong + server module. App B (hien la ../app_package) thanh
> dynamic module hot toan bo, App A (host sach) giu flow boot/gate.
>
> Co so: dyn_modules_android_result.md, dyn_modules_ios_result.md,
> dyn_modules_speed_result.md, dyn_modules_flutter_engine_integration.md,
> tools/cmd/dynmod.sh.
>
> Quy uoc: Host = app/ (ban release sach). B = ../app_package (game).
> Module file = app_b_vN.bytecode.
>
> PHAM VI NEN TANG: nghien cuu tren 2 nen tang **ANDROID + IOS**.
> KHONG co macOS/desktop.
> macOS chi xuat hien o vai tro:
>   (a) may build — bat buoc, vi iOS chi build/ky duoc tren macOS;
>   (b) engine `host` (dartaotruntime + gen_kernel_aot + dart2bytecode)
>       de bien dich module + lam `--local-engine-host`.
> App tren macOS chi xuat hien trong thu nghiem chung minh kha thi
> (dyn_modules_flutter_e2e_result.md) — KHONG phai target san pham.

## 0. Vi sao thay duoc va cai gi KHONG thay duoc

### 0.1. Nguyen tac additive-only (bat buoc hieu)

dyn_modules KHONG de ham cu nhu Shorebird:

> All extensions are additive. Dynamic modules cannot replace an existing
> declaration in the application. (dyn_modules_research.md S2)

| Thiet ke Shorebird hien tai | Thiet ke dynmod moi |
|---|---|
| lib/main.dart (release) vs lib/main_patch.dart (patch mang game). Engine nap snapshot patch de, goi main cua patch | Mot entry duy nhat lib/main.dart. Host A khoi dong, sau boot tai app_b.bytecode, goi entry-point lay widget B roi swap o root |
| Patch diff libapp.so, sinh rieng tung ABI | 1 file .bytecode dung chung moi platform/arch (platform_strong.dill giong het byte) |
| restart_app process-level de apply patch | KHONG restart. setState swap widget la B hien ngay |
| Fix bug de code A | Khong lam duoc. B la tinh nang cong them versioned (v1/v2), host chon ban moi nhat |

BootShell da giai dung bai nay: ownRootMaterialApp=false cho man live tu
dung MaterialApp.router (app/lib/shell/boot_shell.dart). Module B tra ve
Widget root cua app_package la cam thang vao, tranh bug nen den
flutter/flutter#142585.

### 0.2. Cai gi hot duoc / khong hot duoc

Da chung minh: module mang theo duoc package thuan Dart chua tung co trong
host, ke ca dep bac cau (power_pkg.bytecode 1830B, libapp.so host = 0 lan
FastPow - dyn_modules_android_result.md).

| B dung gi | Ket luan |
|---|---|
| Logic Dart, API, JSON, AES, routing, riverpod | OK, bien dich thang vao .bytecode |
| Widget Material/Cupertino/Navigator | OK ve ly thuyet (chua thu). Khai package:flutter la callable/extendable. Slowdown du kien nhom 3-6x nhu workload map/str |
| Plugin co native (block native-prebundle trong app/pubspec.yaml) | KHONG bay bang module. FFI tu module chua ho tro. Giu block native-prebundle o CA 2 mode |
| Doi/them plugin native cho B | Phai build lai ban host moi, giong quy tac app_package_mode.sh |
| Assets/anh cua B | bytecode khong mang asset. Tai tu server luc chay (khuyen nghi), hoac bundle san ten vo nghia |

### 0.3. Ban do thay the 1-1

| Shorebird hien tai | Dynmod thay bang | File lien quan |
|---|---|---|
| shorebird-engine/ (fork, Dart private) + tools/build_engine.sh | Engine upstream flutter/flutter@1be6586f + dart_dynamic_modules=true, build bang tools/cmd/dynmod.sh engine | fork-engine-plan.md, tools/build_engine.sh -> bo |
| updater/ (fork Rust) + symbol shorebird_set_base_url_override | Khong can. Khong con Rust updater, khong FFI override | updater/, loading_kit/lib/shorebird/ -> xoa o G6 |
| CLI shorebird + tools/sb.sh + tools/cmd/app_package_mode.sh | CLI mong tools/cmd/dynpush.sh: release / module / promote | sb.sh, app_package_mode.sh -> dong bang, khong xoa voi |
| Server POST patches/check, uploads/patch, rewrite_download_urls.mjs | POST modules/check, GET artifacts/module, rewrite_module_urls.mjs | server/src/routes/*.js, server/data/db.json |
| patch_only/lib/main_patch.dart (stash entry patch) | app/modules/home_content.dart (wrapper entry noi dung ~20 dong) | patch_only/ -> giu tham chieu toi nghiem thu |
| BootShell + AppLaunchCoordinator + UpdateBloc gate Shorebird | BootShell giu nguyen + DynModuleLoader moi (fetch, sha256, loadModuleFromBytes, swap). Khong restart | app/lib/shell/boot_shell.dart, loading_kit/ |
| shorebird.yaml trong assets | Xoa. Khong con Engine Rust doc yaml | app/pubspec.yaml, app/shorebird.yaml |

## 1. Kien truc muc tieu

Host A (ban chinh): main.dart (1 entry) -> BootShell (giu nguyen) ->
BootFlowCoordinator.executeFlow (giu nguyen: flag, date, Git JSON
apps/<id>.json, GET api_domain/ca/res status==0, cooldown 3-5 ngay) ->
DynModuleLoader (MOI, thay UpdateBloc): POST modules/check -> GET .bytecode
-> sha256 + Ed25519 -> loadModuleFromBytes -> Registry.entries.last ->
swap root (ownRootMaterialApp=false nhu main_patch). Native: toan bo plugin
cua B nuong san tu release. Dart: KHONG import app_package.

Server (server/src mo rong): POST /api/v1/modules/check +
GET /artifacts/module/:id/app_b_vN.bytecode + bang moduleArtifacts.

Build (dynmod.sh + dynpush.sh): engine ddm -> host AOT + interface ->
anchor.dill -> dart2bytecode home_content.dart -> app_b_vN.bytecode.
### 1.1. Hop dong A-B: packages/content_kit

Dart:

    import 'package:flutter/widgets.dart';
    abstract interface class ContentEntry {
      String get version;
      Future<List<Object?>> init();
      Widget buildView(BuildContext context);
    }
    abstract interface class ContentRegistry {
      void register(ContentEntry e);
    }

### 1.2. Wrapper module: app/modules/home_content.dart

Dart:

    import 'package:content_kit/content_kit.dart';
    import 'package:app_package/sun_sports_root.dart';
    class InfoEntry implements ContentEntry {
      @override String get version => '1.0.0';
      @override Widget buildView(BuildContext c) => const SunSportsApp();
    }
### 1.3. dynamic_interface.yaml cho full UI

    callable:
      - {library: 'dart:core'}
      - {library: 'dart:async'}
      - {library: 'dart:convert'}
      - {library: 'dart:typed_data'}
      - {library: 'package:flutter/widgets.dart'}
      - {library: 'package:flutter/material.dart'}
      - {library: 'package:flutter/cupertino.dart'}
      - {library: 'package:content_kit/content_kit.dart', class: 'ContentRegistry', member: 'register'}
    extendable:
      - {library: 'package:content_kit/content_kit.dart', class: 'ContentEntry'}
    can-be-overridden:
      - {library: 'package:content_kit/content_kit.dart', class: 'ContentEntry'}
    can-be-used-as-type:
      - {library: 'package:content_kit/content_kit.dart', class: 'ContentRegistry'}
      - {library: 'package:content_kit/content_kit.dart', class: 'ContentEntry'}
      - {library: 'package:flutter/widgets.dart', class: 'Widget'}
      - {library: 'package:flutter/widgets.dart', class: 'BuildContext'}

Moi plugin Dart ma B goi mat Dart them 1 dong callable tuong ung. Thieu se
loi COMPILE-TIME o dart2bytecode --validate (khong phai runtime) - day la
luoi an toan ma Shorebird khong co.

### 1.4. Runtime DynModuleLoader (thay UpdateBloc.checkForUpdate)

    check = POST base/api/v1/modules/check {app_id, release_version, module_name, module_version}
    if (!check.updateAvailable) return
    bytes = GET check.downloadUrl
    assert sha256(bytes) == check.hash else 'hash mismatch'
    assert ed25519Verify(bytes, check.hashSignature, pubkey) else 'bad signature'
    ep = await loadModuleFromBytes(bytes)
## 2. Ke hoach thi cong theo giai doan

### G0 - Chot pham vi B (0.5 ngay) - KHONG code

1. Mo ../app_package/pubspec.yaml, liet ke dependencies thanh 2 cot:
   pure-Dart (vao duoc module) vs co native (phai nuong san).
2. Doi chieu voi block native-prebundle trong app/pubspec.yaml - moi plugin
   cot native cua B bat buoc da co trong host, khop version constraint.
3. Liet ke assets cua B: quyet dinh tai runtime vs bundle san ten vo nghia.
4. Output: bang 3 cot package | loai | xu ly, lam dau vao G1/G3.

Nghiem thu: bang G0 duoc ky off, khong con plugin mo coi.

### G1 - Tach hop dong slot (1-2 ngay)

1. Tao packages/content_kit/ (pubspec chi depend flutter), 1 file
   lib/content_kit.dart nhu S1.1.
2. Tao app/modules/home_content.dart wrapper nhu S1.2. Can package_config
   thay duoc ../app_package (them path:) - host KHONG import nen B khong
   lot vao libapp.so (da chung minh o android_result).
3. Tao dist/dynamic_interface.yaml nhu S1.3. Plugin Dart nao thieu se loi ra
   o G4 buoc --validate - bo sung dan.
4. main.dart + boot_shell.dart: chua dung o G nay (giu Shorebird chay song
   song toi G6).

Nghiem thu: flutter analyze pass; grep -r app_package app/lib = rong.

### G2 - Engine ddm (0.5-1 ngay, may chay nen)

    bash tools/cmd/dynmod.sh check
    bash tools/cmd/dynmod.sh engine host android ios
    bash tools/cmd/dynmod.sh status
    bash tools/cmd/dynmod.sh backup ~/engine-ddm-backup

Build tren checkout upstream flutter-framework@1be6586f, KHONG dung
shorebird-engine/ (Dart fork private). M4 Max: host ~15p, android ~6p,
ios ~5p. Nghiem thu: strings libflutter.so thay bytecode magic o ca 3 out.

`host` khong phai target app — no la BO CONG CU build: chua
dartaotruntime + gen_kernel_aot + dart2bytecode (compile module) va lam
`--local-engine-host` cho ca 2 lenh build app (android + ios).

### G3 - Build host A + anchor (1 ngay)

    FF=../dart-sdk-build/flutter-framework
    $FF/bin/flutter build apk --release --local-engine-src-path $FF/engine/src \
      --local-engine=android_release_arm64 --local-engine-host=host_release_arm64 \
      --extra-front-end-options=--dynamic-interface=dist/dynamic_interface.yaml

frontend_server ddm da nhan co nay - KHONG can va flutter_tools (Cach A).

Anchor dill - mo neo cho dart2bytecode:

    dartaotruntime gen_kernel_aot.dart.snapshot \
### G4 - Compile B thanh module + E2E dau tien (1-2 ngay)

    bash tools/cmd/dynmod.sh module app/modules/home_content.dart \
      --entry package:app/main.dart -o app_b_v1.bytecode
    strings app_b_v1.bytecode | grep InfoEntry # phai > 0

1. Android emulator: manifest them INTERNET + cleartext (lab) -> fetch
   http://10.0.2.2:PORT/ -> B hien, khong rebuild.
2. Doi chung am: cung module tren engine stock -> phai bao
   Loading of dynamic modules is not supported.
3. iOS device: copy .bytecode qua devicectl vao Documents/, doc file cuc bo
   truoc (duong mang iOS de G6, bat buoc HTTPS + ATS nguyen ven).

Nghiem thu: B hien tren Android emu 10/10 + 1 lan iOS device. Ghi load_us,
fetch_us, size .bytecode, size APK/IPA ddm-vs-stock.

### G5 - CLI dynpush thay sb.sh (2-3 ngay)

    bash tools/cmd/dynpush.sh release  --app <bundleId> --version 1.0.4+7
    bash tools/cmd/dynpush.sh module   --app <bundleId> --release 1.0.4+7 \
      --entry app/modules/home_content.dart --version 1.0.0
    bash tools/cmd/dynpush.sh promote  --app <bundleId> --module 2 --channel stable
    bash tools/cmd/dynpush.sh status   --app <bundleId>

module lam 4 viec: (a) build anchor neu main.dart doi, (b) dart2bytecode
--import-dill anchor --validate interface, (c) sha256sum + ky Ed25519,
(d) POST /uploads/module/:id. Khong con gen_snapshot diff, linker data.

Nghiem thu: 1 lenh module tu source B ra toi server co download_url tai duoc.

### G6 - Server module + thao Shorebird khoi app (2-3 ngay)

Server (server/src/, tai dung store.js/helpers.js/multipart.js):

    POST /api/v1/modules/check
      req:  {app_id, release_version, platform, arch, module_name, module_version}
      resp: {update_available, module:{number, download_url, hash, hash_signature, min_host_anchor}}
    GET  /artifacts/module/:artifactId/:filename -> application/octet-stream
    POST /uploads/module/:artifactId -> nhan .bytecode (mo rong uploads.js)

db.json: bang moi moduleArtifacts {id, filename, hash, hashSignature,
anchorHash, storedPath}. Viet rewrite_module_urls.mjs tu mau
rewrite_download_urls.mjs. Moi app 1 api_base_url rieng trong
configs/apps/<bundleId>.json - giu co che per-app chong chain-ban.

App: (1) them packages/dyn_loader/ (loadModuleFromBytes, sha256, verify
Ed25519, LocalContentRegistry, cmpVersion) thay vi tri UpdateBloc.checkForUpdate
(sau cooldown, fail-open ve demo khi loi). (2) Xoa shorebird.yaml + assets
entry, updater/ FFI, loading_kit/lib/shorebird/. (3) Bo Restart.restartApp
khoi flow module. Dong bang app_package_mode.sh + patch_only/.

Nghiem thu: may chua cai B -> boot A -> check -> B hien sau 1 setState,
khong restart; khong con patches/check; hash lech/chu ky sai bi tu choi.

### G7 - Gate + do dac (2-3 ngay)

1. Giu nguyen: Git JSON per-app -> api_domain/ca/res AES -> status==0 ->
   cooldown 3-5 ngay -> moi cho modules/check thay B.
2. iOS end-to-end HTTPS that (chung chi hop le, khong NSAllowsArbitraryLoads).
3. Do nhu speed_result: load_us, first-frame B, scroll fps, APK/IPA
   ddm-vs-stock, RSS truoc/sau nap. Android do them tren may that.
4. Simpleperf neu workload chuyen tiep nhieu ma cham.

Nghiem thu: bang so G7 dien du; quyet dinh B nao duoc hot vs can build lai host.

## 3. Rui ro va duong lui

| Rui ro | Muc | Giam thieu |
|---|---|---|
| dart2bytecode --validate bao thieu interface | Cao, chac gap | Them dong callable, build lai module - khong dung host/engine. Loi compile-time |
| B phu thuoc widget/plugin chua khai, chay moi crash | Cao | Test ma tran man B tren emu truoc promote; kenh staging truoc stable |
| Host to them + lo ten plugin B | Trung | --obfuscate, asset ten vo nghia, lazy-load mat Dart |
| Interpreter cham voi game loop (arith 13x, alloc 63x) | Cao voi game nang | B nang -> build lai host, dynmod chi hot config/UI/event |
| dyn_modules experimental, API sap doi | Trung | Pin DYNMOD_REV=1be6586f; wrapper dyn_loader cach ly 1 cho |
| Bytecode khong ABI on dinh | Trung | anchorHash trong modules/check: chi tra module khop anchor |
| Module chung heap host, khong sandbox | Cao | TLS + sha256 + Ed25519 bat buoc |
| Mat cong neu quay lai Shorebird | Thap | Dong bang (khong xoa): shorebird-engine/, updater/, sb.sh, patch_only/, routes cu |

## 4. Checklist nghiem thu tong

- [x] G0: bảng plugin B chốt, native-prebundle khớp. (dynmod_g0_audit.md)
- [x] G1: content_kit + wrapper + interface xong, host sạch.
- [x] G2: 3 engine ddm co interpreter + backup. *(dựa trên đã build 1be6586f — verify lại bằng `bash tools/cmd/dynmod.sh status`)* `host` là bộ công cụ build, không phải target app.
- [x] G3: anchor dill `dist/home_v1.anchor.dill` (67MB) — host A release chay man sach cần build lại APK bằng `dynpush release --build`.
- [ ] G4: .bytecode DA COMPILE THAT (lan 2, 03/10 05:5x): dist/app_b_v1.bytecode 22,828,637 B, sha256 4d0f761f…e763c, strings | grep InfoEntry > 0, magic 3CBD. Bien gioi hep: host khong con ung List<Override> (dynmod_gate_impl.render entry.buildView truc tiep; module tu boc ProviderScope ben trong — riverpod roi khoi anchor closure). dist/dynamic_interface.yaml 6524 dong (gitignored, sinh lai bang dyniface.sh gen --regen). HOST CAN BUILD LAI APK (Dart doi). Con E2E: Android emu + iOS.
- [x] G5: dynpush.sh (release/module/promote/rollback/status/keys) — module 1 lenh ra download_url tai duoc (E2E với bytecode giả). `release --build` build APK ddm tự động.
- [x] G6 (code): server modules/check + artifacts + rewrite_module_urls; packages/dyn_loader (Ed25519 thuần Dart, test pass, cross-check openssl); gate móc vào AppLaunchCoordinator (DYNMOD_ENABLE=true), fail-open demo, không restart. Còn lại: E2E trên máy thật.
- [ ] G7: bang toc do/size/RSS; iOS HTTPS E2E; gate thay A.
- [ ] Don: go Shorebird khoi pubspec/assets/CI, cap nhat BUILD/RUN/DEPLOYMENT log.

Uoc luong: ~9-12 ngay cong.

## 5. Con tro file trong repo

- Thuc nghiem: dyn_modules_android/ios/speed/e2e/poc/engine_integration/tools_patch/app_template.
- Thiet ke: ke_hoach_app_bien_hinh.md, selfhost-master-plan.md, fork-engine-plan.md,
  app/lib/main.dart, app/lib/shell/boot_shell.dart, patch_only/,
  tools/cmd/app_package_mode.sh, tools/sb.sh, tools/cmd/dynmod.sh,
  server/src/routes/*.js, configs/apps/<bundleId>.json.


