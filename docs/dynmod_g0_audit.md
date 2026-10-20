# G0 - Kiem ke App B (app_package) cho dynmod

> Ngay: 2026-10-02. Nguon quet: ../app_package.
> Doc ke hoach: dynmod_replace_shorebird_plan.md.

## 1. Entry point cua B

| Item | Gia tri |
|---|---|
| Root widget | `class App extends ConsumerStatefulWidget` (lib/app.dart:69) |
| Wrapper san | `SunSportsApp` (lib/sun_sports_root.dart) - Stateless tra ve const App() |
| Init async | `SunSports.init()` (lib/sun_sports_init.dart) tra ve List<Override> riverpod |
| Router | GoRouter `_goRouter` + GlobalKey NavigatorState trong _AppState |
| Kieu MaterialApp | can xac nhan: AppRouter.createInstance (xem lib/router) - du kien MaterialApp.router |

## 2. Bang plugin G0: pure-Dart vs native

### 2.1. NATIVE - phai nuong san trong host A (giu block native-prebundle)

| Plugin | Ly do native | Da co trong app/pubspec.yaml? |
|---|---|---|
| audioplayers 6.5.1 | audio player (Kotlin/Swift) | CO |
| webview_flutter 4.11.2 + webview_flutter_wkwebview | WebView platform view | CO |
| flutter_inappwebview 6.1.5 (dev_dep nhung game_engine dung that) | InAppWebView + IHRunner | THIEU o deps - can kiem: game_engine dung flutter_inappwebview nhung app_package chi khai o dev_dependencies; host can co ban release |
| video_player 2.9.2 | video platform view | CO |
| path_provider 2.1.0 | documents dir | CO |
| shared_preferences 2.2.0 (B) / 2.5.3 (host) | prefs native | CO (lech version - can khop) |
| device_info_plus 11.5.0 | device info | CO |
| connectivity_plus 6.1.0 | network status | CO |
| package_info_plus 9.0.1 | version | CO |
| url_launcher 6.2.5 | mo URL ngoai | CO |
| wakelock_plus 1.4.0 | giu man hinh sang | CO |
| cached_network_image 3.4.1 (+sqflite) | cache anh | CO |
| fluttertoast 8.2.8 | toast native | CO |
| flutter_in_app_pip 1.7.4 | picture-in-picture | CO |
| rive 0.14.9 (RiveNative.init trong SunSports.init) | render native | CO |
| clarity_flutter 1.9.0 | analytics session replay | CO |
| sentry_flutter 9.24.0 | crash reporting | CO |
| google_fonts 6.2.1 | tai font runtime (can mang) | THIEU trong host - can them hoac chuyen sang font bundle |
| pointer_interceptor 0.10.1 | web pointer | CO |
| game_engine (path, pluginClass CaxiloSurfaceCompositorPlugin, android native) | compositor + IHRunner + PLRunner | CO |
| game_launcher (path, MethodChannel launchGame xuong Cocos native) | mo Cocos view | THIEU trong host - can them neu B dung duong Cocos |
| isolate_manager 6.1.2 (+generator) | background isolate | THIEU trong host - kiem co sinh code .g.dart khong |
| hive 2.2.3 + hive_flutter 1.1.0 | local DB (co adapter sinh code) | THIEU trong host - kiem adapter .g.dart |

### 2.2. PURE-DART - vao duoc .bytecode, khong can host biet

flutter_riverpod, go_router, dio, http, web_socket_channel, freezed_annotation
+ json_annotation (can file .freezed.dart/.g.dart di kem - da sinh san trong
repo), protobuf + fixnum, logger, intl, gap, grouped_list, styled_text, pinput,
lottie, shimmer_animation, blur, gradient_borders, qr_flutter, flutter_svg,
dartz, crypto, uuid, clock, archive, web, cupertino_icons + ~30 internal
packages/* (da so pure: app_env, dart_kit, betting_domain, auth_domain...).
Can quet them: package nao trong packages/* co android/ ios/ hoac pluginClass.

### 2.3. Dac biet can xu ly

1. `flutter_inappwebview`: B dung qua game_engine nhung chi o dev_dependencies
   -> release thieu native. Host phai them vao dependencies that.
2. `shared_preferences` lech 2.2.0 (B) vs 2.5.3 (host) -> khop 1 version.
3. `google_fonts` tai font runtime -> tren may khong mang lan dau B se fetch
   mang. Quyet dinh: giu (can INTERNET) hoac bundle font.
4. `SunSports.init()` goi `RiveNative.init()`, `WakelockPlus.enable()`,
   `SoundEffects.configureSession()`, `SentryService.init`,
   `LandingAuthSession.capture()` -> tat ca phai co san trong host (native).
   Wrapper module phai goi init roi moi buildApp.
5. `game_launcher` MethodChannel `launchGame` xuong Cocos native -> neu B co
   nut mo game Cocos thi host phai co Activity/View Cocos san. Ngoai pham vi
   hot Dart - ghi nhan la gioi han.
6. `hive` + `freezed`/`json_serializable` sinh code: module build phai thay
   duoc file .g.dart (nam san trong repo) - khong can chay build_runner lai
   neu khong doi schema.
7. Khong thay `dart:ffi` truc tiep trong lib/ + packages/ -> tot (module chua
   ho tro FFI). `dart:io` co dung (platform check) - OK vi van la Dart.

## 3. Quyet dinh G0

- [ ] Khop shared_preferences 1 version cho ca 2.
- [ ] Bo sung vao host deps: flutter_inappwebview, google_fonts (hoac loai),
  isolate_manager, hive + hive_flutter, game_launcher (neu dung Cocos).
- [ ] Xac nhan AppRouter tao MaterialApp.router (doc lib/router).
- [ ] Assets B: hien khong khai trong pubspec (comment out) + icon chuyen CDN
  webp -> huong tai runtime, khong bundle.

## 4. Tien do G1 (2026-10-02)

- [x] Tao packages/content_kit (pubspec + lib/content_kit.dart) -
  flutter analyze: No issues found.
- [x] Tao app/modules/home_content.dart (wrapper InfoEntry version 1.0.1,
  goi SunSports.init + SunSportsApp).
- [x] Tao dist/dynamic_interface.yaml (flutter + slot capabilities).
- [x] Host sach: grep app_package trong app/lib chi ra comment + main_app_package.
- [x] Bo sung host deps: google_fonts, isolate_manager, hive, hive_flutter
  (flutter pub get + analyze + test PASS). shared_preferences giu 2.5.3
  (tuong thich ^2.2.0 cua B).
- [x] game_launcher pure-Dart fail-open -> khong can them gi cho Cocos.
- [x] Plugin NATIVE duy nhat co android/ rieng: game_engine (da co) -> OK.
- [ ] G2: engine android + ios dang build nen (host_release_arm64 da co san).


