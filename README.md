# line_fleet_app

LINE 叫車派遣 — 司機/乘客雙端 Flutter App（一 repo 兩 flavor）。

## 架構

```
lib/
├── core/           # API、WebSocket、推播、定位、models
├── driver/         # M6 司機端
├── customer/       # M7 乘客端
├── main_driver.dart
├── main_customer.dart
└── main.dart
```

## 環境需求

- Flutter 3.44+、**JDK 17**（JDK 26 會導致 Android build 失敗）
- Android SDK 36
- 後端 `line-fleet-dispatch` 跑在 `:8080`

## 執行

```bash
# 司機端（模擬器預設 10.0.2.2:8080）
flutter run -t lib/main_driver.dart --flavor driver

# 乘客端
flutter run -t lib/main_customer.dart --flavor customer

# 真機請指定電腦區網 IP
flutter run -t lib/main_driver.dart --flavor driver \
  --dart-define=API_BASE=http://192.168.1.100:8080
```

## Google Maps（乘客端 B2/B3）

1. [Google Cloud Console](https://console.cloud.google.com/) 啟用 Maps SDK for Android
2. 在 `android/local.properties` 加入（可參考 `android/local.properties.example`）：
   ```
   GOOGLE_MAPS_API_KEY=你的key
   ```
3. 執行時帶入 Dart define（控制是否顯示地圖追蹤 widget）：
   ```bash
   flutter run -t lib/main_customer.dart --flavor customer \
     --dart-define=GOOGLE_MAPS_API_KEY=你的key
   ```

未設定 key 時：文字叫車／ETA 追蹤仍可用，地圖區塊顯示提示文字。

## FCM 推播（司機端 A2）

1. 在 [Firebase Console](https://console.firebase.google.com/) 建立專案，新增 Android App，套件名 **`dev.linefleet.line_fleet_app.driver`**
2. 下載 `google-services.json` 放到 `android/app/`
3. （可選）執行 `dart pub global activate flutterfire_cli && flutterfire configure`
4. 登入司機 App 後會自動 `POST /api/driver/device-token`；後端目前為 `LogPusher` stub，換真 FCM 後 App 被殺仍可收派單

範本檔：`android/app/google-services.json.example`

推播 data payload 契約（後端真 FCM 實作時應帶）：

```json
{
  "type": "ride.assigned",
  "ride_id": "42",
  "address": "上車地址",
  "dropoff_address": "目的地"
}
```

## 功能進度

詳見 [`docs/TODO.md`](docs/TODO.md)。

- **司機端**：登入→前景服務 GPS→WS/FCM 收派單→接單→導航→完成
- **乘客端**：登入→叫車（含目的地）→WS 追蹤 ETA→取消／完成

## 相關文件

- API key 取得與免費測試流程：[`docs/API_KEYS_SETUP.md`](docs/API_KEYS_SETUP.md)
- 總體進度：`line-fleet-dispatch/docs/STATUS.md`
- 設計規格：`line-fleet-dispatch/docs/superpowers/specs/2026-07-06-fleet-dual-client-design.md`
