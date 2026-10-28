# tools/ — tool dùng hằng ngày

| Tool | Làm gì | Khi nào |
|---|---|---|
| `setup.sh` | Bootstrap máy build + sinh interface | Máy mới, đổi engine, đổi package host |
| `check.sh` | Kiểm app_package, main_app các app, validator registry | Sau MỖI lần convert app_package hoặc sửa main_app |
| `dynpub.sh` | **Wizard** build host từng app / ra patch / store / force / deploy | Mọi việc phát hành |
| `snapshot.sh` | Chấp nhận ràng buộc version mới của app_package | Khi `check.sh` báo app_package đổi ràng buộc và bạn đồng ý |

Tool con xem [cmd/README.md](cmd/README.md). Thiết kế đầy đủ:
[docs/release_registry_design.md](../docs/release_registry_design.md).

## Luồng chuẩn

Chỉ cần chạy `bash tools/dynpub.sh` rồi chọn số — không truyền tham số:

```
── Hằng ngày
[1] Ra patch                       compile → tool tự tính mỗi bản build chạy được tới đâu
[2] Deploy lên rs_domain           bytecode trước, manifest sau
[3] Xem kế hoạch (plan)            [1] tổng quan app: ✓ ABI mới nhất / ⚠ ABI cũ (dừng ở vN vì …) / ☠ đã chết / chưa live
                                   [2-4] kế hoạch: ai chạy tới patch nào, ai bị mời/ép, mở đâu
[4] Đưa patch lên env khác         vd staging → pre → prod
── Phát hành bản app
[5] Build host (release app)       chọn app → platform → kiểu build → NGÀY UNLOCK; version_code TỰ TĂNG mỗi lần build (kể cả debug / không lên store)
                                   → ghi registry/hosts/ + ngày unlock vào loading_kit (BootConfig.appReleaseDate) + TỰ COMMIT,
                                   không hỏi deploy (máy build không có VPN)
                                   ngày unlock: 2026-10-20 | 20/10/2026 | 20/10 | +3 | 0 | -1 (so với hôm nay) — trước ngày đó máy mới cài chạy demo;
                                   debug/profile (không đăng ký) build xong trả lại ngày cũ
[6] Trạng thái store 1 bản build   submitted / live / removed / rejected → registry/store/ (chỉ file này vào manifest)
── Sự cố / ép
[7] Rút patch lỗi (retract)
[8] Ép cập nhật / ép restart      [1] bắt cập nhật theo version_code · [2] cấm patch cũ (block-below)
                                   · [3] ép restart (min_force_update)
── Ít dùng
[9] Quản lý app                    thêm app / đánh dấu app chết / Apple ID / đổi env
[10] Link / app thay thế           [1] kiểm link (cron) · [2] app thay thế chung (prod, bundle Android / iOS)
                                   · [3] link tải Android (APK / trang chủ, MỌI env) — dự phòng: app / app thay thế không có
                                     trên Play, hoặc không có app thay thế → mở link này
                                   Mỗi lần sinh manifest tool kiểm link Android 1 lần (Play từng app + link tải, cache 10 phút);
                                   link hỏng (không có trên Play / 404 / bị chặn) → in ĐỎ ở dòng cuối khi tool chạy xong
[11] Đổi package host (ABI)
[12] Đổi rs_domain của env
[13] Đổi api_domain của env
── Dev
[14] Chạy thử app trên simulator  chọn app → tools/cmd/run.sh ios-sim (tự mở Simulator, áp tên/icon của app)
```

Mỗi bước ghi xong (trừ [5] Build host), wizard hỏi **deploy**; deploy xong thì **tự commit** registry/ + publish/ (deploy lỗi / hoãn → chưa commit, deploy xong ở [7] sẽ commit).

**2 file mỗi app:** `registry/hosts/<bundleId>.json` = MỌI bản build (máy build
ghi, chỉ commit — bản build mới không làm đổi manifest nên không cần deploy);
`registry/store/<bundleId>.json` = CHỈ bản đã xác nhận lên store qua [6]
(`submitted` / `live` / `removed`; `rejected` — chỉ từ `submitted` — bị bỏ
khỏi manifest, bản trước giữ nguyên). Manifest đẩy lên server (máy user tải về)
chỉ sinh từ `store/` → bản chưa xác nhận (kể cả ad-hoc phát tester) chạy
không patch tới khi [6] + deploy ở máy có VPN.

| Tình huống | Làm gì |
|---|---|
| Thêm app | [9] → nhập bundle id → chọn env → sửa `apps/<bundleId>/app.yaml` + `api_domain` trong `configs/apps/<bundleId>.json`. Tự ghi config (env/rs_domain/api_domain) + sinh `texts`. Folder đã có sẵn (copy từ app khác): KHÔNG đụng code, chỉ sửa `bundle_id:` trong app.yaml nếu lệch tên thư mục. |
| Sửa text app (nút, popup, loading…) | sửa `configs/texts.json` → `python3 tools/cmd/gentexts.py` → commit → deploy (chép sang `../configs`, push) |
| Build release | máy build: [5] (tự commit, push để máy deploy kéo về) → nộp store → máy có VPN: [6] `submitted` → deploy → duyệt xong [6] `live` → deploy |
| Ra patch | `check.sh` → [1] → chọn env (vd staging) → xem bảng compat → deploy → [4] đưa lên pre / prod |
| Patch đổi package host | [1] báo FAIL ràng buộc version → [11] nhận version mới (pub get + chụp mốc + commit lock) → [5] build lại các app còn update được → [6] khi lên store → [1] → deploy |
| Android không lên Play | [10] → Link tải Android → nhập link APK / trang chủ (1 lần, áp cả staging / pre / prod). Mỗi lần sinh manifest tool kiểm Play của từng app: app không có trên Play → popup Android của app đó mở link tải; app thay thế chung không có trên Play / không có app thay thế → link tải. Có thể đặt CẢ app thay thế lẫn link tải. `none` = bỏ |
| App chết (bị gỡ / không update được nữa) | [10] → App thay thế chung (1 lần, prod) → [9] → đánh dấu app chết (user được mời sang app thay thế, từ chối được) |
| Cấm patch cũ | [8] → Cấm patch cũ → N → xem trước → áp dụng. Máy bị cấm: update chính app nếu store có bản live chạy được >= N, không thì app thay thế chung |
| Ép update vì lỗi app | build bản sửa → `live` → [8] → Bắt cập nhật theo version_code (không có bản cao hơn → app thay thế chung) |
| Patch lỗi | [7] → máy chưa tải dừng ở bản trước; máy đã tải cần patch mới |
| Patch quan trọng, muốn máy dùng ngay | [8] → Ép restart → chọn patch vN → nhập M (mặc định N): máy đang chạy patch < M, tải xong vN sẽ hiện popup khởi động lại (0 = tắt) → deploy. Gọi tay: `reg patch-force <N> <M>` |

## Dữ liệu

| Đường dẫn | Là gì | Git |
|---|---|---|
| `apps/<bundleId>/` | `app.yaml` (tên, icon, ký) + `main_app/` + `assets/` của 1 app | ✓ |
| `apps/_reference/main_app` | main_app tối giản: host tham chiếu khi compile patch + khung app mới | ✓ |
| `registry/` | `hosts/` mọi bản build (ABI) · `store/` bản đã lên store (nguồn của manifest) · mọi patch + policy | ✓ |
| `publish/<env>/manifest/<bundleId>.json` | manifest RIÊNG từng app (mọi version store của app đó) — máy user đọc `<rs_domain>/app/manifest/<bundleId>.json` | ✓ |
| `publish/patches/*.bytecode` | các patch manifest các env đang trỏ tới (dùng chung) | ✓ |
| `configs/apps/<bundleId>.json` | `env` + `api_domain` + `rs_domain` (tool ghi theo env) + `soft_prompt_interval_hours` (thiếu → 24) + `texts` (TOÀN BỘ text hiển thị của host, ĐÃ token-hoá — sinh tự động, ĐỪNG sửa tay) — deploy chép sang `../configs/apps/` | ✓ |
| `configs/texts.json` | NGUỒN text host dùng CHUNG mọi app (tên key dễ đọc). Sửa đây rồi `python3 tools/cmd/gentexts.py` → sinh `text_keys.dart` + ghi khối `texts` token-hoá vào mọi `configs/apps/*.json`. Code tra text bằng SỐ (index) nên binary không chứa tên key; token = `fnv1a(bundleId:index)` → mỗi app khác nhau. `dynpub` chặn nếu quên sinh lại. | ✓ |
| `dist/patch_archive/` | bản sao mọi patch (lấy lại khi retract) | ✗ |
| `dist/builds/` | APK / IPA đã build | ✗ |
| `configs/deploy.json` | các env: rs_domain + server SSH (xem dưới) | ✓ |
| `.env` | key SSH của từng dev (`cp .env.example .env`) | ✗ |

**Env (staging / pre / prod).** Mỗi app thuộc đúng 1 env (`"env"` trong
`configs/apps/<bundleId>.json`, chọn lúc thêm app, đổi ở [9]). Mỗi env 1
`rs_domain` + 1 manifest chỉ chứa app + patch của env đó. Ra patch ([1]) xong
chọn env; đưa lên env khác sau bằng [4]. block-below ([8] → Cấm patch cũ) theo env; retract
([7]) rút khỏi mọi env. App thay thế chung ([10] → App thay thế chung) chỉ có ở env prod — env khác: app chết không được mời, bị ép mà không có bản cao hơn thì validator chặn.

`configs/deploy.json` — mỗi target = 1 env, file lên `<ssh.path>/app/`
(= `<rs_domain>/app/`) — chỉ bytecode + manifest, config app không lên server:

```json
{"targets": [{"name": "staging", "rs_domain": "https://stg.example.site",
              "api_domain": "https://api-stg.example.site/?command=",
              "ssh": {"host": "1.2.3.4", "port": 22, "user": "deploy",
                      "path": "/var/www/stg"}}]}
```

`api_domain` của target = mặc định cho app MỚI của env đó (tuỳ chọn). Config
app trống `api_domain` → lấy bản trong `../configs/apps/` (app đã chạy) → mặc
định của env. Chép sang `../configs` không bao giờ ghi đè bằng giá trị rỗng.

**Deploy** ([2], hoặc `reg deploy [--env E]… [--bundle B] [--dry-run] [--no-configs]`,
hoặc `python3 tools/registry/deploy_sftp.py …`): mỗi env qua SFTP (paramiko,
thiếu thì tự cài) bytecode → manifest (ghi file tạm rồi rename),
đọc lại hash qua SFTP (không tải lại qua rs_domain — prod không vào được qua VPN), xong hết mới chép config
app sang `../configs/apps/<bundle>.json` (repo GitHub configs clone cạnh repo
này; chỉ đè key tool quản lý, giữ key khác như `force_update`). Tool KHÔNG
commit / push repo configs — **bạn tự commit + push** để app nhận config mới.
Sau mỗi bước ghi, wizard chỉ hỏi deploy các env có thay đổi; chưa deploy thì
tool vẫn nhớ.

**Đổi rs_domain** ([12] / `reg set-rs-domain <env> <url> [--ssh-path P]`):
ghi `deploy.json` + rs_domain mọi config app của env đó → deploy: file lên
domain mới trước, chép config sang `../configs` sau → bạn commit + push repo
configs (máy chỉ chuyển khi config mới lên GitHub, lúc đó domain mới đã đủ file). `reg sync-configs`: kéo rs_domain mọi config về đúng env.

**Đổi api_domain** ([13] / `reg set-api-domain <env> <url>`): ghi `api_domain` của env vào `deploy.json` + `api_domain` mọi config app của env đó → bạn commit + push repo configs sau để app nhận config mới.

Key SSH: `.env` (`SSH_KEY_FILE`, `SSH_KEY_PASS`, xem `.env.example`) — CLI
`--key-file/--key-pass` > env > `ssh.key_file` trong target. Vẫn dùng được
cách cũ: thay `ssh` bằng `"upload": "scp {file} user@host:/var/www/app/{name}"`
(lệnh chạy cho TỪNG file, không upload config).

Host tĩnh rs_domain: bật HTTPS, gzip, ETag; `manifest/*.json` để
`Cache-Control: no-cache`, `*.bytecode` cache dài (tên theo hash).

## Không tương tác (CI / cron)

```bash
bash tools/dynpub.sh release --app com.example.host1 --platform android [--version 1.0.13+13]   # bỏ --version = tự tăng
bash tools/dynpub.sh patch --envs staging[,pre,prod] [--min-force-update N]
bash tools/dynpub.sh reg apps [--env E] | reg android-url [URL|none] | reg plan | reg validate | reg deploy [--env E] [--bundle B] [--dry-run] | reg check-links
DYNPUB_YES=1 …     # tự trả lời Y cho câu hỏi deploy/commit
```

Cron hằng ngày: `bash tools/dynpub.sh reg check-links` — link store / app thay
thế chết thì báo (không có publish thì validator không chạy).

## `setup.sh` — setup máy build

```bash
bash tools/setup.sh                # làm mọi bước còn thiếu (chạy lại vô hại)
bash tools/setup.sh --dry-run      # chỉ in kế hoạch
bash tools/setup.sh --full         # nghiệm thu kèm test dart/flutter
```

Đổi version Flutter/engine: sửa `configs/flutter.json` rồi chạy `setup.sh`.
Patch tiếp theo tự không tương thích với mọi bản build cũ → build lại các app
còn update được; app không build lại được tự dừng ở patch cuối cùng.

## `check.sh` — kiểm trước khi ra patch

```bash
bash tools/check.sh                       # app_package + apps/*/main_app + registry
bash tools/check.sh --main-app <dir> ...  # chỉ kiểm main_app chỉ định
```

## Lưu ý

- Patch luôn compile với **host tham chiếu** (`apps/_reference/main_app`) để kết
  quả không phụ thuộc app nào vừa build trước đó.
- `configs/abi/module_abi.json` giờ chỉ là mốc tham chiếu cho `check.sh`
  (tự chụp lại mỗi lần build host), không còn chặn build/publish.

## Phạm vi

App chỉ build **Android + iOS**. macOS chỉ là máy build (iOS chỉ ký được trên
macOS). Mọi đường dẫn mặc định tương đối từ folder project: **mọi thứ để dùng
nằm trong `../engine`** (`flutter-framework/` = CLI flutter/dart, `out/` = engine
đã build); `../dart-sdk-build` chỉ để build lại engine; module ở `../app_package`.
Chỉ dùng Flutter của engine — xem `CLAUDE.md` §1.

**Ký iOS** (`tools/registry/app_identity.py`, mỗi lần build): profile ghi trong
`apps/<bundleId>/app.yaml` CÓ trên máy (trống thì tự tìm theo bundle id rồi ghi
lại) → ký **Manual**; không có → ký **Automatic** — Xcode → Settings → Accounts
đã đăng nhập Apple ID thuộc team (quyền Admin / App Manager), Xcode tự tạo/tải
profile (`flutter build ipa` truyền sẵn `-allowProvisioningUpdates`). Archive và
export quyết định riêng (vd có profile Development nhưng chưa có App Store →
archive Manual, export automatic). Project đọc `CODE_SIGN_STYLE = $(APP_SIGN_STYLE)`
(mặc định Manual trong `Flutter/{Debug,Release}.xcconfig`). Bản **App Store** ký
Automatic (máy không có profile Development) chỉ archive **không ký**
(`--no-codesign`, vì archive Automatic ký Development mà Apple đòi team có device)
→ `dist/builds/<bundle>_ios_<ver>.xcarchive`, tool mở trong Xcode Organizer để tự
Distribute App. Bản **App Store** ký
Automatic thì archive bằng `Apple Distribution` (`APP_SIGN_IDENTITY`) → Xcode tạo
profile App Store, không cần team có device đăng ký (profile Development thì cần).
Bản ad-hoc vẫn cần device trong team. Máy khác vẫn cần
private key của cert Distribution nếu ký Manual (export `.p12` từ máy cũ).
