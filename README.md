# line_fleet_app

LINE 叫車派遣 — 司機/乘客雙端 Flutter App（一 repo 兩 flavor）。

## 架構

```
lib/
├── core/           # 共用：API、WebSocket、models、storage
├── driver/         # M6 司機端
├── main_driver.dart
├── main_customer.dart  # M7 placeholder
└── main.dart
```

## 環境需求

- Flutter 3.44+、**JDK 17**（JDK 26 會導致 Android build 失敗）
- Android SDK 36
- 後端 `line-fleet-dispatch` 跑在 `:8080`

## 執行（司機端）

```bash
# 模擬器連本機後端（預設 10.0.2.2:8080）
flutter run -t lib/main_driver.dart --flavor driver

# 真機請指定電腦區網 IP
flutter run -t lib/main_driver.dart --flavor driver \
  --dart-define=API_BASE=http://192.168.1.100:8080
```

## M6 司機端功能

- [x] 登入 / 註冊（line_user_id + 密碼 JWT）
- [x] 上線開關 + 定時 GPS 回報
- [x] WebSocket 收派單（`ride.assigned`）
- [x] 接單 → Google Maps 導航 → 上車 → 完成
- [ ] 背景定位（切到 Maps 仍上報）— 待加 foreground service
- [ ] FCM 推播 — 待 M5 推播 + Firebase 設定

## 相關文件

- 總體進度：`line-fleet-dispatch/docs/STATUS.md`
- 設計規格：`line-fleet-dispatch/docs/superpowers/specs/2026-07-06-fleet-dual-client-design.md`
