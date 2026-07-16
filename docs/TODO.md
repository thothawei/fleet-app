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
- [x] B2. 叫車帶目的地 ✅（2026-07-16 完成）：文字 + 地圖選點皆通。改 flutter_map + OSM 後**免 key**，
      模擬器實跑「選點→反查地址→回填→叫車」，後端 `dropoff_point` 座標與選點一致。
- [x] B3. 即時追蹤 ✅（2026-07-16 完成）：文字 ETA/距離 + **地圖追蹤**皆通。模擬器實跑司機 marker
      隨 WS `driver.location` 移動、相機跟隨、距離/ETA 即時更新（1427m/3分 → 676m/2分）。
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
- [x] **乘客端地圖版（Bottom Sheet）✅ 已實測**（2026-07-16）：改用 flutter_map + OSM 後**不需任何 key**，
      地圖為底、sheet 可拖、司機 marker 隨 WS 移動、浮動登出鈕全數模擬器實跑驗過。
      詳見下方「地圖引擎改用 flutter_map + OpenStreetMap」。

## 下次任務

> **🎨 App icon（叫車系統圖示）✅ 已完成（2026-07-15，PR #15）**：品牌綠 LINE green #06C755 + 白色計程車，
> 以 `flutter_launcher_icons` 產生 Android（含 adaptive icon）與 iOS 各尺寸，driver/customer 兩 flavor 共用。

> **💰 金額改用整數台幣（無小數）✅ 已實作（2026-07-15）**：採 A 模型（後端計算落在整數元）。
> App 這端已同步：`lib/core/util/money.dart` `formatCentsAsNtd` 改整數元、不帶小數點（防禦性四捨五入）；
> 司機收入頁、乘客完成卡車資、遺失物處理費與支付金額顯示皆整數。相關測試斷言全部改整數元、flutter test 73 passed。
> **主規格與決策見** [line-fleet-dispatch/docs/TODO.md](../../line-fleet-dispatch/docs/TODO.md)「M. 金額改用整數台幣」。

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
   ~~**待補**：補 `GOOGLE_MAPS_API_KEY` 後改由乘客 App「地圖選點」真實產生座標~~
   ✅ 2026-07-16 已補：改 flutter_map 後由 App 地圖選點真實產生座標，後端 `dropoff_point` 一致（免 key）。
2. ~~**乘客端地圖版**：補 `GOOGLE_MAPS_API_KEY` 後驗地圖 sheet 路徑~~ ✅ 2026-07-16 已驗（見下方 flutter_map 段）。
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
   **旁見小項 ✅（2026-07-16 修，driver + customer）**：原本只在 `init()` 還原 session 與下拉刷新才
   `refreshLostItems`，登入後不會自動帶出「進行中協尋」banner／司機協尋角標。修正：兩端 `_authenticate`
   成功後補 `refreshLostItems()`；`CustomerController` 比照 driver 增加 `wsFactory` 注入點供測試換靜默 WS。
   新增 `test/customer_login_lost_items_test.dart`＋driver_controller_test 一案，反向確認拿掉修正會 FAIL。
   flutter analyze 無 issue、flutter test 75 passed。

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


## 地圖引擎改用 flutter_map + OpenStreetMap（2026-07-16）

> 決策：**放棄 Google Maps，改用 `flutter_map` + OpenStreetMap 圖磚**（免任何 API key，
> 與 admin 後台同一圖磚來源）。原本 B2/B3、「乘客端地圖版尚未實測」都卡在「需 GOOGLE_MAPS_API_KEY」，
> 換 flutter_map 後此前置條件消失，地圖永遠可用。

**改了什麼**：
- 依賴：移除 `google_maps_flutter`，改 `flutter_map: ^8.3.1` + `latlong2`（`geocoding` 保留，走裝置內建 Geocoder，免 key）。
- 乘客端 4 檔改寫成 flutter_map：`customer_map_home_screen`（地圖為底＋sheet）、`customer_tracking_map`、
  `map_picker_screen`（onTap 選點）、`ride_phase_content`（LatLng 改 latlong2）。新增共用 `lib/core/util/map_tiles.dart`（OSM 圖磚常數）。
- 移除整套「無 key 降級」：`AppConfig.mapsConfigured`/`googleMapsApiKey` 刪除、`app.dart` 永遠走地圖版、
  `customer_home_screen._showTrackingMap` 拿掉 key 判斷、刪 `maps_js_loader` 三檔（Google JS 專用）、`main_customer` 清呼叫。
- 清原生 Google 設定：`build.gradle.kts`（移除 mapsApiKey 注入與 Properties import）、`AndroidManifest.xml`
  （移除 geo.API_KEY meta-data）、`ios/Runner/AppDelegate.swift`（移除 GoogleMaps／GMSServices）、`local.properties.example`。
- 測試：`customer_home_widget_test` 改直接建卡片版（widget test 不宜抓網路圖磚）。

**已驗證（2026-07-16，實際執行過的指令）**：
- `flutter analyze` 無 issue。
- `flutter test` **75 passed**（含改寫後的 `customer_home_widget_test`）。
- `flutter build apk --debug --flavor customer` **成功**——這是清掉 Google 原生設定的關鍵證明：
  `AndroidManifest` 不再引用已移除的 `${googleMapsApiKey}` placeholder，Android 仍可編譯。
- 全 repo 殘留掃描：`lib`／`test`／`build.gradle.kts`／`AndroidManifest`／`AppDelegate`／
  `local.properties.example`／`pubspec` 皆無 `google_maps_flutter`／`mapsConfigured`／`geo.API_KEY`／`GMSServices`。

**模擬器實跑驗收 ✅（2026-07-16，`m6_pixel` + 後端 docker，全程截圖＋後端 API 交叉驗證）**：
- **地圖為底**：OSM 圖磚**真實從網路渲染**——台北信義區街道圖，中文地名齊全（臺北市／信義商圈／
  台北101‑世貿／國父紀念館／忠孝東路四段五段／市政府／象山）。**全程未使用任何 API key**。
- **bottom sheet 雙向可拖**：0.42 →拖大到 ~0.85（地圖縮至頂部）→拖小回原位，`DraggableScrollableSheet` 正常。
- **浮動登出鈕**：右上角綠色 FAB 全程在位。
- **地圖選點**：進「選擇目的地」→ 點地圖 → **紅色釘渲染**（MarkerLayer）→ **`geocoding` 反查成功**
  （回「Taipei City Jiantai Village Section 1, Chengde Road 52」，走裝置內建 Geocoder、免 key）→
  「確定」地址回填叫車表單。
- **座標鏈路（後端交叉驗證）**：叫車後 `GET /api/admin/rides/1` 顯示
  `dropoff_point={lat:25.0517, lng:121.5170}`＋`dropoff_address` 與選點反查地址完全一致；
  `pickup_address="目前位置 (25.03300, 121.56540)"` 正是模擬器 `geo fix` 座標 → GPS 自動帶入生效。
- **派單→接單**：司機 `POST /api/driver/location` 上線（Status=1）→ 乘客叫車 → ride #2 `status=1`(assigned)
  → 司機 `POST /api/rides/2/accept` → `status=2`(accepted)、`driver_id=1` →
  App **WS `ride.accepted` 即時**顯示「司機：地圖司機／約 1 分鐘抵達／聯絡司機」。
- **司機 marker 隨 WS `driver.location` 移動＋相機跟隨** ✅：司機回報位置後，地圖出現**綠色計程車 marker**、
  **相機自動移到司機位置**（`_maybeFollowDriver` 的 postFrame `MapController.move`）；再回報一次新位置後，
  綠色 marker 明顯向紅色上車點靠近、地圖同步位移，sheet 即時由
  「距您約 1427 公尺／約 3 分鐘」→「距您約 676 公尺／約 2 分鐘」。

**尚未驗證**：
- iOS：`AppDelegate` 已移除 GoogleMaps，但 iOS build 延後（A5，需完整 Xcode），未編譯驗證。
- OSM 圖磚正式環境使用政策／流量上限未評估（開發測試量無虞；上線量大需改自架或 OpenFreeMap，
  只需改 `lib/core/util/map_tiles.dart` 一處）。
- 旁見小項（既有行為，非本次引入）：`_formatPlacemark` 以 `parts.join('')` 串地址，
  中文 locale 正常（臺北市大安區…），英文 locale 下會黏成「Taipei CityJiantai Village…」。

## 司機端內嵌概覽地圖（2026-07-16）

> 承上：乘客端換 flutter_map 後，司機端也加內嵌地圖。**先釐清一個事實**：司機端原本
> **沒有任何內嵌地圖**，也沒有 `google_maps_flutter` 依賴——只有兩個「導航」按鈕，
> 用 `url_launcher` 開**外部** Google Maps app（URL scheme，本來就免 key）。
> 所以這不是「換掉 Google 地圖」，而是**新增**一塊概覽地圖。

**定位（刻意不做導航）**：`flutter_map` 只渲染圖磚，不做 turn-by-turn 語音導航。
司機開車的實際導航仍交給 Google Maps／Waze（保留原本的導航按鈕）；內嵌地圖只做
「一眼看出方向與距離」的概覽。

**改了什麼**：
- 新增 `lib/driver/widgets/driver_ride_map.dart`：OSM 圖磚、司機自己（綠色計程車）、
  目標點（前往上車點＝紅色 person_pin／行程中＝藍色 flag）、兩點連線、`fitCamera` 框住兩點。
- 嵌入 `driver_home_screen` 行程卡（`_buildRideMap`）；**無目標座標時整塊不顯示**
  （舊後端／LINE 建的無目的地訂單），其餘操作不受影響。
- **座標鏈路補齊**（原本司機端拿不到上車點座標，只有 address 字串）：
  - 後端 `rideAssignedPayload` 補 `pickup_lat/pickup_lng`（fleet-dispatch#22，與 dropoff 對稱）。
  - `RideOffer`／`ActiveRide` 加 `pickupLat/pickupLng`；`acceptOffer` 帶入；
    `ActiveRide.fromBackendJson` 解析 `pickup_point`（App 重啟還原用，後端本來就有送）。
  - `push_payload.dart` 數值白名單加 `pickup_lat/lng`——FCM data 值一律是字串，
    漏掉會讓推播接單在 `as num?` 丟 TypeError（既有坑，見 pitfall-fcm-data-all-strings）。

**驗收 ✅（2026-07-16，`m6_pixel` + 後端 docker，截圖＋交叉驗證）**：
- 靜態：`flutter analyze` 無 issue、`flutter test` **77 passed**（新增 3：WS pickup 座標→acceptOffer、
  rides/active 的 pickup_point 還原、FCM 字串轉型）；反向確認移除修正後對應測試會 FAIL。
- 後端 payload 實測：用 python websockets 連司機 WS，收到的 `ride.assigned` 確含
  `pickup_lat: 25.033, pickup_lng: 121.5654`。
- 模擬器實跑：司機登入→上線（前景服務）→ 收派單卡 #7（573 公尺／ETA 2 分鐘）→ 接單 →
  **地圖顯示 OSM 街道＋綠色計程車（自己）＋紅色上車點釘＋兩點連線＋自動框住兩點**；
  按「乘客已上車」→ chip 變「行程中」→ **地圖自動切換到目的地（藍色旗子＝台北車站）並重新框景**。
  導航按鈕（跳外部 Google Maps）保留。

**實跑發現 → 已修**（見下「WS 斷線的真實狀態與 UI」）：模擬器上 WS 曾 `Connection timed out`，
導致派單事件收不到、接單卡不跳，畫面卻顯示「即時連線正常」；當時以為只是 UI 沒反映，
追下去發現是 WS client 有三個真 bug。


## WS 斷線的真實狀態與 UI（2026-07-16）

> 起因：司機端實跑時 WS `Connection timed out`，司機收不到任何派單，
> 但畫面顯示「上線中／等待派單中」＋「即時連線正常」。原以為只是 UI 沒反映斷線，
> 追根因後發現是 **WS client 本身有三個真 bug**，UI 只是誠實地反映了錯誤的旗標。

**根因（三個獨立 bug，都在 `lib/core/ws/fleet_ws_client.dart`）**：
1. **樂觀宣告連線成功**：`WebSocketChannel.connect()` 同步回傳 channel，但握手是非同步的。
   舊碼在 `_connector(uri)` 回傳當下就 `onConnectionChanged(true)`——還沒連上就說「正常」。
   又因為每 3 秒重連一次、每次都樂觀設 true，UI 幾乎永遠顯示「連線正常」。
2. **連線失敗變 unhandled exception**：從未 await `channel.ready`，失敗時它的 error 沒人接，
   直接噴 `Unhandled Exception: WebSocketChannelException`（logcat 可見），try/catch 也包不到。
3. **重連鏈會默默停擺（最嚴重）**：`_open()` 開頭 `await _channel?.sink.close()` 對**硬斷線**的
   channel 會等 close handshake 而**永不完成**（docker stop／網路消失＝RST，對端不會回 close frame）。
   `_open()` 就卡死在那行，重連鏈停止且無任何例外——**App 從此停在斷線狀態直到重開**。
   這正是先前「重啟 App 才恢復」的真正原因。單元測試沒踩到，是因為測試 server 走正常 close handshake。

**修正**：
- `await channel.ready.timeout(15s)`：真的握手完成才 `onConnectionChanged(true)`；失敗一律進 catch → 排重連（順帶消滅 unhandled exception）。
- `connect()` 改背景連線（`unawaited(_open())`）：握手可能卡到 TCP 逾時，不可拖住登入流程。
- 清理舊連線一律走 `_closeQuietly`（`sink.close().timeout(2s)` + 吞例外），**保證重連鏈不會被卡住或被例外打斷**。
- `_channel` 只在握手成功後才賦值 → `isConnected` 不再說謊。
- **UI**：司機 hero card 在「上線但 WS 斷線」時改紅底＋`cloud_off`＋「連線中斷，暫時收不到派單」
  （原本照樣顯示「等待派單中」，司機會以為自己在接單）。
- **錯誤訊息中文化**：新增 `lib/core/api/api_error.dart`，兩個 api client 的 `_wrap` 共用它。
  舊碼 `message = e.message` 會把 dio 的英文技術訊息原封不動丟到司機畫面上——實跑時整段
  「The connection errored: Connection refused This indicates an error which most likely cannot be
  solved by the library.」出現在 banner。現改為依 `DioExceptionType` 分類的中文訊息（比照 admin 的 `apiError`）。
- **殘留錯誤清除**：位置回報成功＝後端可達，順手清掉上一輪的錯誤 banner（否則連線恢復了還掛著「無法連線」）。

**驗收 ✅（2026-07-16，`m6_pixel` + 後端 docker）**：
- 靜態：`flutter analyze` 無 issue、`flutter test` **88 passed**（新增 8：WS 握手失敗不報 true／
  connect 不擋登入／斷線恢復自動重連／hero 斷線呈現／api_error 分類 7 案）；
  反向確認「樂觀 true」與「hero 忽略 WS」的舊行為都會讓對應測試 FAIL。
- 模擬器完整循環（uiautomator 斷言）：
  1. 後端活 → 「等待派單中」、無錯誤
  2. `docker stop` → 「連線中斷，暫時收不到派單」（紅底 cloud_off）＋「無法連線到伺服器，請檢查網路」，
     且畫面**不再出現** dio 的英文訊息（斷言 `library` 字樣不存在）
  3. `docker start` → **自動重連**，回到「等待派單中」，錯誤 banner 自動清除（修正前會永遠停在斷線）

**待辦**：重連為固定 3 秒間隔，長時間離線會持續重試；量體上線前可評估指數退避（目前每 3 秒一次的成本可接受）。

## 🧍‍♂️🧍‍♀️ 多乘客／多停靠點行程（2026-07-16 規劃，未實作）

> 需求（使用者 2026-07-16）：乘客端可在一張訂單安排**多位客人**各自的上車／下車點，
> 中途設**中斷點**，**最多 5 位**；司機端同步收到「客人 A/B/C/D 在哪上車／下車、最終目的地」，
> 依最終目的地計費。
> **主規格與資料模型見** [line-fleet-dispatch/docs/TODO.md](../../line-fleet-dispatch/docs/TODO.md)「N. 多乘客／多停靠點行程」。
> **這不是陌生人拼車**，是同一張訂單、同行的多位乘客、依序停靠。

**依賴**：後端 N1–N6（`ride_stops` 表、建單 API 帶 stops、`ride.assigned`／`rides/active` 回 stops）。
**App 端在後端就緒前無法實作**（現行 model 只有單一 pickup／dropoff）。

### 乘客端

- [ ] **停靠點編輯 UI**：叫車表單改成可新增／刪除／排序「乘客 + 上車點 + 下車點」。
      ✅ 定案（2026-07-16）：**最多 5 位乘客、各自上下車 → 最多 10 個停靠點**。
      每個點沿用既有 `MapPickerScreen`（flutter_map 選點，免 key）取座標。
      這是目前叫車表單（單一目的地）之外最大的一塊 UI 改動。
- [ ] **模型擴充**：`CustomerRide` 加 `stops`；`createRide` body 帶 `stops` 陣列。
- [ ] **地圖呈現**：`CustomerMapHomeScreen` 的 `_markers()` 要畫出多個停靠點
      （目前只有 pickup 一支紅釘＋司機綠車），並考慮 `fitCamera` 框住全部點。
- [ ] **行程中顯示進度**：目前到第幾站、下一站是誰（若後端做 N7 到站標記）。

### 司機端

- [ ] **接單卡顯示全程**：`RideOffer` 加 `stops`；接單前就看得到「A 在哪上、B 在哪下、最終到哪」。
- [ ] **行程卡依序列出停靠點**：`ActiveRide` 加 `stops`；目前只有單一「上車點／目的地」兩行。
- [ ] **概覽地圖多點**：`DriverRideMap` 現在是「自己 + 單一目標 + 連線」，
      要改成畫出依序的多個停靠點（polyline 串起來），並標示下一站。
- [ ] **導航按鈕**：多停靠點時導航去「下一站」而非最終目的地（`mapsNavigationUri` 已支援座標）。

### App 端待拍板

- 停靠點編輯的 UX：一次填滿 5 位很繁瑣，是否預設 1 位、按「+ 新增乘客」漸進展開？
- 車資預估：乘客建單時要不要先顯示預估車資？（後端目前只在完成時定格計費，無報價 API）

---

## 🚗 司機車輛資訊（車種／車牌）（2026-07-16 規劃，未實作）

> 需求（使用者 2026-07-16，含後續拍板）：乘客端顯示司機的**車種與車牌**；
> 司機**必須先上傳車種車牌才能接單**（**強制跳轉引導、不設寬限期**）；
> 車種為**選單**（轎車／休旅／七人座／無障礙／**寵物用車**）；
> **寵物用車加收清潔費**（上限 30%），**乘客端要分項顯示**；
> 司機換車後乘客仍能查到**當時車輛**與**司機聯絡方式**，並用**留言板**聯絡（沿用既有聊天）。
> **主規格見** [line-fleet-dispatch/docs/TODO.md](../../line-fleet-dispatch/docs/TODO.md)「O. 司機車輛資訊／寵物車清潔費」。

**依賴**：後端 O1–O7（`drivers` 車輛欄位、`GET/PUT /api/driver/vehicle`、派單/接單 gate、
`ride.accepted` 帶車輛資訊與司機電話、`rides` 車輛快照、`pet_cleaning_fee_bps` 與 `cleaning_fee_cents`）。

### 司機端

- [ ] **車輛資訊設定頁**：車種**下拉選單**（轎車／休旅／七人座／無障礙／寵物用車，
      顯示名稱在 App 對應，送後端 code）＋車牌輸入＋**聯絡電話**（`drivers.phone` 欄位已存在，只是沒填寫入口），
      串 `GET/PUT /api/driver/vehicle`。
- [ ] **強制跳轉引導** ✅ 定案（2026-07-16）：未填車輛資訊時**強制導向設定頁**，
      填完才能回到首頁／上線。不是「提示」而是 gate——
      使用者明確要求「強迫司機必須填寫才能開始接單（用跳轉方式引導）」。
      實作點：`driver/app.dart` 的 `_DriverRoot`（目前只有 `isLoggedIn ? Home : Login`），
      加第三種狀態 `已登入但無車輛資訊 → VehicleSetupScreen`。
      註：**後端也會擋**（O3），App 端跳轉只是提早給回饋、不能只靠 App。
- [ ] **`DriverController` 狀態**：加 `vehicle`／`hasVehicle`；`init()`／`login()` 後載入。
      注意 `hasVehicle` 未載入完成前不要誤判成「沒填」而閃跳轉（載入中要有明確狀態）。

### 乘客端

- [ ] **顯示司機車種車牌**：`ride.accepted` 後的「司機前往上車點」階段，
      sheet 目前只顯示「司機：{name}」＋ETA，要加車種與車牌（醒目、方便路邊對車）。
      `CustomerController` 的 `driverName` 旁加 `driverVehicleType`／`driverPlateNumber`。
- [ ] **司機聯絡方式**：同階段顯示可撥打的電話（或留言板入口）。
      **隱私**：僅該趟乘客可見；是否遮罩／轉接號碼依後端拍板（主規格 O 風險 7）。
- [ ] **清潔費分項顯示** ✅ 定案：完成卡不可只給總額，要拆「車資 NT$X ＋ 清潔費 NT$Y」。
      **只有乘客指定寵物車的行程才有清潔費**（依 `required_vehicle_type`，非司機車種）；
      未指定時完成卡不該出現清潔費欄位。
      `CompletedRideSummary` 目前只有 `fareAmountCents`，要加 `cleaningFeeCents`。
      沿用 `money.dart` 的整數元格式（M 已定案）。
- [ ] **留言板**：沿用既有 `RideChatScreen`（H1，已有 REST 歷史＋WS 即時）。
      需確認「行程完成很久之後仍能進入對話」的入口——目前入口綁在進行中行程／協尋單上，
      歷史行程沒有對話入口（**可能要加**）。

### 乘客指定車種（✅ 2026-07-16 拍板採此方案，依賴後端 P1–P5）

> 清潔費依**乘客指定的車種**加收（不是司機車種）→ 乘客端必須能選車種。
> 主規格見 [line-fleet-dispatch/docs/TODO.md](../../line-fleet-dispatch/docs/TODO.md)「P. 乘客指定車種」。
> **不只服務寵物車**——無障礙／七人座同樣是乘客有需求才指定。

- [ ] **叫車表單加車種選擇**：預設「不指定」（任何車種），可選轎車／休旅／七人座／無障礙／寵物用車。
      `createRide` body 帶 `required_vehicle_type`（未選則不帶，維持現行行為）。
- [ ] **選寵物車時當場顯示加價** ✅ 定案：選擇的當下就要看到「將加收清潔費 X%」，
      不能等完成才知道。**依賴後端開乘客可讀的費率端點**（P5；目前費率只有 admin 能讀）。
- [ ] **找不到指定車種的回饋**：指定車種後可用司機大幅變少，更容易「無人接單自動取消」。
      取消原因要讓乘客看得懂是**車種**問題（後端 P4 會給更明確訊息），
      否則乘客只看到「附近暫無可用司機」會困惑。
- [ ] **車種供給為零時**：該選項是否停用／隱藏（依後端是否提供「目前可用車種」查詢，P 風險 2）。

### App 端待拍板

- 車牌顯示格式：是否放大／等寬字型方便對照？（乘客在路邊要快速比對）
- 車種選擇的 UI 形式：下拉選單 vs 橫向卡片（帶圖示＋加價標示）——
  寵物車有加價，用卡片較能同時呈現「車種＋加價」，但佔版面。
