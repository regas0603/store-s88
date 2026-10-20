# store-s88 — Setup máy mới

> macOS + Xcode (cài tay) là bắt buộc. Không cần Flutter trong PATH.

## Cấu trúc

```
work/
├── store-s88/         ← repo này
├── engine/            ← giải nén engine.zip
├── s88-flutter/       ← clone để gen app_package
├── app_package/       ← sinh ra từ s88-flutter
└── main_app_package/  ← setup.sh tự xuất
```

## 1. Tải engine

Tải từ: https://drive.google.com/file/d/1HcW5at7LTdc4n6q4BDwY6CszKSf-I0Yv/view?usp=drive_link

Giải nén ra NGOÀI repo (cùng cấp):

```bash
cd ..
unzip engine.zip -x "__MACOSX/*"    # ra ./engine/ cùng cấp store-s88
```

## 2. Gen app_package từ s88-flutter

```bash
cd ..
git clone https://github.com/G1-production/s88-flutter.git
cd s88-flutter 
bash convert_to_package.sh --env=prod --hardcode-version    # ra ../app_package
```

## 3. Cấu hình .env

```bash
cd store-s88
cp .env.example .env
```

Điền vào `.env`: `SSH_KEY_FILE` (đường dẫn key SSH) + `SSH_KEY_PASS` (để trống nếu không có pass).

## 4. Setup + check

```bash
bash tools/setup.sh      # idempotent, chạy lại vô hại; xem kế hoạch: --dry-run
bash tools/check.sh      # exit 0 = OK
```

## 5. Sau đó

```bash
bash tools/dynpub.sh     # wizard: [5] build host · [1] ra patch · [6]+[2] lên store
```

## Luật

- Chỉ dùng Flutter của engine (`../engine/flutter-framework/bin/flutter`), KHÔNG dùng `flutter` trong PATH — xem [CLAUDE.md](CLAUDE.md).
- `../app_package` là bản sinh ra — sửa ở `s88-flutter` rồi chạy lại convert, không sửa bản áp.
