# line-fleet-app — 補強清單

> 建立：2026-07-08 盤點（以程式碼實測為準）。最後盤點：2026-07-10。
> 編號沿用後端 repo 的
> [gap-analysis-plan](../../line-fleet-dispatch/docs/2026-07-07-gap-analysis-plan.md)（A=司機端、B=乘客端）。
> 每完成一項：實跑驗收 → 勾選回填 → commit + push（main）。

## 現況

- 司機端（M6）主鏈路完成：登入→hero 上線→**前景服務 GPS**→全螢幕接單→導航→上車→完成／放棄（二次確認）。
- 乘客端（M7）：登入→叫車（目的地優先）→階段共用元件／地圖 Bottom Sheet→WS ETA→取消／完成卡。
- **UI/UX 翻新（2026-07-10）**：LINE 綠亮暗雙主題；司機駕駛情境 UI；乘客地圖為底＋卡片降級。靜態驗收 49 tests 通過；模擬器主鏈路待後端 docker 可起後補跑。
- **座標導航（2026-07-10）**：司機端目的地導航改吃後端 `dropoff_point` 座標，地址僅供顯示與退路。
- 單元測試：`widget_test` + `driver_controller_test` + theme／home widget 測試（54 項）。
- 遠端：`github.com/thothawei/fleet-app`。

## B. 乘客端 App（M7）— 收尾

- [x] B6. M7 slice 實作計畫（2026-07-08：後端 repo
      `docs/superpowers/plans/2026-07-08-m7-customer-app.md`；主鏈路已完成並回填證據，
      剩餘 Slice 5 地圖追蹤／Slice 6 評分付款）。
- [x] B1. 乘客登入/註冊（2026-07-08）
- [~] B2. 叫車帶目的地：文字 + 地圖選點接線完成。填 `GOOGLE_MAPS_API_KEY`（`local.properties` + `--dart-define`）後地圖可顯示。
- [~] B3. 即時追蹤：文字 ETA/距離已通；**地圖追蹤（Slice 5）**已接線（需 API key + 後端 WS `driver.location`）。
- [x] B4. 行程狀態流 + App 端取消 + 分階段畫面（尋找／前往／司機已抵達／行程中；2026-07-08）。
- [~] B5. 完成後評分/付款：**入口佔位已落地**（2026-07-08；`ride.completed` 顯示完成卡
      + 評分／費用按鈕 disabled +「再叫一輛」）。**真實 API 待 Phase C**。
- 整體驗收：模擬器「叫車 → 看到司機 ETA → 司機完成 → 收到完成」整條通。

## A. 司機端收尾

- [x] A1. **真背景定位**（2026-07-08）：`getPositionStream` + Android `ForegroundNotificationConfig`
      前景服務常駐通知；切到 Google Maps / 鎖屏仍回報。權限含通知（Android 13+）與
      `locationAlways` 加分請求。iOS 已補 `UIBackgroundModes: location` + 用途說明。
      **待真機驗收**：鎖屏 10 分鐘後後台地圖座標仍更新。
- [~] A2. FCM 推播收派單（2026-07-08 App 端契約落地）：`firebase_messaging` 整合、
      登入後 `POST /api/driver/device-token`、前景／點擊推播解析 `ride.assigned`。
      2026-07-10 修：FCM data 值一律是字串，`fleetEventFromPushData` 原樣塞進 payload，
      `RideOffer.fromEvent` 的 `as num?` 會丟 `TypeError`（推播接單一啟用就崩，已有回歸測試）。
      **待**：Firebase 專案 + 複製 `google-services.json` + 後端真 FCM 實作（data payload 契約見 README）
      + 真裝置驗收（App 被殺點推播可接單）。
- [x] A4. 回填 M6 計畫勾選框 + 同步後端 STATUS.md（2026-07-08；證據以 commit / `flutter test` 為主，
      A1 鎖屏長跑仍待真機）。
- [ ] A5. iOS build（延後：需完整 Xcode + CocoaPods + pod install）。

## 2026-07-10 修掉的既有阻塞（非 UI 翻新引入）

- [x] Android build 全面失敗：`android/app/build.gradle.kts` 的 `java.util.Properties()`
      在 Gradle Kotlin DSL 被解析為 Java plugin extension。改 `import java.util.Properties`。
- [x] 司機端啟動即崩潰（無 `google-services.json` 的裝置）：`FirebaseMessaging.instance`
      在建構子預設參數就求值，早於 `Firebase.initializeApp()`，try/catch 攔不到
      `[core/no-app]`。改為 initializeApp 後才取 instance，NoOp 降級路徑恢復生效。

## 被後端擋住的項目

- [x] 司機端「上車後導航去目的地」：後端 dropoff 鏈路 + App 端已通（2026-07-08）。
- [x] **改用座標導航**（2026-07-10）：`ride.assigned`／`ride.accepted`／pickup 回應／`rides/active`
      四條路徑都解析 `dropoff_lat/lng`（後者讀 `dropoff_point`）；`mapsNavigationUri()` 有座標時以
      `lat,lng` 為導航目標，無座標才退回地址搜尋——地址字串在 Google Maps 可能解析到同名的錯誤地點。
      驗收：`flutter analyze` 無 issue、`flutter test` 54 passed（新增 5 項）。

## 品質/雜項

- [x] 補司機端 controller 整合層測試（2026-07-08：`test/driver_controller_test.dart`，
      注入 MemoryAuthStore / silent WS / FakeApi，覆蓋登入→派單→接單→上車→完成／放棄）。
- [x] 建 `flutter analyze` + `flutter test` 的 CI（2026-07-08：`.github/workflows/flutter-ci.yml`）。
- [x] **App UI/UX 翻新**（2026-07-10，分支 `claude/fleet-admin-app-ux-redesign-12cc74`）：
      theme tokens、司機 hero／接單 overlay／大按鈕、乘客階段元件＋地圖 sheet；
      規格見 `docs/superpowers/specs/2026-07-10-fleet-ui-ux-redesign-design.md`。
- [x] **模擬器 E2E 驗收**（2026-07-10，`m6_pixel` + 後端 docker）：
      `flutter analyze` 無 issue、`flutter test` 49 passed。
      司機端實跑：hero 上線開關（前景服務啟動）→ WS 收派單全螢幕接單卡 → 接單 →
      前往上車點大按鈕 → 放棄二次確認 dialog → 乘客已上車 → 完成行程（ride #6 status=4）。
      乘客端卡片版實跑：叫車表單「要去哪裡？」→ 配對中 → 司機前往上車點（ETA chip）→
      行程中 → 完成卡（評分／費用佔位＋再叫一輛，ride #41）。
      暗色主題：`cmd uimode night yes` 下深底＋提亮綠，`ThemeMode.system` 生效。
- [ ] **乘客端地圖版（Bottom Sheet）尚未實測**：本機無 `GOOGLE_MAPS_API_KEY`，
      只驗到 `mapsConfigured=false` 的卡片版降級路徑。補 key 後需驗：地圖為底、
      sheet 可拖、司機 marker 隨 WS 移動、浮動登出鈕。

## 下次任務

> 現況（2026-07-12）：司機收入頁（E1）／完成卡車資（E2）已完成，與 admin＋後端**三端對帳通過**。
> 後端計費 F1–F8＋F3 OSRM 里程退路皆已合併進 main，故司機收入頁呈現的車資已是「軌跡 vs 路線取大者」的較準值。
> 以下多為**外部資源卡住**的項目：

0. [x] **聊天／遺失物模擬器實跑** ✅（2026-07-15，`m6_pixel` + 後端 docker，driver/customer 雙 flavor 同機並存）：
   - **聊天（行程中，WS 即時到達）**：完整叫車→接單→上車進「行程中」後開司機端聊天室。
     乘客端以 API 發訊 → **司機 App 聊天室無操作即時顯示**（WS `chat.message` 推播，s16）；歷史以 REST 載入；
     司機 App 打字送出 → 自己泡泡靠右綠底、乘客端 API 收得到（sender_role=driver）。App↔API 雙向即時對話成立。
   - **遺失物協尋整條 UI（open→found→paid→returned）**：乘客完成行程後建協尋單（處理費 NT$17.96＝車資 17962×10% 快照）→
     首頁「進行中協尋」banner 進 `CustomerLostItemScreen`（處理費快照、與司機對話、取消）→
     司機 AppBar「遺失物協尋」**紅色角標即時 +1**（WS `lost_item.created`）→ `DriverLostItemsScreen`「已找到」→
     乘客端「支付處理費 NT$17.96」→ 司機「已歸還」→ 清單顯示「目前沒有待處理的協尋」。狀態轉換與費用快照全程雙端一致。
   - **測試座標**：本機無 `GOOGLE_MAPS_API_KEY`，乘客走卡片版；目的地以 ASCII 地址輸入（`adb input text` 不支援中文）。
   - **實跑中發現 3 個待修（見下「模擬器實跑發現」）**：登入後 WS 未重連、乘客完成卡競態、乘客協尋詳情返回後未刷新。
1. [x] **座標導航的模擬器 E2E** ✅（2026-07-11，`m6_pixel` + 後端 docker）：
   乘客帶 `dropoff_lat/lng` 下單（本機無 `GOOGLE_MAPS_API_KEY`，改以 customer API 注入座標
   繞過需金鑰的選點 UI）→ 司機端接單 → 乘客已上車 → 按「導航去目的地」。
   以 `dumpsys activity` 攔到實際開出的 intent：
   `dat=https://www.google.com/maps/search/?api=1&query=25.0636%2C121.5525`
   → **`query=lat,lng` 而非地址**，斷言成立。後端 ride #4 `dropoff_point=POINT(121.5525 25.0636)`。
   同場加映：完整叫車鏈路 ride #3 走完六狀態（requested→assigned→accepted→driver.arrived
   →picked_up→completed），`driver.arrived` 由 GPS 進上車圍籬自動觸發。
   **待補**：補 `GOOGLE_MAPS_API_KEY` 後改由乘客 App「地圖選點」真實產生座標（本次以 API 注入替代）。
2. **乘客端地圖版**：補 `GOOGLE_MAPS_API_KEY` 後驗上述地圖 sheet 路徑。
3. **A2 真裝置推播**：建 Firebase 專案 + `google-services.json`，後端實作 FCM data payload
   （契約見 README，含 `dropoff_lat/lng`），驗「App 被殺 → 點推播 → 接單卡」。
4. 依賴外部資源、暫不動：A5 iOS build（需完整 Xcode + CocoaPods）。

## 即時聊天／遺失物協尋（2026-07-13 實作）

> 需求：會員（乘客）↔ 司機**即時**對話（WS `chat.message` 推播，非留言板）；
> 乘客弄丟東西可對已完成行程建協尋單聯絡司機並支付「找回處理費」
> （＝該趟車資 × 後台可調的 `lost_item_fee_bps`%，建單當下快照）。
> 後端對應 [line-fleet-dispatch/docs/TODO.md](../../line-fleet-dispatch/docs/TODO.md)「H. 對話與遺失物協尋」。

- [x] **聊天**：共用 `lib/shared/screens/ride_chat_screen.dart`（氣泡、WS 即時收訊以訊息 id 去重、
      REST 發送、`after` 增量補歷史、發送中 spinner、錯誤 banner 可重試）。
      入口：乘客「聯絡司機」（司機途中／行程中，未讀角標）、司機行程卡「聯絡乘客」。
      controller：`chatStream`／`unreadChat`／`setChatVisible`（聊天室開啟不累計、自己回聲不計）。
- [x] **遺失物（乘客）**：完成卡「物品遺失？聯絡司機」→ `CustomerLostItemScreen`
      （回報表單 → 顯示處理費快照 → 對話 → 司機尋獲後「支付處理費」→ 等待歸還；open/found 可取消）；
      首頁列「進行中協尋」卡（WS `lost_item.updated` 即時更新）。
- [x] **遺失物（司機）**：AppBar「遺失物協尋」入口（計數角標）→ `DriverLostItemsScreen`
      （已找到／已歸還／未尋獲結案／聯絡乘客；WS `lost_item.created` 即時進單）。
- 驗收：`flutter analyze` 無 issue、`flutter test` **67 passed**（新增 7：未讀邏輯、清單合併、
  模型解析、乘客操作）；後端 live E2E 30/30（含 WS 即時遞送與快照制，見 dispatch TODO H）。
- 坑：controller `init()` 新增的 `refreshLostItems()` 讓既有 widget 測試卡死 10 分鐘——
  `testWidgets` 跑在 FakeAsync，真網路呼叫永不完成；Fake API 必須覆蓋 init 觸碰的所有端點。
- [x] **模擬器實跑 ✅（2026-07-15）**：`m6_pixel` 雙 flavor 並存，聊天室 WS 即時到達＋協尋 open→found→paid→returned
  整條 UI 雙端跑通（詳見「下次任務 0」）。

## 模擬器實跑發現（2026-07-15）

> 以下為 2026-07-15 模擬器雙端實跑聊天／協尋時**新發現的行為問題**，非當初規劃的功能。
> 程式邏輯的正確性仍由 widget/unit tests＋後端 E2E 30/30 覆蓋；這些是「跨畫面／重連時機」層的缺陷。

1. [x] **登入後 WebSocket 未以新 token 重連** ✅（2026-07-15 修，driver + customer）：
   根因不在 `login()`——`login()` 有走 `_applySession → _ws.connect(newToken)`；真正原因是 `FleetWsClient.disconnect()`
   會設 `_disposed=true` 永久擋掉自動重連（登出時必要），但 `connect()` 從不重置它，導致同次執行內
   「登出→重登」後 `_open()`／`_scheduleReconnect()` 都因 `_disposed=true` 早退，WS 一直連不上（只有冷啟動重建 client 才通）。
   修正：`connect()` 重置 `_disposed=false` 並取消待定 reconnect timer；新增 `test/fleet_ws_client_test.dart`
   （注入 connector 連本機測試伺服器）並反向確認移除修正會 FAIL。flutter analyze 無 issue、flutter test 綠。
2. [x] **乘客「完成卡」競態，導致「完成卡回報遺失」入口可能不出現** ✅（2026-07-15 修）：
   `customer_controller._handleWsEvent` 對 `ride.completed` 先讀 `final active = _activeRide`；若輪詢 `refreshActive()`
   先一步把終態行程的 `_activeRide` 清成 null（active API 對已完成行程回 null），`active == null` 早退，`_completedSummary`
   永不設定，完成卡不顯示。修正：新增 `_lastActiveRide` 鏡像（賦值進行中訂單處一併更新），`ride.completed` 改在
   `active==null` 早退前處理、以 `_activeRide ?? _lastActiveRide` 取 rideId/dropoff（車資仍來自事件 payload）。
   新增 `test/customer_completed_race_test.dart`（重現「輪詢先清空 active，稍後才到 ride.completed」＋rideId 不符不誤設），
   反向確認移除退路會 FAIL。flutter analyze 無 issue、flutter test 綠。
3. [x] **乘客協尋詳情返回再進入未刷新** ✅（2026-07-15 已查根因＋防禦性強化）：
   **不是** http 快取，也不是 widget 殘留。用 `flutter run` 掛 debug log 實測 `fetchLostItemByRide`：
   重進時 API 明確回 `status=found`（HTTP 200），`_load` 也抓到 found，但 `CustomerLostItemScreen.build`
   （第 96-107 行）會拿 `ctrl.lostItems` 裡的同 id 版本蓋掉剛抓到的 `_item`——若清單因漏收 WS `lost_item.updated`
   而停在 open，畫面就顯示過期 open。**主因是發現 1（登入後 WS 未重連）**：原始 E2E 當時登出→重登弄壞 WS，
   乘客收不到 `lost_item.updated`，清單停在 open。發現 1 修好後本次 `flutter run` 實測**已不再複現**
   （log 顯示 `listStatuses=[1:found]`、畫面正確顯示 found）。
   **防禦性強化**：controller `fetchLostItemByRide` 抓到最新單子後順手 `_applyLostItem` 合併回清單，
   讓「新鮮抓取」成為清單權威來源，即使 WS 偶爾漏事件也不顯示過期狀態。新增
   `test/customer_lost_item_refresh_test.dart`（過期 open→抓到 found 應合併為 found；抓到 returned 應移出清單），
   反向確認移除合併會 FAIL。flutter analyze 無 issue、flutter test 72 passed。
   **旁見小項（未做）**：首頁只在下拉刷新才 `refreshLostItems`，登入後不會自動帶出「進行中協尋」banner；
   可考慮在 `login()` 後也 `refreshLostItems`（比照 `init()/restoreSession()`）。

## 手續費／會費／司機收入（2026-07-11 規劃）

> 需求：報表要顯示司機營業狀況（營業額）與應付總公司金額。App 端主要做**司機收入頁**。
> **依賴後端 F7**（`GET /api/driver/earnings`，見
> [line-fleet-dispatch/docs/TODO.md](../../line-fleet-dispatch/docs/TODO.md)「F. 手續費／會費／營運報表」）。
> 車資／手續費由後端於行程完成時定格計算，App 只呈現，**勿在 App 端算錢**。
>
> 已定案：距離自動計費、手續費+會費並存、會費為月費固定金額、費率快照制、
> 金額全系統統一（後端存分、App 顯示除 100）。

> **實作進度（2026-07-11）**：E1、E2 已完成。`flutter analyze` 無 issue、`flutter test`
> 60 passed（新增 money 格式化 3 案、司機收入頁 widget 1 案、E2 完成卡車資 1 案）。
> 金額用 `lib/core/util/money.dart`（分→NT$）。**尚未做**：真裝置/模擬器 E2E 對帳。

- [x] **E1. 司機收入頁** ✅（`lib/driver/screens/driver_earnings_screen.dart`）
      月切換（上/下月，禁未來月），顯示本月趟數、營業額、手續費、實得、月會費、**應付總公司**。
      串後端 F7（`FleetApiClient.fetchEarnings` → `DriverController.fetchEarnings`）。
      司機首頁 AppBar 加「我的收入」入口（payments 圖示）；載入中 spinner、失敗可重試。

- [x] **E2. 乘客端完成卡顯示車資** ✅（`ride_phase_content.dart` + `CompletedRideSummary`）
      `ride.completed` 事件帶 `fare_amount_cents`（後端 tracking.go 已補）→ 完成卡顯示「車資 NT$…」；
      無車資（舊後端）時保留「查看費用（即將開放）」佔位。付款流程仍屬另一題。

**驗收**：`flutter analyze` 無 issue、`flutter test` 60 passed。
**收入頁 E2E 對帳 ✅（2026-07-11，`m6_pixel` + 後端 docker）**：造 2 筆已完成行程（ride #3/#4，
各 fare 8500 分）→ 司機收入頁 2026-07 顯示與後端 `GET /api/driver/earnings` 完全一致——
完成趟數 2、營業額 NT$170.00（17000）、手續費 −NT$25.50（2550，15%）、司機實得 NT$144.50（14450）、
月會費 NT$3,000.00（300000）、應付總公司 NT$3,025.50（302550）。空月（2026-06）全歸零、
與後端一致；月切換 `<` 可用、`>` 在當月禁用（禁未來月）驗到。
**跨端對帳 ✅（2026-07-11，後端 docker）**：以 smoke_test 造新司機（#2 煙霧測試司機）一筆完成行程，
後端 `GET /api/driver/earnings`（app 端來源）與 `GET /api/admin/reports/monthly`（admin 端來源）
對同一司機完全一致：趟數 1、營業額 8500、手續費 1275、實得 7225、月會費 300000、應付總公司 301275（分）。
admin 月報表頁 UI 亦渲染相同數字（NT$85.00／NT$12.75／NT$3,012.75／NT$72.25）。
`流程司機`（#1）列同樣對齊本表上方記錄的 170/25.50/3025.50/144.50——**app E1 ↔ admin G3 ↔ 後端 F6/F7 三端金額全對齊**。
