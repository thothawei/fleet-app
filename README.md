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
- **iOS 尚未可 build**（2026-07-20）：Xcode 26.6 已裝但工具鏈未打通、CocoaPods 未安裝、
  iOS 端無 flavor 設定。開工步驟見 [`docs/IOS_PLAN.md`](docs/IOS_PLAN.md)。

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

**App 端（司機 flavor）**：

1. 在 [Firebase Console](https://console.firebase.google.com/) 建立專案，新增 Android App，套件名 **`dev.linefleet.line_fleet_app.driver`**
2. 下載 `google-services.json` 放到 `android/app/`（範本 `android/app/google-services.json.example`）
3. （可選）執行 `dart pub global activate flutterfire_cli && flutterfire configure`
4. 登入司機 App 後會自動 `POST /api/driver/device-token`

**後端（dispatch）**：真 FCM 已實作（`FCMPusher`，A2）。啟用方式：

1. Firebase Console → 專案設定 → 服務帳戶 → 產生新的私密金鑰（服務帳戶 JSON）
2. 把 JSON 掛進 dispatch 容器，設環境變數 `FCM_CREDENTIALS_FILE=<容器內路徑>`
3. **未設此變數＝降級成 stub**（只記 log、不真的推），派單路徑不受影響——本地開發不必配 Firebase

推播 data payload 契約（後端 `rideOfferPushData` 已依此送出）：

```json
{
  "type": "ride.assigned",
  "ride_id": "42",
  "address": "上車地址",
  "pickup_lat": "25.03",
  "pickup_lng": "121.56",
  "eta_sec": "300",
  "dist_m": "1200",
  "dropoff_address": "目的地",
  "dropoff_lat": "25.06",
  "dropoff_lng": "121.55"
}
```

FCM data 的值一律是字串，App 端 `fleetEventFromPushData()` 會把座標／`eta_sec`／`dist_m` 轉回數值。
訂單未指定目的地時省略 dropoff 三鍵。**`stops` 不放進推播**（結構化陣列不塞 FCM data）——
多停靠點行程的全程由 App 接單後重讀 `rides/active` 補齊（`acceptOffer` → refreshActive）。

## 功能進度

逐項驗收紀錄詳見 [`docs/TODO.md`](docs/TODO.md)。**主鏈路（叫車→派單→接單→行程→完成→計費）
三端已全通**，後端 N／O／P／O5 系列全部上線且 App 端補完。

### 核心鏈路

- **司機端**：登入 → hero 上線 → 前景服務 GPS → 全螢幕接單 → 大按鈕導航（座標優先）／上車／完成（放棄需二次確認）。
- **乘客端**：登入 → 叫車（目的地優先）→ 階段畫面／地圖 Bottom Sheet → WS ETA → 取消／完成卡。
- **UI/UX（2026-07-10）**：三端 LINE 綠亮暗雙主題。

### 行程進階（N，2026-07-17）

- **多乘客／多停靠點**：一張訂單最多 **5 位乘客各自上下車**（最多 10 個停靠點）。
  乘客端 `StopsEditor` 漸進展開編輯（預設單一目的地畫面不變）；司機端 `RideStopsList`
  依序列出全程、**只有下一站給操作**（已上車／已下車／跳過）。
- **概覽地圖多點連線**：`DriverRideMap` 畫出全程停靠點＋折線串「司機→下一站→後續」——
  下一站全彩、之後半透明、已到達灰色、**已跳過不畫**（畫了會誤導路線）。
- **推播喚醒補齊全程**：`stops` 不放進 FCM data，接單後 `acceptOffer → refreshActive`
  重讀 `rides/active` 補齊全程（N4）。

### 車輛與審核（O／O5）

- **司機車輛資訊（O，2026-07-17）**：車種選單＋車牌設定頁；乘客端 `DriverVehicleCard`
  顯示車種／放大車牌／明碼電話（`tel:` 撥號）。
- **車輛審核四態（O5，2026-07-19）**：司機填／改車輛後需 admin 核准才能接單。
  `_DriverRoot` 四態——未填→強制設定頁、**待審核**→等待頁、**已退回**→顯示原因＋重送審、
  已核准→首頁。**能不能接單一律以後端 `can_accept` 為準**（App 不自行推導；
  舊後端沒這欄時退回 `has_vehicle`，不誤鎖）。admin 在司機管理頁核准／退回（退回須附原因）。
  > 導入時既有已填車輛的司機**祖父化為 `approved`**，不因導入審核被鎖出。
  > 要改成全體重審＝改後端 migration `000022` 的那行 `UPDATE`（見 TODO T4，**會全線停擺，動手前先問**）。

### 金流與計費

- **司機收入頁（E1）**：首頁「我的收入」入口，月切換顯示趟數／營業額／手續費／實得／月會費／應付總公司，
  串後端 `GET /api/driver/earnings`。
- **乘客完成卡車資（E2）**：`ride.completed` 帶 `fare_amount_cents` 時顯示車資，
  與後端 F 系列＋admin **三端對帳通過**。
- **整數台幣（2026-07-15）**：金額一律整數元、不帶小數（`lib/core/util/money.dart`）。
- **乘客指定車種＋寵物車清潔費（P／O6，2026-07-17）**：叫車表單 `VehicleTypePicker`（預設不指定）；
  選寵物車**當場**顯示加價%（查 `GET /api/customer/fees`，**失敗降級「上限 30%」不擋叫車**）；
  完成卡與司機收入頁**分項**顯示清潔費。

### 溝通與售後

- **即時聊天（2026-07-13）**：乘客↔司機行程內對話——WS `chat.message` 即時遞送（非留言板），
  共用 `RideChatScreen`（氣泡、未讀角標、斷線以 `after` 增量補歷史）。
- **遺失物協尋（2026-07-13）**：完成卡「物品遺失？聯絡司機」→ 回報 → 顯示處理費
  （該趟車資×%，**建單當下快照**）→ 與司機對話 → 司機尋獲 → 乘客支付 → 歸還結案；
  司機端 AppBar「遺失物協尋」工作清單。處理費% 由 admin 費率設定頁調整（`lost_item_fee_bps`）。
- **我的行程歷史（2026-07-19）**：乘客首頁右上「我的行程」列出過去行程（狀態／路線／時間／車資）；
  **有司機的行程可事後「聯絡司機」**開對話。後端 `GET /customer/rides`（只回本人）。
- **取消原因呈現（P4，2026-07-17）**：以機器可讀 `cancel_reason` 判斷（**不 parse 文案**），
  叫車表單頂部通知卡；指定車種找不到時給「改用不指定車種」快捷。

### 地圖與連線韌性

- **司機端概覽地圖（2026-07-16）**：接單後行程卡內嵌地圖（flutter_map + OSM，免 key）——
  自己（綠色計程車）＋目標（前往上車點＝紅釘／行程中＝藍旗）。
  **只做「看位置」，不做導航**——turn-by-turn 仍由「導航」按鈕跳外部 Google Maps／Waze。
- **連線韌性（2026-07-16）**：WS 握手完成才回報已連線（不再樂觀說謊）、背景連線不擋登入、
  硬斷線時清理有逾時保護（否則重連鏈會卡死）；司機端「上線但連線中斷」明確顯示
  「暫時收不到派單」而非假裝正常；API 錯誤一律轉中文（`lib/core/api/api_error.dart`）。

**目前狀態（2026-07-20 實測）**：`flutter analyze` 無 issue、`flutter test` **169 passed**。

## 下一步（尚未實作）

完整拆解見 [`docs/TODO.md`](docs/TODO.md)「📋 下次任務」，後端規格見
[line-fleet-dispatch/docs/TODO.md](../line-fleet-dispatch/docs/TODO.md)。

| # | 項目 | 卡在哪 |
|---|------|--------|
| **T1** | 多停靠點的**建單前車資預估** | **等產品拍板**：接受「先搭後知價」（零開發）vs 後端新開報價 API |
| **T2** | A2 **真裝置推播 E2E** | 卡外部資源：程式兩端都寫完了，缺 Firebase 專案憑證 |
| **T3** | A5 **iOS build** | 卡外部資源：需完整 Xcode + CocoaPods |
| **T4** | O5 祖父化改「全體重審」 | 既有決策，**只有你要改才動**（一行 SQL，但會全線停擺） |
| **T5** | A1 真機背景定位驗收、B5 評分／付款真實 API | 需真機／依賴後端 Phase C |

> **T1 是唯一還懸而未決的產品決策**：N5 拍板「車資＝全程實際路線（含繞路）」後，
> 繞路越多車資越高，但乘客建單時完全看不到預估（後端只在完成時定格計費，沒有報價 API）。
> 多停靠點會放大這個問題。**未拍板前不動工。**

## 相關文件

- API key 取得與免費測試流程：[`docs/API_KEYS_SETUP.md`](docs/API_KEYS_SETUP.md)
- 總體進度：`line-fleet-dispatch/docs/STATUS.md`
- 設計規格：`line-fleet-dispatch/docs/superpowers/specs/2026-07-06-fleet-dual-client-design.md`
