# API Key 設定與免費測試流程

> 對象：line-fleet-app（司機／乘客雙端 Flutter）。
> 建立：2026-07-09。最後更新：2026-07-16。

## ⚠️ 地圖已不需要 API key（2026-07-16 起）

**地圖改用 `flutter_map` + OpenStreetMap 圖磚，不需要任何 Google Maps API key。**
`GOOGLE_MAPS_API_KEY`、`local.properties` 的 key 設定、AndroidManifest 的 `geo.API_KEY`、
iOS 的 `GMSServices` 皆已**全數移除**；本文以下的「一、Google Maps API Key」**已失效，僅留作歷史紀錄**。

- 圖磚來源：`lib/core/util/map_tiles.dart`（`tile.openstreetmap.org`，與 admin 後台同源）。
  日後若要換自架／OpenFreeMap，只需改這一個檔。
- 座標→地址反查：`geocoding` 套件走**裝置內建 Geocoder**，同樣免 key（模擬器實測可反查）。
- 司機端「導航去目的地」仍是開啟外部 Google Maps app 的 deep link（`lib/core/util/maps.dart`），
  那是 URL scheme、**不需要 key**。

## 現在還需要的 key（1 組）

| 用途 | key / 檔案 | 卡住的功能 | 費用 |
|------|-----------|-----------|------|
| Firebase 推播 | `android/app/google-services.json` | 司機端 A2 FCM 收派單（App 被殺仍可收） | FCM **完全免費** |

不填時：文字叫車／ETA 追蹤、WS 收派單、**地圖全功能**仍可用；推播走後端 `LogPusher` stub。

---

<details>
<summary>（歷史）舊版 Google Maps key 設定說明 — 已不適用</summary>

---

## 一、Google Maps API Key

### 取得步驟（免費）

1. 進 [Google Cloud Console](https://console.cloud.google.com/) → 建立專案（或選現有）。
2. **啟用帳單**：Maps Platform 一律要求綁定帳單帳戶才會發 key，但（見下）原生手機地圖不收費。首次註冊另有一次性試用額度。
3. 「API 和服務 → 程式庫」啟用：
   - **Maps SDK for Android**（跑 Android 才需要）
   - **Maps SDK for iOS**（要跑 iOS 才需要）
   - **Maps JavaScript API**（跑 Flutter Web 才需要，見下方「Web 平台」）
   - **Geocoding API**（只有在地圖選點要「地址 ↔ 座標」互轉時才需要；純顯示地圖用不到）
4. 「憑證 → 建立憑證 → API 金鑰」，複製產生的 key。
5. **限制這把 key**（重要，避免被盜刷）：
   - 應用程式限制：Android 應用程式 → 加入套件名 `dev.linefleet.line_fleet_app.driver`（司機）與 `dev.linefleet.line_fleet_app.customer`（乘客）＋各自 debug/release keystore 的 **SHA-1**
     （取得 SHA-1：`cd android && ./gradlew signingReport`）。
   - API 限制：只勾上面啟用的那幾個 API。

### 免費額度（2025-03 起的新制）

- **手機原生 SDK（Maps SDK for Android / iOS）的地圖載入不計費、無上限** —— 本 App 乘客端用的就是原生 `GoogleMap` widget，屬此類，**日常開發與測試不會產生費用**。
- Essentials 類 API（Geocoding、Static Maps、Web 動態地圖）每月各有 **10,000 次免費**，超過才按量計費。
- 舊制「每月 $200 美金抵用金」已於 2025-03-01 取消，改為上述「各 API 各自免費額度」。
- 最新數字以官方為準：<https://mapsplatform.google.com/pricing/>

### 填入專案

原生 SDK（讓地圖能渲染）＋ Dart 層（控制是否顯示地圖 widget）用**同一把 key**：

1. 複製 `android/local.properties.example` → `android/local.properties`，填入：
   ```
   GOOGLE_MAPS_API_KEY=你的key
   ```
   （`local.properties` 已在 `.gitignore`，不會被 commit。`build.gradle.kts` 會把它注入 AndroidManifest 的 `com.google.android.geo.API_KEY`。）
2. 執行時再帶一次 Dart define：
   ```bash
   flutter run -t lib/main_customer.dart --flavor customer \
     --dart-define=GOOGLE_MAPS_API_KEY=你的key
   ```

### Web 平台（Flutter Web）

Web 版**不讀** `android/local.properties`，且 `google_maps_flutter_web` 要求
`google.maps` 在建立地圖前就存在於 `window`，否則會拋
`Cannot read properties of undefined (reading 'maps')`。

本專案**不在 `web/index.html` 寫死 script tag**，而是由
[`lib/core/util/maps_js_loader_web.dart`](../lib/core/util/maps_js_loader_web.dart)
在 `main()` 啟動時依 `--dart-define` 的 key 動態注入，key 因此永遠不進版控：

```bash
flutter run -d chrome -t lib/main_customer.dart \
  --dart-define=API_BASE=http://localhost:8080 \
  --dart-define=GOOGLE_MAPS_API_KEY=你的key
```

- 未帶 key 時 loader 為 no-op，不阻擋啟動；地圖選點按鈕停用並顯示提示，改用手動輸入地址叫車。
- key 限制請選「HTTP 參照網址」，開發階段填 `http://localhost:*`。
- Web 版的地圖載入計費歸在 **Maps JavaScript API**（與原生 SDK 的免費規則不同），額度見官方定價頁。

</details>

---

## 二、Firebase FCM（司機端推播）

### 取得步驟（免費）

1. 進 [Firebase Console](https://console.firebase.google.com/) → 建立專案（可掛在同一個 Google Cloud 專案下）。
2. 「新增應用程式 → Android」，**Android 套件名稱**填司機端的 `dev.linefleet.line_fleet_app.driver`。
3. 下載產生的 `google-services.json`，放到 `android/app/`。
   （此檔已加入 `.gitignore`，不會被 commit；範本見 `android/app/google-services.json.example`。）
4. 可選：`dart pub global activate flutterfire_cli && flutterfire configure` 自動產生設定。

### 費用

Firebase Cloud Messaging（推播）**完全免費、無訊息量上限**，不需要升級付費方案。

### 後端搭配

App 端登入後會自動 `POST /api/driver/device-token` 上報 token。但**後端 `line-fleet-dispatch` 目前的 pusher 是 `LogPusher` stub**——要做到「App 被殺點推播仍能接單」，後端需換成真 FCM（用 Firebase 專案的 service account 呼叫 FCM v1 API）。data payload 契約見 [README.md](../README.md#fcm-推播司機端-a2)。

---

## 三、免費測試流程（不花錢、多數不需真機）

### 地圖（乘客端）— 用模擬器即可，**不需任何 key**

1. 啟動 Android 模擬器（**不需**含 Google Play 的 image；OSM 圖磚只走一般網路請求）。
2. `flutter run -t lib/main_customer.dart --flavor customer`（無須任何 `--dart-define`）。
3. 設模擬器 GPS：`adb emu geo fix 121.5654 25.0330`（台北信義區），並授予定位權限。
4. 驗收：地圖為底顯示 OSM 街道圖 → 「在地圖上選目的地」點選 → 地址反查 → 回填 → 叫車。
5. 要驗司機 marker 移動：用司機 API 上線並移動——
   `POST /api/driver/register` → `POST /api/driver/location`（回報位置即上線）→
   乘客叫車後 `POST /api/rides/:id/accept` → 反覆 `POST /api/driver/location` 改座標，
   乘客端地圖的綠色計程車 marker 會隨 WS `driver.location` 移動、相機跟隨、ETA/距離即時更新。
6. **OSM 圖磚免費**，反覆測不會產生帳單（注意 OSM 使用政策，量大請改自架／OpenFreeMap）。

### 推播（司機端）

- **前景推播**：含 Google Play 的模擬器即可收，登入司機 App → 從後端／Firebase Console「Cloud Messaging」發測試訊息 → App 前景跳 `ride.assigned`。
- **App 被殺／鎖屏後台推播**：建議用**真 Android 裝置**驗收（模擬器可行但行為較不穩），且需後端已換上真 FCM。

### 安全檢查（每次都確認）

- `android/local.properties` 與 `android/app/google-services.json` **都已被 gitignore**，勿 commit 真 key。
- 只有 `*.example` 範本檔該進版控。
- （地圖已無 key，不再有「Maps key 外流被盜刷」的風險面。）

---

## 對照 TODO

本文解掉的是 [docs/TODO.md](TODO.md) 中被 key 卡住的 **B2 / B3（地圖）** 與 **A2（FCM）**。拿到 key 後依上面流程驗收，再回填勾選框並 commit。
