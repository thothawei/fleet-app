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

1. **座標導航的模擬器 E2E**（本次只做到單元測試）：後端 docker 起來 → 乘客 App 地圖選點下單 →
   司機端接單 → 上車 → 按「導航去目的地」，確認開出的 Google Maps URL 是 `query=lat,lng` 而非地址。
2. **乘客端地圖版**：補 `GOOGLE_MAPS_API_KEY` 後驗上述地圖 sheet 路徑。
3. **A2 真裝置推播**：建 Firebase 專案 + `google-services.json`，後端實作 FCM data payload
   （契約見 README，含 `dropoff_lat/lng`），驗「App 被殺 → 點推播 → 接單卡」。
4. 依賴外部資源、暫不動：A5 iOS build（需完整 Xcode + CocoaPods）。
