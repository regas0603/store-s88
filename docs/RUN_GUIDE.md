# Hướng dẫn RUN (dev) — chạy app trên Android / iOS

> **Phạm vi: app chỉ chạy trên Android và iOS — không có macOS/desktop.**
> Script này cũng chỉ nhận `ios`, `ios-sim`, `android`, `android-emu`, `devices`.
> macOS trong dự án chỉ là **máy build** (bắt buộc: iOS chỉ build/ký được trên macOS).
>
> Doc này chỉ lo **chạy thử lúc dev** bằng Flutter stable của máy.
> **KHÔNG** dùng cho build release hay build engine dynamic-modules —
> hai việc đó đi qua `tools/cmd/dynmod.sh` (engine) + `tools/cmd/dynpush.sh` (đăng
> release / module `.bytecode`).
>
> Mọi lệnh + kết quả trong doc này đã chạy thật trên máy này
> (Flutter 3.44.2 / Dart 3.12.2, Xcode 27.0, macOS 27.0).

---

## 0. Tool

| Tool | Dùng để | Cách dùng |
|---|---|---|
| `tools/cmd/run.sh` | chạy dev từ terminal | `bash tools/cmd/run.sh ios-sim`, `APP_ENV=pre bash tools/cmd/run.sh android`, `bash tools/cmd/run.sh devices` |
| `.vscode/launch.json` | bấm F5 trong VS Code | 5 config: debug prod/pre, profile prod, release prod/pre. Máy chọn ở device picker. |

Platform nhận: `ios`, `ios-sim`, `android`, `android-emu`, `devices`.

Tham số sau tên platform được truyền thẳng cho `flutter run`.

Env override của `tools/cmd/run.sh`:

| Env | Ý nghĩa |
|---|---|
| `APP_ENV` | `prod` \| `pre`, mặc định `prod`. Giá trị lạ → script báo lỗi và dừng. |
| `DEVICE` | ID device cụ thể — bỏ qua bước tự tra device |
| `FLUTTER` | đường dẫn flutter khác |

---

## 1. `APP_ENV` — prod / pre

Chỉ là **tag đóng vào bản build** bằng `--dart-define=APP_ENV=<prod|pre>`.

**Repo này KHÔNG có code nào đọc nó.** Phần đọc nằm ở code chỉ xuất hiện
trong app **sau khi update** — code đó tự gọi
`String.fromEnvironment('APP_ENV')`, không cần helper nào ở đây. Không truyền
define = không có giá trị nào được đóng vào, và `String.fromEnvironment` trả
chuỗi rỗng → phía đọc tự quy ước rỗng = `prod`.

Hệ quả: **không verify được từ repo này** rằng define đã vào đúng chưa, vì
không có gì in nó ra. Gõ sai (`APP_ENV=prd`) sẽ đi lọt tới tận lúc chạy. Vì
vậy `tools/cmd/run.sh` chặn sẵn giá trị lạ:

```bash
$ APP_ENV=staging bash tools/cmd/run.sh android
APP_ENV không hợp lệ: 'staging' (chỉ nhận: prod | pre)      # exit 1
```

Cách chạy:

```bash
bash tools/cmd/run.sh android                 # prod (mặc định)
APP_ENV=pre bash tools/cmd/run.sh android     # pre
APP_ENV=pre bash tools/cmd/run.sh ios --release
```

Trong VS Code: chọn config có hậu tố `· pre`.

### ⚠️ Quan trọng — phải đặt define lúc build app

`String.fromEnvironment` là **compile-time**: giá trị bị inline lúc biên dịch.
Code đọc `APP_ENV` nằm trong **module `.bytecode`**, không phải bản release gốc.
Nên define phải có ở lệnh build app:

```bash
bash tools/cmd/dynmod.sh app android -- --dart-define=APP_ENV=pre
```

`tools/cmd/dynpush.sh release --build` đã truyền sẵn các define `DYNMOD_*` cần
thiết; nếu tự build thì thêm `--dart-define=APP_ENV=<prod|pre>` như trên.

Quên define → module đọc ra chuỗi rỗng, tức là rơi về prod, dù bản release đã
build với `pre`.

---

## 1b. Bấm Run trong VS Code

Các config trong `.vscode/launch.json` **không ghim device**. Cách chạy:

1. Bật simulator trước — VS Code chỉ thấy máy nào đang chạy:
   `open -a Simulator`, hoặc bấm device picker → **Start iOS Simulator**.
2. Bấm **device picker** ở góc phải dưới thanh status (chỗ hiện tên máy, vd
   `iPhone 18 Pro`) → chọn máy.
3. Chọn config ở panel **Run and Debug** (`app · debug (prod)` /
   `· debug (pre)` / ...) → **F5**.

### ⚠️ Đừng ghim `"deviceId": "ios"` hay `"android"`

Không chạy được, và đây là lỗi ở bản `launch.json` đầu tiên của repo này.
Extension Dart-Code dò device bằng `findBestDevice()`, chỉ so theo **ID** và
**TÊN** device (khớp đúng → prefix → substring), **không hề so theo
platform**. Simulator có id là UUID và tên `iPhone 18 Pro`, nên `"ios"` không
khớp gì cả:

```
Device "ios" was not found
```

`flutter run -d ios` ở terminal cũng hỏng y hệt vì cùng nguyên nhân:

```
$ flutter run -d ios
No supported devices found with name or id matching 'ios'.
```

`tools/cmd/run.sh` giải quyết bằng cách tra ID thật qua `flutter devices
--machine` trước khi gọi `-d`. Trong VS Code thì không ghim device, dùng
picker.

---

## 2. Android

```bash
bash tools/cmd/run.sh android          # máy Android bất kỳ
bash tools/cmd/run.sh android-emu      # chỉ emulator
bash tools/cmd/run.sh android --release
```

Chưa bật emulator thì script chỉ luôn cách bật:

```
$ bash tools/cmd/run.sh android
Không thấy device nào cho 'android'.
  Liệt kê emulator: flutter emulators
  Bật emulator:     flutter emulators --launch <emulator-id>
```

`flutter build apk --debug` đã verify build xanh. `applicationId` hiện tại là
`com.example.app` (`app/android/app/build.gradle.kts`).

---

## 3. iOS

```bash
bash tools/cmd/run.sh ios-sim          # chỉ simulator — dùng cái này khi dev
bash tools/cmd/run.sh ios              # máy iOS bất kỳ (thật hoặc simulator)
DEVICE=<uuid> bash tools/cmd/run.sh ios
open -a Simulator                  # bật simulator nếu chưa có
```

Cắm iPhone thật mà simulator cũng đang bật thì `ios` có 2 lựa chọn, script
liệt kê ra để chọn thay vì đoán bừa:

```
$ bash tools/cmd/run.sh ios
Có nhiều device 'ios' — chọn 1 bằng DEVICE=<id>:
  00008140-00125CE11A7B001C  Admin's iPhone (máy thật)
  DA21CFCE-5429-4D09-9B3F-EFA3D9C00ED5  iPhone 18 Pro (simulator/emulator)
  (hoặc dùng: bash tools/cmd/run.sh ios-sim để lấy simulator)
```

Đã verify: chạy thật trên simulator iPhone 16 Pro (app lên màn hình, boot flow
chạy), và `flutter build ios --debug --no-codesign` build xanh cho máy thật.

Flutter 3.44 dùng **Swift Package Manager** cho plugin iOS → không có
`Podfile`, không cần `pod install`.

### Hai thứ phải biết trên Xcode 27

**a) `IPHONEOS_DEPLOYMENT_TARGET` đã nâng 13.0 → 15.0.**
Xcode 27 từ chối build deployment target < 15.0:

```
Target Integrity (Xcode): The iOS deployment target 'IPHONEOS_DEPLOYMENT_TARGET'
is set to 13.0, but the range of supported deployment target versions is
15.0 to 27.0.x.
```

Đã sửa 3 chỗ trong `app/ios/Runner.xcodeproj/project.pbxproj`. **Hệ quả: app
không còn cài được trên iOS 13/14.** Nếu cần giữ 13/14 thì phải hạ Xcode,
không có cách khác.

**b) `flutter build ios --simulator` (destination generic) FAIL — bug Flutter
3.44 + Xcode 27, không phải lỗi project.**

```
Target debug_unpack_ios failed: Exception: Binary .../Flutter.framework/Flutter
does not contain architectures "arm64 x86_64".
lipo -info: Architectures in the fat file: ... are: x86_64 arm64
```

Framework có đủ cả 2 arch. Nguyên nhân: `flutter_tools` gọi
`lipo <binary> -verify_arch arm64 x86_64` (xem
`packages/flutter_tools/lib/src/build_system/targets/darwin.dart:85`), nhưng
`lipo` của Xcode 27 chỉ nhận **một** arch mỗi lần:

```
$ lipo <binary> -verify_arch arm64 x86_64
lipo: -verify_arch requires exactly one input file     # exit 1
$ lipo <binary> -verify_arch arm64                     # exit 0
$ lipo <binary> -verify_arch x86_64                    # exit 0
```

Destination generic → `ARCHS = "arm64 x86_64"` → luôn fail.

**Cách tránh:** luôn chỉ định device cụ thể (1 arch). `flutter run -d <id>` và
mọi config iOS trong `launch.json` đều làm vậy nên **không dính bug**. Chỉ
`flutter build ios --simulator` gõ tay mới dính.

### Ký (signing) khi chạy máy thật

`project.pbxproj` đang `CODE_SIGN_STYLE = Automatic` nhưng **chưa set
`DEVELOPMENT_TEAM`**. Simulator chạy được luôn; máy thật phải mở
`app/ios/Runner.xcworkspace` trong Xcode → Runner → Signing & Capabilities →
chọn Team một lần.

---

## 4. Bundle id nào có config thật?

Boot flow fetch `<kConfigBaseUrl>/<bundleId>.json`, hiện là
`https://raw.githubusercontent.com/Vulcan-dev-25/configs/main/apps/`.
`bundleId` đọc runtime qua `package_info_plus` (Android `applicationId`,
iOS `CFBundleIdentifier`) — **không có cách ép từ ngoài**.

Repo configs hiện chỉ có `apps/com.gamevee.th1.json` và `apps/api_test.json`.
Bundle id mặc định của app là `com.example.app`
(`app/android/app/build.gradle.kts` + `PRODUCT_BUNDLE_IDENTIFIER` trong
`project.pbxproj`) → **chưa có file config** → chạy mặc định sẽ 404 ở Step 3
và hiện dialog "Lỗi Internet" (đã thấy đúng như vậy khi chạy simulator).

Muốn qua Step 3 khi dev, chọn 1 trong 2:
- thêm file `apps/com.example.app.json` vào repo configs, hoặc
- đổi `applicationId` / `PRODUCT_BUNDLE_IDENTIFIER` sang bundle id đã có
  config rồi build lại.

### ⚠️ Step 4 hiện đang fail với `com.gamevee.th1`

Step 3 OK (HTTP 200), nhưng Step 4 tạo URL hỏng:

```
[Boot] Step 3 result: success apiDomain=https://alpha-weather-check.workers.dev
[Boot] checkBoot iteration=1 START url=https://alpha-weather-check.workers.devcom.gamevee.th1
                                                                            ^^^ dính liền
```

`boot_flow_coordinator.dart` (thay đổi CHƯA COMMIT) nối thẳng
`'$apiDomain$appBundleId'` — tức là schema mới yêu cầu `api_domain` tự mang
theo dấu phân cách. `apps/api_test.json` đúng schema đó (`api_domain` kết thúc
bằng `?`), còn `apps/com.gamevee.th1.json` thì không
(`https://alpha-weather-check.workers.dev`, không có `/` hay `?` cuối). Thêm
nữa domain `alpha-weather-check.workers.dev` hiện không phân giải được
(curl trả `000`).

Đây là việc đang làm dở ở phía config/backend, **không liên quan tới run
config**. Sửa 1 trong 2:
- thêm dấu phân cách vào `api_domain` trong file config, hoặc
- nối có separator trong `executeCheckBoot` (step 4 hiện gọi 1 lần, không retry).

---

## 5. Những gì đã verify trên máy này

| Việc | Kết quả |
|---|---|
| `APP_ENV=pre bash tools/cmd/run.sh ios-sim` trên simulator | ✅ app chạy bình thường (define được truyền, không có gì đọc nên không log ra) |
| `bash tools/cmd/run.sh ios` khi có 2 máy iOS | ✅ liệt kê cả 2, exit 1 thay vì đoán |
| `bash tools/cmd/run.sh android` khi chưa bật emulator | ✅ chỉ cách bật, exit 1 |
| `flutter run -d ios` | ❌ "No supported devices found with name or id matching 'ios'" — lý do bỏ `deviceId` khỏi launch.json (mục 1b) |
| bundle id `com.example.app` khi chạy simulator | ⚠️ 404 ở Step 3 → dialog "Lỗi Internet" (mục 4) |
| `APP_ENV=staging bash tools/cmd/run.sh android` | ✅ bị chặn, exit 1 |
| `flutter build apk --debug` | ✅ `Built build/app/outputs/flutter-apk/app-debug.apk` |
| `flutter build ios --debug --no-codesign` | ✅ `Built build/ios/iphoneos/Runner.app` (sau khi nâng deployment target) |
| `flutter build ios --simulator` (generic) | ❌ bug lipo Flutter 3.44 + Xcode 27 (mục 3b) — dùng device cụ thể thay thế |
| `dart analyze app/lib` + `dart analyze loading_kit/loading_kit/lib` | ✅ sạch |
