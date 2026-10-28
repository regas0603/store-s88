# Release registry — mỗi host 1 ABI, tool tự tính patch cao nhất mỗi host chạy được

> Trạng thái: THIẾT KẾ (chưa code). Hệ thống làm mới từ đầu: mọi host đều
> được build bằng tool mới, không có host cũ cần tương thích ngược.

Thuật ngữ:
- **host** = 1 bản build app, định danh `host_key = <bundleId>/<platform>/<version_code>`.
  1 bundle có nhiều host (mỗi lần release 1 host mỗi platform).
  Mỗi host có **ABI riêng**, chụp lúc build.
- **patch** = 1 version bytecode `app_content`, dùng chung cho mọi host.

## 1. Mục tiêu

```
patch:        v6  v7  v8  v9 … v14
Host 1..7     ●───●───●───●──…──●    (build lại host khi cần → ABI mới, nhận tiếp)
Host A,B,C    ●───●   ✗              (tool tự phát hiện: v8 cần package khác ABI của A,B,C)
                                      → A,B,C dừng ở v7
Ra v14, cấm chơi v7 → A,B,C force update → store không có bản mới → mở link app D
```

- Không chia mốc cố định. **Tool tự xác định** với mỗi cặp (host, patch) là chạy
  được hay không, rồi suy ra **patch cao nhất** của từng host.
- **Không cần server**: tool tính hết lúc publish, sinh file tĩnh cho từng host.
  Mọi host đọc chung 1 manifest, tra dòng của chính mình.
- Cấm chơi patch cũ → force update. Mở store nếu store đã có bản host chạy được,
  không có thì mở link app khác (D) trong config git.

## 2. Tổng quan luồng

```
 MÁY BUILD (tool)                                   HOST (app trên máy user)
 ─────────────────                                  ────────────────────────
 build host  ──► chụp provides ─┐
                                ├─► registry/ (git) ─► compat ─► sinh file tĩnh
 compile patch ► chụp requires ─┘        ▲                          │
                                         │                          ▼
 bạn khai: policy, retired, store ───────┘            <rs>/app/manifest.json
                                                                    │
                                                    GET manifest, tra hosts[bundle][platform][vc]
                                                    → biết: patch đích, hành động
                                                      (bình thường / mời / ép), link
```

Vì sao không cần server: kết quả chỉ phụ thuộc `provides` của host và `requires`
của patch, cả hai đều biết lúc publish. Lúc chạy không có gì phải tính thêm,
nên 1 file tĩnh là đủ. Bất cứ khi nào registry đổi (patch mới, host mới, đổi
policy, store duyệt bản mới), tool sinh lại `manifest.json` rồi deploy.

## 3. Cách tool xác định tương thích

### 3.1 Bytecode phụ thuộc vào đâu

Lệnh compile (`tools/cmd/dyniface.sh`):

```
dart2bytecode --import-dill <anchor.dill của app/> \
              --validate dist/dynamic_interface.yaml \
              --packages app/.dart_tool/package_config.json …
```

→ Bytecode được link với **kernel và package của host `app/` lúc compile**
("host compile"). `dynamic_interface.yaml` chỉ gồm thư viện `dart:*` và
package tầng host (không có `main_app`/`loading_kit`), theo đơn vị library
(một số entry có `class`).

### 3.2 Hai phía

**Host cung cấp gì (`provides`)**: chụp lúc build host, từ `app/pubspec.lock`
và `dist/dynamic_interface.host.yaml`:

```json
{
  "engine_rev": "4cf2416…",
  "contract_version": 2,
  "packages": { "dio": "5.11.1", "lottie": "3.6.1", "content_kit": "path:6b55d03c…", "…": "…" },
  "iface": ["callable|package:dio/dio.dart", "extendable|package:dio/src/options.dart#_RequestConfig", "…"]
}
```

**Patch cần gì (`requires`)**: chụp lúc compile patch:

- `engine_rev`, `contract_version`: của host compile.
- `packages`: **tên** = package tầng host có trong `pubspec.lock` của
  `../app_package`. **Version** = version trong host compile
  (`app/pubspec.lock`), vì đó là bản bytecode được link.
- `iface`: entry của `dist/dynamic_interface.yaml` lúc compile, **chỉ giữ**
  entry thuộc `dart:*`, `flutter` và các package trong `requires.packages`
  (host compile thêm package module không dùng → host cũ không bị dừng oan).

### 3.3 Luật `compatible(host, patch)`

| Kiểm | Điều kiện |
|---|---|
| engine | `requires.engine_rev == provides.engine_rev` |
| contract | `requires.contract_version == provides.contract_version` |
| package | mỗi package trong `requires.packages`: host có và **cùng version** (path package: cùng hash nội dung) |
| interface | `requires.iface ⊆ provides.iface` |

`max_patch(abi) = max{v | compatible(abi, v), v không bị retract}`; mỗi build
lấy theo `abi_id` của nó. Không cần
liên tục: v8 lệch, v9 trả package về như cũ thì A nhận v9.

### 3.4 Kiểm sâu `--deep` (tuỳ chọn)

Luật trên giả định "cùng version package ⇒ cùng API". Muốn chắc hơn thì chạy
`dart2bytecode --validate` cho patch với **đúng bộ của host đó**
(`anchor.dill` + `dynamic_interface.host.yaml` + `package_config.json`, lưu lúc
build host). Bản đầu: luật §3.3 mặc định, `--deep` khi đổi engine/package lớn.

## 4. Dữ liệu lưu trên git (`registry/`)

```
registry/
  abis/<abi_id>.json        # mỗi ABI khác nhau 1 file: provides đầy đủ (dùng chung giữa các build)
  abis/_deep/<abi_id>/      # anchor.dill + iface + package_config (chỉ khi dùng --deep)
  hosts/<bundleId>.json     # MỌI build của 1 bundle, mỗi build trỏ tới 1 abi_id (máy build ghi)
  store/<bundleId>.json     # CHỈ build đã xác nhận lên store (menu [6]) — nguồn DUY NHẤT của manifest
  bundles.json              # mỗi bundle: active | retired + app thay thế
  patches/v<N>.json         # mỗi patch: requires + file/hash/size
  policy.json               # min_allowed_patch, cấu hình popup
  compat.json               # SINH RA: abi_id → max_patch + lý do dừng
```

Chỉ append / đổi trạng thái, không xoá → `git log registry/` là lịch sử phát hành.

**ABI theo từng bản build, không theo bundle.** 1 bundle qua nhiều lần
release có nhiều ABI. Máy user có thể chạy bản cũ rất lâu nên phải giữ hết:

```
com.example.host1
  android vc10 ─┐
  ios     vc10 ─┴─► abi 3f9a0c1d…   (lottie 3.6.1)   → max v7
  android vc12 ───► abi 3f9a0c1d…   (chỉ sửa shell, ABI không đổi) → max v7
  android vc13 ─┐
  ios     vc13 ─┴─► abi a71be094…   (lottie 3.7.0)   → max v14
```

**`abis/3f9a0c1d7e2b4a55.json`**: `abi_id = sha256(canonical_json(provides))[0:16]`.

```json
{
  "abi_id": "3f9a0c1d7e2b4a55",
  "first_seen": "2026-11-01T…",
  "provides": { "…": "như §3.2 (engine, contract, packages, iface ~10k entry)" }
}
```

`iface` cỡ vài trăm KB, nên lưu 1 lần cho mỗi ABI, các build cùng ABI
(Android + iOS cùng release, bản chỉ sửa shell…) trỏ chung. Compat cũng tính
theo `abi_id` (ít hơn số build nhiều), rồi mới trải ra từng build.

**`hosts/com.example.host1.json`** — mọi bản build (kể cả chưa / không bao giờ
lên store). Máy build (không có VPN) chỉ ghi file này + commit, không deploy.

```json
{
  "bundle_id": "com.example.host1",
  "builds": [
    { "platform": "android", "version_code": 10, "abi_id": "3f9a0c1d7e2b4a55", "built_at": "…", "git_rev": "…" },
    { "platform": "ios",     "version_code": 10, "abi_id": "3f9a0c1d7e2b4a55", "built_at": "…", "git_rev": "…" },
    { "platform": "android", "version_code": 12, "abi_id": "3f9a0c1d7e2b4a55", "built_at": "…", "git_rev": "…" },
    { "platform": "android", "version_code": 13, "abi_id": "a71be0942c33d810", "built_at": "…", "git_rev": "…" },
    { "platform": "android", "version_code": 14, "abi_id": "a71be0942c33d810", "built_at": "…", "git_rev": "…" },
    { "platform": "ios",     "version_code": 13, "abi_id": "a71be0942c33d810", "built_at": "…", "git_rev": "…" }
  ]
}
```

**`store/com.example.host1.json`** — chỉ bản đã xác nhận lên store (menu [6]),
chép dòng từ `hosts/` + `store` + `store_at`. Manifest / plan / validator /
deploy CHỈ đọc file này (android vc14 ở trên chưa lên store → không có trong manifest).

```json
{
  "bundle_id": "com.example.host1",
  "builds": [
    { "platform": "android", "version_code": 10, "abi_id": "3f9a0c1d7e2b4a55", "store": "removed", "store_at": "…", "…": "…" },
    { "platform": "ios",     "version_code": 10, "abi_id": "3f9a0c1d7e2b4a55", "store": "removed", "store_at": "…", "…": "…" },
    { "platform": "android", "version_code": 12, "abi_id": "3f9a0c1d7e2b4a55", "store": "removed", "store_at": "…", "…": "…" },
    { "platform": "android", "version_code": 13, "abi_id": "a71be0942c33d810", "store": "live",    "store_at": "…", "…": "…" },
    { "platform": "ios",     "version_code": 13, "abi_id": "a71be0942c33d810", "store": "live",    "store_at": "…", "…": "…" }
  ]
}
```

- `store`: `submitted | live | removed` (menu [6]) — cả 3 đều tính là đã lên
  store, có trong manifest. Đặt về `built` = bỏ dòng khỏi `store/` (không còn
  trong manifest).
- `rejected` (store từ chối, **chỉ từ `submitted`**): bỏ dòng khỏi `builds`
  (không còn trong manifest), ghi vào mảng `rejected` cùng file để còn lịch sử;
  bản trước của app giữ nguyên. Nộp lại cùng bản → [6] `submitted` (bỏ khỏi `rejected`). Build `removed` vẫn giữ dòng (và
  vẫn có trong manifest): máy đã cài vẫn chạy.
- Bản chưa có trong `store/` (vừa build, ad-hoc phát tester…) → máy cài bản đó
  không thấy dòng của mình → chạy không patch (fail-open) tới khi [6] + deploy.
- Bố cục cũ (`store` nằm trong `hosts/`) tool tự chuyển lần ghi kế tiếp.
- Chỉ đăng ký build chạy được module (engine ddm). Build `debug` engine stock thì bỏ qua.
- `bundle + platform + version_code` phải duy nhất: build lại cùng
  `version_code` mà ra `abi_id` khác → tool từ chối, bắt tăng version_code.
  Cùng `abi_id` (build lại y hệt) → chỉ cập nhật `built_at`/`git_rev`.

**`bundles.json`**

```json
{
  "com.example.host1": { "status": "active", "ios_app_id": null },
  "com.example.hostD": { "status": "active", "ios_app_id": 1234567890 },
  "com.example.hostA": { "status": "retired", "redirect_bundle": "com.example.hostD" }
}
```

- `retired` = bundle không update được nữa. `redirect_bundle` = app D.
- Link store tool tự sinh lúc publish, máy user không phải tra:
  Android `market://details?id=<bundle>`; iOS tra
  `itunes.apple.com/lookup?bundleId=<bundle>` lấy `trackId` →
  `itms-apps://apps.apple.com/app/id<trackId>`. Tra không ra (chưa duyệt /
  sai vùng) → dùng `ios_app_id` khai tay, thiếu nữa thì validator báo.

**`patches/v8.json`**

```json
{
  "version": 8, "file": "app_content_d779701c.bytecode", "hash": "d779701c…",
  "size": 7600000, "min_force_update": 0, "published_at": "…",
  "retracted": false,
  "requires": { "…": "như §3.2" }
}
```

`retracted: true` = loại khỏi tính toán (patch lỗi). Máy đã lên bản đó không tự
lùi về (loader chỉ nhận version lớn hơn), muốn sửa thì ra patch mới.

**`policy.json`**

```json
{
  "min_allowed_patch": 8,
  "force_redirect": { "android": "com.example.hostD", "ios": "com.example.hostE" },
  "soft_prompt": true,
  "soft_prompt_interval_hours": 24
}
```

- `min_allowed_patch`: patch nhỏ hơn số này bị cấm chơi (menu [8] → Cấm patch cũ).
- `force_redirect`: app thay thế **cho mọi máy bị force**, chọn riêng từng
  platform mỗi lần force (menu [8] → Cấm patch cũ / Bắt cập nhật). Có giá trị → mọi
  `url` của `action = force` trên platform đó = store của bundle này.
  `null` cho 1 platform = không thay, mỗi máy mở store của chính app.

## 5. Manifest host đọc

**Mỗi app 1 file** `<rs>/app/manifest/<bundleId>.json` (rs = rs_domain env của
app), chứa kết quả đã tính sẵn cho mọi bản build store của app đó (`hosts` chỉ
có 1 bundle; `patches` chỉ còn patch app đó dùng). Mỗi lần publish chỉ upload:
bytecode mới (nếu có) + các file này. Ví dụ dưới là dạng gộp cũ (nhiều app) —
schema y hệt, xem `templates/manifest.sample.json` cho dạng 1 app.

```json
{
  "schema": 1,
  "generated_at": "2026-12-01T…",
  "latest": 14,
  "soft_prompt_interval_hours": 24,
  "patches": {
    "7":  { "file": "app_content_73ffe17f.bytecode", "hash": "73ffe17f…", "size": 7500000, "min_force_update": 0 },
    "14": { "file": "app_content_ab12cd34.bytecode", "hash": "ab12cd34…", "size": 7700000, "min_force_update": 0,
            "gz_file": "app_content_ab12cd34.bytecode.gz", "gz_size": 2900000 }
  },
  "hosts": {
    "com.example.hostA": {
      "android": { "12": { "patch": 7, "action": "force", "url": "market://details?id=com.example.hostD" } },
      "ios":     { "9":  { "patch": 7, "action": "force", "url": "https://apps.apple.com/app/id1234567890" } }
    },
    "com.example.host1": {
      "android": {
        "12": { "patch": 7, "action": "force", "url": "market://details?id=com.example.host1" },
        "13": { "patch": 14 }
      }
    }
  }
}
```

Ý nghĩa:

| Field | Nghĩa |
|---|---|
| `latest` | patch mới nhất đã phát hành (chỉ để thông tin / log). Host **không** tải theo số này |
| `patches` | thông tin tải của các patch đang là đích của ít nhất 1 host |
| `patches.N.gz_file` / `gz_size` | bản gzip của `file` (~3 lần nhẹ hơn). Host mới tải bản này, giải nén rồi verify `hash` (sha256 của bytecode **đã giải nén**); lỗi → tải `file`. Host cũ bỏ qua 2 field này. Tool sinh `.gz` (mtime=0) khi `register-patch`; patch cũ: `reg regen` |
| `hosts.<bundleId>.<platform>.<version_code>` | dòng của 1 bản build. Host tra bằng bundle id + platform + buildNumber (`package_info_plus`), **không cần bake gì vào binary** |
| `.patch` | patch **cao nhất bản build này chạy được** — host chỉ tải đúng bản này |
| `.action` | `none` (mặc định khi thiếu) / `soft` / `force` |
| `.url` | link đầy đủ nút popup mở (store của chính app hoặc của app thay thế) — tool sinh sẵn, chỉ có khi `action` ≠ `none` |

Ví dụ: `latest = 14` nhưng `hostA/android/12` có `patch: 7` → máy đó chỉ tải
v7 (nếu chưa có), **không bao giờ tải v14**. Tool đã xác định v8+ không chạy
được trên bản build đó.

Key dùng bundle id thật cho dễ đọc. Đánh đổi: mọi app đọc chung file này, nên
ai tải về cũng thấy danh sách bundle id của bạn. Nếu cần giấu, tool có tuỳ
chọn `--hash-keys`, thay key bằng `sha256("<bundleId>/<platform>/<version_code>")[0:16]`.

- `patches` chỉ chứa version đang là đích của ít nhất 1 host.
- Kích thước: ~60 byte / bản build. 1000 bản build ≈ 50 KB. Build có
  `store: removed` và quá N ngày có thể bỏ khỏi file (host không có key →
  fail-open).
- Đổi 1 file là mọi host chuyển cùng lúc, không có lúc upload dở (1 nửa host
  đã thấy patch mới, 1 nửa chưa).
- Tải mỗi lần mở app (thay cho `bytecode.manifest` hiện cũng tải mỗi lần):
  - Host lưu manifest + `ETag` lần trước, gửi `If-None-Match`. File chỉ đổi
    khi publish → hầu hết các lần mở app nhận `304` không body. Host tĩnh
    (nginx/Cloudflare/S3) tự hỗ trợ ETag, không cần server riêng.
  - Bật gzip trên host tĩnh: ~11 KB → ~3–4 KB khi có thay đổi.
  - Không làm chậm boot: vẫn load patch đã cache trước; chỉ `force` mới chặn
    màn hình. `soft` và tải patch mới chạy nền như `executeBackground` hiện tại.
  - Lỗi mạng → dùng manifest đã lưu lần trước (vẫn áp được `force` đã biết).

| `action` | Host làm gì |
|---|---|
| `none` | tải `patches[patch]` nếu `patch > curPatch`, chơi bình thường |
| `soft` | như `none` + popup "Cập nhật / Để sau" mở `url`; từ chối → chơi tiếp `patch` |
| `force` | popup không đóng được, mở `url`; không vào live |

- `rs_domain` vẫn lấy từ `configs/apps/<bundleId>.json` như hiện tại.
- Lỗi manifest (mất mạng, 404, 5xx, nội dung hỏng) → dùng **manifest đã lưu
  gần nhất**: máy chạy tiếp patch đã tải, vẫn giữ quyết định đã biết (vd force).
  Nội dung hỏng không ghi đè bản lưu tốt. Chưa từng lưu manifest → giữ patch
  đang có trên đĩa; chưa có patch nào → app gốc (fail-open).
- Không có dòng của bản build trong `hosts` → giữ patch đang có, không popup.
- Manifest đã lưu nói `force` → lúc mở app luôn tải lại manifest trước khi
  chặn (force không vào live nên check nền không chạy; không refresh thì server
  gỡ force máy cũng không biết).
- Thay cho `bytecode.manifest` hiện tại. Bytecode vẫn dùng chung ở `<rs>/app/`.

### 5.1 Tool tính `action` + `url` thế nào

```
target = max_patch(abi_id của build) # 0 = không chạy được patch nào
store  = max_patch của build `live` mới nhất cùng bundle + platform  (0 nếu không có)

FORCE nếu target < min_allowed_patch (hoặc dính force-vc, xem dưới):
    force_redirect[platform] có     → url = store của bundle force_redirect[platform]
    force_redirect[platform] null   → url = store của chính app
                                      (validator: store phải có build live đạt ngưỡng)

SOFT  nếu target < latest && soft_prompt:
    store > target              → url = store của chính app
    bundle retired              → url = store link của redirect_bundle (app D)
    ngược lại                   → none   (vd host1 đang chờ store duyệt bản mới:
                                          không mời user sang app D)
còn lại → none
```

> **Bản build bị gỡ khỏi store nhưng vẫn chạy được patch mới nhất → kệ nó,
> `action = none`.** Trạng thái store (`removed`) và `retired` **không** tự tạo
> popup. Popup chỉ phát sinh khi bản build **không chạy được** patch mong muốn:
> SOFT khi `target < latest`, FORCE khi `target < min_allowed_patch` (hoặc
> dính `force-vc` do bạn chủ động đặt). Máy cài từ bản đã gỡ vẫn nhận patch mới
> bình thường chừng nào ABI còn tương thích.

Link store (của chính app hay của app D) tool sinh như mô tả ở `bundles.json` (§4).

`force-vc` (§7.8) thêm 1 điều kiện FORCE: build có `version_code <
force_below_vc` của bundle + platform. `url` tính y như trên (cùng
`force_redirect`).

`redirect_bundle` trong `bundles.json` giờ **chỉ dùng cho SOFT** (mời user app
retired sang app khác, từ chối được). FORCE luôn dùng `force_redirect`.

Áp vào ví dụ:

| Thời điểm | Host | target | store | retired | action → url |
|---|---|---|---|---|---|
| ra v8, host1 bản mới chưa live | host1 vc12 | 7 | 7 | – | none |
| | hostA vc12 | 7 | 7 | ✓ | soft → app D |
| host1 vc13 đã live | host1 vc12 | 7 | 8 | – | soft → store host1 |
| | host1 vc13 | 8 | 8 | – | none |
| ra v14, `block-below 8`, chọn Android → hostD | host1 vc12 | 7 | 14 | – | **force → app D** |
| | hostA vc12 | 7 | 7 | ✓ | **force → app D** |
| | host1 vc13 | 14 | 14 | – | none |
| ra v14, `block-below 8`, chọn "Không thay" | host1 vc12 | 7 | 14 | – | **force → store host1** |
| | hostA vc12 | 7 | 7 | ✓ | ✗ validator chặn: store hostA không có bản đạt v8 |

### 5.2 Phía client

- Popup: dùng lại `force_update_dialog.dart`, thêm biến thể SOFT có nút "Để sau".
- SOFT bị từ chối: lưu `dismissed_latest` + thời điểm, không hỏi lại trong
  `soft_prompt_interval_hours` trừ khi `latest` tăng. Host từ 2026-10-15
  đọc interval từ Git JSON per-app (`configs/apps/<bundleId>.json`, thiếu →
  24); field cùng tên trong manifest chỉ còn cho các bản build cũ.
- Text hiển thị của host (nút / popup / loading / lỗi mạng) KHÔNG nằm trong
  code: lấy từ khối `texts` của Git JSON per-app. Khối này token-hoá
  (token = `fnv1a(bundleId:index)`) — sinh từ nguồn chung `configs/texts.json`
  bằng `tools/cmd/gentexts.py`; code tra bằng index (`TK`, `remote_texts.dart`)
  nên binary không chứa tên key. Key thiếu → ẩn chữ / nút hiện icon. Bản resolve
  cache vào prefs để màn trước khi có Git JSON (splash / dialog lỗi mạng) dùng
  bản lần trước.
- FORCE: kiểm ở gate boot, trước khi vào live. Check nền (`executeBackground`)
  đọc lại manifest, nếu chuyển sang `soft`/`force` thì hiện popup trên màn live.
- Bỏ `force_update.min_version_code` và `StoreAvailability` khỏi luồng quyết
  định: ép theo patch dùng `block-below`, ép theo version app (lỗi native) dùng
  `force-vc`. Cả hai đều ghi vào `action`.

## 6. Tool

### 6.1 Wizard `dynpub.sh`

Chỉ cần chạy `bash tools/dynpub.sh`, **không truyền tham số**. Tool hỏi từng
bước, mọi lựa chọn đều là danh sách đánh số, có gợi ý mặc định:

```
$ bash tools/dynpub.sh
Việc cần làm:
  ── Hằng ngày
  [1] Ra patch
  [2] Deploy lên rs_domain
  [3] Xem kế hoạch (plan)
  [4] Đưa patch lên env khác (staging → pre → prod)
  ── Phát hành bản app
  [5] Build host (release app)
  [6] Cập nhật trạng thái store của 1 bản build
  ── Sự cố / ép
  [7] Rút patch lỗi (retract)
  [8] Ép cập nhật / ép restart (bắt cập nhật · cấm patch cũ · min_force_update)
  ── Ít dùng
  [9] Quản lý app (thêm app / đánh dấu app chết / Apple ID / đổi env)
  [10] Link / app thay thế (kiểm link · app thay thế chung · link tải Android)
  [11] Nhận đổi version package host (đổi ABI)
  [12] Đổi rs_domain của env
Chọn [1-12]:
```

**[5] Build host**

```
Bundle id:                                   ← nhập, hoặc chọn số từ danh sách apps/
  [1] com.example.host1
  [2] com.example.hostA
  [3] (nhập bundle id khác)
Chọn [1-3]: 1
Platform:  [1] iOS  [2] Android
Chọn [1-2]: 2
Version [1.0.14+14]:                         ← tự gợi ý = version_code lớn nhất trong registry + 1
Build:  [1] Release engine ddm (khuyến nghị)  [2] Debug engine stock (không đăng ký registry)
Chọn [1-2]: 1
Ngày unlock (…) — hôm nay 2026-10-17, code đang ghi 2026-05-26
  ngày:  2026-10-20 | 20/10/2026 | 20/10 (năm nay)
  hoặc số ngày so với hôm nay:  +3 (3 ngày nữa) | 0 (hôm nay) | -1 (hôm qua = mở ngay)
Ngày unlock: +3
  → unlock 2026-10-20 (Thứ Ba, 3 ngày nữa)   ← ghi vào BootConfig.appReleaseDate (loading_kit)
… build …
ABI: a71be0942c33d810 (đã có — trùng build android vc13)
Bản build này chạy được tới patch: v14
đã commit: dynpub: build …, unlock 2026-10-20 ← chỉ registry/hosts|abis|bundles|compat + boot_config.dart, KHÔNG hỏi deploy
                                               (máy build không có VPN; chưa lên store → manifest không đổi)
```

Bundle id nhập tay mà chưa có `apps/<bundleId>/` → tool hỏi có tạo app mới
không (sang [9] Thêm app).

**[1] Ra patch**: không hỏi bundle (patch dùng chung). Compile → in báo cáo
§6.2 → `Tiếp tục publish? [y/N]` → hỏi deploy + commit.

**[6] Trạng thái store**: chọn bundle → chọn build trong `hosts/` (hiện
platform, version_code, trạng thái hiện tại) → chọn `submitted / live / removed`
(ghi vào `store/`, vào manifest), `rejected` (chỉ từ `submitted` — bỏ khỏi
manifest, bản trước giữ) hoặc `built` (bỏ khỏi `store/`) → deploy + commit.
Làm ở máy có VPN.

**[9] Quản lý app**: chọn bundle →
`[1] Đánh dấu app chết  [2] App sống lại  [3] Khai Apple ID  [4] Đổi env`
(bundle chưa đăng ký → thêm app).

**[8] Ép cập nhật / ép restart**: gom mọi kiểu ép —
`[1] Bắt cập nhật theo version_code (force-vc)  [2] Cấm patch cũ (block-below)
[3] Ép restart (min_force_update)  [4] App thay thế chung (prod)`.

**[8] → [2] Cấm patch cũ**

```
Cấm chơi patch nhỏ hơn [8]: 8
Sẽ bị force: 14 bản build (android 9, ios 5)
App thay thế cho ANDROID:                       ← chỉ liệt kê bundle active, có build android live,
  [1] com.example.hostD  (live vc20, chạy tới v14)   và build đó không bị chính lần force này chặn
  [2] com.example.host1  (live vc13, chạy tới v14)
  [3] Không thay — mỗi app mở store của chính nó
Chọn [1-3]: 1
App thay thế cho iOS:
  [1] com.example.hostE  (live vc11, chạy tới v14)
  [2] com.example.host1  (live vc13, chạy tới v14)
  [3] Không thay — mỗi app mở store của chính nó
Chọn [1-3]: 1
host                              patch  → mở
com.example.hostA/android/12      v7     market://details?id=com.example.hostD
com.example.host1/android/12      v7     market://details?id=com.example.hostD
com.example.hostB/ios/9           v7     itms-apps://apps.apple.com/app/id<hostE>
…
Áp dụng? [y/N]
```

Ghi `min_allowed_patch` + `force_redirect` vào `policy.json` → deploy + commit.
Lần force sau hỏi lại từ đầu (gợi ý mặc định = lựa chọn lần trước).

**[7] Rút patch**: chọn patch từ danh sách → in ảnh hưởng → xác nhận.

**[3] Plan**: hỏi `Tất cả / chọn 1 bundle`, `Kiểm sâu (--deep)? [y/N]`. Chỉ đọc.

Mọi bước ghi (trừ [5] Build host — chỉ tự commit) đều kết thúc bằng câu hỏi
**deploy ngay?**; deploy xong tự commit `registry/` + `publish/` (deploy lỗi /
hoãn → chưa commit, deploy xong ở [2] mới commit — git không ghi trạng thái
server chưa có).

Cờ dòng lệnh (`--app`, `--platform`, `--version`…) vẫn giữ cho CI chạy không
tương tác, nhưng không bắt buộc khi dùng tay.

"Tính lại" = sinh `compat.json` + `publish/<env>/manifest/<bundleId>.json` (1 file mỗi app) cho từng env
(staging / pre / prod — `configs/deploy.json`). Mỗi app thuộc 1 env
(`configs/apps/<bundle>.json` → `"env"`), mỗi patch có danh sách `envs`; manifest
env chỉ chứa app + patch của env đó, policy (block-below) tách theo env.
**Mỗi app 1 file manifest** `<rs>/app/manifest/<bundleId>.json` (cùng schema §5,
`hosts` chỉ còn dòng của app đó — 1 app nhiều version store chung 1 file,
`patches` chỉ còn patch app đó dùng); app tải đúng file của bundleId mình.
Deploy 1 env: đẩy `publish/patches/*.bytecode` + `publish/<env>/manifest/*.json`
lên `<rs_domain env>/app/`, **bytecode trước, manifest sau**
(manifest trỏ tới file chưa có → máy tải 404), đọc lại hash manifest qua SFTP,
xong mới chép config app sang `../configs/apps/` (repo GitHub configs — app đọc
config ở đó; tool không commit, user tự commit + push → đổi rs_domain / đổi env
thì máy chỉ chuyển khi config mới lên GitHub, lúc đó domain mới đã đủ file).

Thứ tự thường gặp khi đổi package: [1] patch v8 (chưa host nào nhận → cảnh báo)
→ [5] build host1..7 (máy build: ghi `hosts/` + commit) → nộp store → [6]
`submitted` → deploy → [6] `live` khi store duyệt → deploy.

`snapshot.sh` / `configs/abi/module_abi.json` không còn là cổng chặn publish: lệch
host cũ là chuyện bình thường, tool chỉ báo host nào dừng ở đâu.

### 6.2 Báo cáo

```
$ bash tools/dynpub.sh patch
… compile v8 OK
host                              v8  max  action  lý do dừng
com.example.host1/android/13      ✓   8    none
com.example.host1/android/12      ✗   7    soft    lottie: host 3.6.1 ≠ patch 3.7.0
com.example.hostA/android/12      ✗   7    soft    lottie: host 3.6.1 ≠ patch 3.7.0
com.example.hostB/ios/9           ✗   7    soft    package mới: rive (host không có)
Tiếp tục publish? [y/N]
```

### 6.3 Validator (chặn publish)

1. Host `live` có `action = force` mà không có `url`: `force_redirect` null
   và store của chính app chưa có build đạt ngưỡng → user kẹt.
2. Bundle trong `force_redirect` phải `active`, có build `live` trên đúng
   platform, và build đó **không** bị force (nếu không user bị đẩy sang app D
   rồi lại bị force tiếp).
3. Manifest tham chiếu patch thiếu `.bytecode` hoặc lệch hash.
4. `bundle + platform + version_code` trùng nhưng `abi_id` khác.
5. (cảnh báo) Patch không host nào chạy được; bundle `retired` thiếu `redirect`.

## 7. Quy trình vận hành

Mọi việc đều bắt đầu bằng `bash tools/dynpub.sh` rồi chọn số trong menu (§6.1).
Bước nào ghi registry xong (trừ [5] Build host — chỉ tự commit), tool hỏi **deploy**
(mặc định có); deploy xong tự commit `registry/` + `publish/`.

### 7.1 Một lần khi dựng hệ thống
1. Host tĩnh rs_domain: bật HTTPS, gzip, ETag, `Cache-Control: no-cache` cho
   `manifest.json`, cache dài cho `*.bytecode` (tên theo hash, không đổi).
2. Tool tự tạo `registry/policy.json` lần chạy đầu (`min_allowed_patch: 0`).
3. Tạo `configs/deploy.json` (server SSH + URL rs_domain) và `.env` (key SSH,
   `cp .env.example .env`) — xem `tools/README.md`.

### 7.2 Thêm app (host) mới
1. Tạo `apps/<bundleId>/` (§7.13): `app.yaml`, `main_app/`, icon.
2. Tạo `configs/apps/<bundleId>.json` (`api_domain`, `rs_domain`) trên repo configs.
3. Menu **[9] → Thêm app**.
4. iOS: sau khi app được duyệt lần đầu, tool tự tra Apple ID; tra không ra
   → menu **[9] → Khai Apple ID**.

### 7.3 Build release host
1. Máy build (không VPN): menu **[5]** → bundle id → platform → version (tự
   tăng) → build. Tool ghi `registry/hosts/` + tự commit (không hỏi deploy) —
   push để máy deploy kéo về.
2. Xem báo cáo: bản build chạy được tới patch nào.
3. Nộp store → máy có VPN: menu **[6]** → `submitted` → deploy (dòng của build
   vào manifest; chưa [6] thì máy cài bản này chạy không patch).
4. Store duyệt → menu **[6]** → `live` → deploy. Từ đây máy chạy build cũ
   không lên được patch mới sẽ thấy SOFT → store.

### 7.4 Ra patch (host không đổi)
1. Menu **[1]** → xem báo cáo → xác nhận → deploy.

### 7.5 Ra patch cần đổi package host
1. Menu **[1]** → báo cáo: chưa host nào nhận được (cảnh báo, vẫn ghi).
2. Build lại các app còn update được (7.3) → tool tự tính: build mới nhận patch.
3. Nộp store → **[6]** `submitted` → deploy → **[6]** `live` khi duyệt → deploy.
4. App không build lại được → 7.6.

### 7.6 App không update được nữa (chuyển user sang app D)
1. Menu **[10] → App thay thế chung** (prod) → chọn D. Menu **[9]** → chọn app → **đánh dấu app chết** → deploy.
   User app A thấy SOFT "Cập nhật / Để sau" mở app D, từ chối thì chơi tiếp.

### 7.7 Ép bỏ patch cũ (force)
1. Menu **[8] → Cấm patch cũ** → nhập `N` → chọn app thay thế cho **Android** → chọn app thay
   thế cho **iOS** (hoặc "Không thay") → xem bảng ai bị force, mở đâu →
   validator → xác nhận → deploy.
2. Mọi máy bị force trên platform đó mở store của app vừa chọn.

### 7.8 Ép update vì lỗi ở app (không liên quan patch)
1. Build bản sửa (7.3), chờ `live`.
2. Menu **[8] → Bắt cập nhật theo version_code** → chọn app → platform →
   version_code tối thiểu → chọn app thay thế cho platform đó (thường chọn
   "Không thay" để mở store của chính app) → deploy.

### 7.9 Patch lỗi
1. Menu **[7]** → chọn patch → host chưa tải bản đó sẽ dừng ở bản trước → deploy.
2. Máy **đã** lên bản lỗi: ra patch mới sửa lỗi (loader chỉ nhận version lớn hơn).
   `DynmodHealth` vẫn tự bỏ bản crash ngay khi boot như hiện tại.

### 7.10 App bị gỡ khỏi store ngoài ý muốn
1. Menu **[6]** → các build `live` của app đó → `removed`.
2. Đánh dấu app chết (menu **[9]**) + app thay thế chung (menu **[10]**) để sẵn link cho sau này.
3. Deploy.

Máy đang cài app đó **không bị làm phiền gì**: vẫn tải patch mới nhất bình
thường, không popup, chừng nào bản build còn tương thích. Chỉ khi ra patch mà
bản build không chạy được thì mới có SOFT (mời sang app thay thế), và chỉ khi
bạn cấm patch nó đang dừng thì mới có FORCE.

### 7.11 Định kỳ (cron hằng ngày)
1. Menu **[10]** (cron chạy dạng không tương tác): link store của app còn
   `live` và link app thay thế còn mở được không (Play `details?id` 200/404,
   iTunes lookup). Hỏng → báo ngay, vì không có publish thì validator không chạy.
2. Tuỳ chọn: bỏ khỏi manifest build `removed` quá N ngày.

### 7.12 Đổi Flutter / engine
1. Sửa `configs/flutter.json` → `setup.sh`.
2. Patch tiếp theo (7.5) tự không tương thích với mọi host cũ → build lại mọi
   app còn update được; app không build lại được tự dừng ở patch cuối cùng.

### 7.13 Nhiều app trong 1 repo

**1 branch, mỗi app 1 folder**, không chia branch theo app:

- `manifest.json` cần thấy mọi build của mọi app trong **1** `registry/`.
  Chia branch thì mỗi branch 1 registry, lệch nhau, phải gom và xử lý xung đột.
- Shell chung (`app/`, `loading_kit/`, `tools/`) sửa 1 lần cho mọi app. Chia
  branch thì phải merge sang N branch, quên 1 branch là app đó build với shell khác.
- Chia branch dễ làm `pubspec.lock` trôi khác nhau → ABI lệch ngoài ý muốn →
  host dừng ở patch cũ dù bạn không chủ động đổi package.

```
apps/
  com.example.host1/
    app.yaml          # thông tin build của app
    main_app/         # UI màn "sạch" riêng của app
    assets/           # icon, splash
  com.example.hostA/
    …
  _reference/main_app # main_app tối giản: host tham chiếu khi compile patch + khung app mới
app/                  # shell chung — mọi app build từ đây
loading_kit/  tools/  registry/
```

`apps/<bundleId>/app.yaml`

```yaml
bundle_id: com.example.host1
display_name: Weather Check
icon: assets/icon.png          # PNG vuông >= 1024, tool tự sinh mọi cỡ (sips)
android:
  keystore: ~/keys/host1.jks   # ngoài repo; mật khẩu qua env hoặc wizard hỏi
  key_alias: host1
ios:
  team_id: ABCDE12345
  profile: host1_dev           # profile development dùng lúc archive (project ký manual)
  adhoc_profile: host1_adhoc   # profile export mode adhoc
  appstore_profile: host1_store
```

Cách áp (không sửa vĩnh viễn file trong `app/`):
- **Không có bundle id mặc định**: mọi build / chạy dev phải chọn app
  (`dynpub.sh` hoặc `tools/cmd/run.sh`, env `APP_ID` hoặc hỏi chọn).
- Android: `build.gradle.kts` đọc env `APP_BUNDLE_ID`, `APP_DISPLAY_NAME`,
  `APP_KEYSTORE`…; thiếu `APP_BUNDLE_ID` → Gradle dừng với thông báo.
- iOS: chỉ có `ios/Flutter/AppIdentity.xcconfig` (tool ghi lúc build theo
  `app.yaml`, gitignore, xoá sau build) — KHÔNG có giá trị mặc định nào; team +
  profile bắt buộc trong `app.yaml` của từng bundle khi build iOS (trường
  trống → `app_identity.py` tự tìm profile đã cài khớp đúng bundle id, còn hạn,
  chọn hạn xa nhất theo loại dev / ad hoc / app store, rồi ghi vào `app.yaml`;
  không đè giá trị đã ghi); project dùng `$(APP_BUNDLE_ID)`, `$(APP_PROFILE)`…; ExportOptions sinh theo
  `adhoc_profile` / `appstore_profile`.
- Icon: chép đè `res/mipmap-*` + `AppIcon.appiconset`, **backup trước và
  khôi phục sau build** (kể cả build lỗi / bị ngắt — lần mở tool sau tự khôi phục).

Wizard **[5] Build host** với bundle id đã chọn:
1. Xuất `apps/<bundleId>/main_app` → `../main_app_package` (việc
   `build_main_app.sh` đang làm, thêm chọn app). Chạy `check.sh --main-app`
   để cảnh báo nếu main_app của app này kéo version package host khác.
2. Áp bundle id, tên hiển thị, icon, cấu hình ký vào bản build (Android
   `applicationId`, iOS `PRODUCT_BUNDLE_IDENTIFIER`…), không sửa file trong
   `app/` đã commit.
3. Build → chụp ABI → ghi registry.

`main_app` khác nhau có thể kéo package khác nhau. Bản thân
`main_app_package` không tính vào ABI (`HOST_SHELL` trong `abi.py`), nhưng nếu
nó đổi version 1 package host thì app đó tự ra ABI riêng, registry ghi lại đúng.

Build lại 1 app từ code shell cũ: registry lưu `git_rev` từng build →
`git worktree add <dir> <git_rev>`. Không cần giữ branch riêng.

## 8. Phạm vi code (đã triển khai)

| Chỗ | Việc |
|---|---|
| `tools/registry/registry.py` | `provides` / `requires` / `compatible`, registry, compat, action + url, manifest, validator, plan, deploy, check-links |
| `tools/registry/deploy_sftp.py` | deploy từng env (bytecode, manifest, config app) lên rs_domain qua SFTP (key SSH từ `.env`) |
| `tools/registry/app_identity.py` | áp `apps/<bundleId>/app.yaml`: env Android, xcconfig iOS, ExportOptions, icon (backup/khôi phục) |
| `tools/registry/test_registry.py` | test kịch bản: host kẹt, soft/force, redirect, retract, force-vc, removed |
| `tools/dynpub.sh` | wizard §6.1, build theo app, patch với host tham chiếu, hỏi deploy + commit |
| `tools/cmd/build_main_app.sh` | `--src apps/<bundleId>/main_app`; lệch ABI chỉ cảnh báo |
| `tools/cmd/abicheck/abi.py` | `ABICHECK_ALLOW_ABI_DIFF=1`: lệch version package host → cảnh báo (kéo package module vẫn FAIL) |
| `tools/check.sh` | kiểm `apps/*/main_app` + validator registry |
| `app/android`, `app/ios` | bundle id / tên / ký / profile tham số hoá (env + xcconfig) |
| `loading_kit/dyn_loader` | đọc `app/manifest/<bundleId>.json` (tra `hosts[bundle][platform][version_code]`), ETag cache |
| `loading_kit/lib/flow/` + `update/force_update_dialog.dart` | xử lý `action`, biến thể SOFT |
| `app/lib/shell/` | gate boot + nền, popup soft/force trên màn live |

Chi tiết vận hành thêm:
- Patch luôn compile với **host tham chiếu** (`apps/_reference/main_app`): kết
  quả `requires` không phụ thuộc app nào vừa build trước đó.
- `dist/patch_archive/` giữ bản sao mọi patch; retract làm bản cũ thành đích
  thì tool lấy lại từ đây (hoặc tải từ rs_domain), kiểm hash.
- `configs/deploy.json`: server SSH (deploy qua SFTP, `tools/registry/deploy_sftp.py`)
  hoặc lệnh upload từng file + URL kiểm lại; key SSH ở `.env` (xem `tools/README.md`).
- `min_allowed_patch` mặc định 0 (không cấm gì); đặt lớn hơn patch mới nhất → validator chặn.

## 9. Cần chốt

1. `--deep` có bắt buộc trước mỗi lần publish không? Tốn thời gian compile theo
   số host, và phải lưu `anchor.dill` của từng host.
