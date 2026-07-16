# line_fleet_app

LINE 叫車派遣 — 司機/乘客雙端 Flutter App（一 repo 兩 flavor）。

## 架構

```
lib/
├── core/
│   ├── api / ws / push / storage / models
│   └── theme/          # LINE 綠亮暗雙主題（appLightTheme / appDarkTheme）
├── driver/             # M6 司機端（hero 上線、全螢幕接單、行程大按鈕、遺失物工作清單）
├── customer/           # M7 乘客端（卡片版降級／地圖為底＋Bottom Sheet、遺失物協尋）
├── shared/screens/     # 乘客/司機共用畫面（RideChatScreen 即時聊天室）
├── main_driver.dart
├── main_customer.dart
└── main.dart
```

兩 flavor 皆 `themeMode: ThemeMode.system`，主色 `#06C755`（深色 primary `#3DD675`）。
乘客端為**地圖為底＋Bottom Sheet**（`flutter_map` + OpenStreetMap 圖磚，**不需任何 API key**）。

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

## 地圖（乘客端 B2/B3）— 免 API key

地圖用 **`flutter_map` + OpenStreetMap 圖磚**，**不需要任何 API key**，直接 `flutter run` 就能看到地圖。

- 圖磚設定集中在 [`lib/core/util/map_tiles.dart`](lib/core/util/map_tiles.dart)（與 admin 後台同一來源）。
  要換自架或 OpenFreeMap 只需改這一個檔。
- 座標→地址反查用 `geocoding`（走裝置內建 Geocoder，同樣免 key），反查失敗時退回座標字串。
- 司機端「導航去目的地」是開啟外部 Google Maps 的 deep link（URL scheme，不需 key）。

> 2026-07-16 起已完全移除 `google_maps_flutter` 與 `GOOGLE_MAPS_API_KEY`；
> OSM 使用政策見 <https://operations.osmfoundation.org/policies/tiles/>，上線量大時請改自架圖磚。

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
  "dropoff_address": "目的地",
  "dropoff_lat": "25.06",
  "dropoff_lng": "121.55"
}
```

FCM data 的值一律是字串，App 端 `fleetEventFromPushData()` 會把 `eta_sec`／`dist_m`／
`dropoff_lat`／`dropoff_lng` 轉回數值。訂單未指定目的地時，後端省略 dropoff 三個鍵即可。

## 功能進度

詳見 [`docs/TODO.md`](docs/TODO.md)。

- **司機端**：登入→hero 上線→前景服務 GPS→全螢幕接單→大按鈕導航（座標優先）／上車／完成（放棄二次確認）
- **乘客端**：登入→叫車（目的地優先）→階段畫面／地圖 sheet→WS ETA→取消／完成卡
- **司機收入頁（E1）**：首頁「我的收入」入口，月切換顯示趟數／營業額／手續費／實得／月會費／應付總公司，
  串後端 `GET /api/driver/earnings`；金額用 `lib/core/util/money.dart`（分→NT$）。
- **乘客完成卡車資（E2）**：`ride.completed` 帶 `fare_amount_cents` 時顯示「車資 NT$…」，
  與後端 F 系列＋admin 三端對帳通過。
- **即時聊天（2026-07-13）**：乘客↔司機行程內對話——WS `chat.message` 即時遞送（非留言板），
  共用 `RideChatScreen`（氣泡、未讀角標、斷線以 `after` 增量補歷史）；乘客「聯絡司機」、
  司機「聯絡乘客」入口。
- **遺失物協尋（2026-07-13）**：乘客完成卡「物品遺失？聯絡司機」→ 回報→顯示處理費
  （該趟車資×%，建單快照）→ 與司機對話 → 司機尋獲後支付處理費 → 歸還結案；
  司機端 AppBar「遺失物協尋」工作清單（已找到／已歸還／未尋獲結案）。
  處理費% 由 admin 費率設定頁調整（後端 `lost_item_fee_bps`）。
- **司機端概覽地圖（2026-07-16）**：接單後行程卡內嵌地圖（flutter_map + OSM，免 key）——
  自己（綠色計程車）＋目標（前往上車點＝紅釘／行程中＝藍旗）＋兩點連線，相機自動框住兩點。
  **只做「看位置」，不做導航**——turn-by-turn 仍由「導航」按鈕跳外部 Google Maps／Waze。
- **連線韌性（2026-07-16）**：WS 握手完成才回報已連線（不再樂觀說謊）、背景連線不擋登入、
  硬斷線時清理有逾時保護（否則重連鏈會卡死）；司機端「上線但連線中斷」會明確顯示
  「暫時收不到派單」而非假裝正常；API 錯誤一律轉中文（`lib/core/api/api_error.dart`）。
- **UI/UX 翻新（2026-07-10）**：三端 LINE 綠亮暗雙主題。

**目前**：`flutter analyze` 無 issue、`flutter test` **88 passed**。

## 規劃中（尚未實作）

> 以下為 2026-07-16 加入的需求，**都還沒有實作**，僅列出方向；
> 完整規格與待拍板事項見 [`docs/TODO.md`](docs/TODO.md) 與後端
> [line-fleet-dispatch/docs/TODO.md](../line-fleet-dispatch/docs/TODO.md)（N／O 章節，跨端主規格）。

- **多乘客／多停靠點行程**：一張訂單最多 **5 位乘客各自上下車**（最多 10 個停靠點）；
  司機端同步收到全程；車資依**全程實際路線（含繞路）**計算。
  依賴後端新建 `ride_stops` 表——現行 `rides` 是單點對單點，App 端在後端就緒前無法實作。
- **司機車輛資訊**：車種**選單**（轎車／休旅／七人座／無障礙／寵物用車）＋車牌；
  **司機沒填不得接單**（App 強制跳轉引導、後端也會擋，不設寬限期）；
  乘客端顯示車種／車牌／司機聯絡方式，方便路邊對車與事後聯絡。
- **乘客指定車種**：叫車時可指定車種（不指定＝任何車皆可）；派單依車種過濾。
  不只服務寵物車——無障礙／七人座同樣是乘客有需求才指定。
  指定後可用司機變少，更容易叫不到車，取消原因要說清楚是車種問題。
- **寵物用車清潔費**：**乘客指定寵物車**的行程加收清潔費（比例，**上限 30%**）——
  依乘客指定的車種，不是司機的車種。選擇當下就要看到加價，完成卡**分項顯示**「車資＋清潔費」。
- **留言板**：沿用既有 `RideChatScreen`（本來就有 REST 歷史＋WS 即時），
  補上「歷史行程也能進入對話」的入口，讓乘客事後（例如找遺失物）仍能聯絡司機。

## 相關文件

- API key 取得與免費測試流程：[`docs/API_KEYS_SETUP.md`](docs/API_KEYS_SETUP.md)
- 總體進度：`line-fleet-dispatch/docs/STATUS.md`
- 設計規格：`line-fleet-dispatch/docs/superpowers/specs/2026-07-06-fleet-dual-client-design.md`
