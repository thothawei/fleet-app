# line-fleet-app — 補強清單

> 建立：2026-07-08 盤點（以程式碼實測為準）。編號沿用後端 repo 的
> [gap-analysis-plan](../../line-fleet-dispatch/docs/2026-07-07-gap-analysis-plan.md)（A=司機端、B=乘客端）。
> 每完成一項：實跑驗收 → 勾選回填 → commit + push（main）。

## 現況

- 司機端（M6）主鏈路完成：登入→上線→前景 GPS→WS 收派單→接單→導航→上車→完成／放棄。
- 單元測試已有：行程狀態機 + WS 事件解析（`test/widget_test.dart`）。
- 乘客端（M7）**0%**：`lib/main_customer.dart` 仍是 placeholder。
- 遠端已建：`github.com/thothawei/fleet-app`。

## B. 乘客端 App（M7）— 最優先，後端依賴已全部就緒

後端四個乘客端點已上線（`POST /api/rides`、`GET /api/customer/rides/active`、
`GET /api/customer/rides/:id`、`POST /api/rides/:id/cancel-by-customer`，均吃 customer JWT），
比照司機端在 `lib/customer/` 開工，重用 `lib/core/`。

- [ ] B6. 先寫 M7 slice 實作計畫（比照 M6，存後端 repo `docs/superpowers/plans/`）
- [x] B1. 乘客登入/註冊（`lib/customer/` + `CustomerApiClient` + `CustomerTokenStorage`，2026-07-08）
- [~] B2. 叫車帶目的地 → `POST /api/rides`：已完成**地址式最小叫車**（GPS 上車點 + 文字目的地，
      帶 `dropoff_address`，打通司機端「導航去目的地」）。地圖選點**接線已鋪好**（google_maps_flutter
      + geocoding 依賴、Manifest/AppDelegate key 佔位、`MapPickerScreen` + 叫車表單「在地圖上選目的地」按鈕；
      Android debug APK 已可 build）。地圖選點會把精確座標帶進 `dropoff_lat/lng`（手動改地址則退回純地址），
      body 建構有單元測試覆蓋。**待填 key** 才會顯示地圖：AndroidManifest `YOUR_ANDROID_MAPS_API_KEY`、
      iOS AppDelegate `YOUR_IOS_MAPS_API_KEY`。**未做**：iOS `pod install` + 部署目標。
- [~] B4. 行程狀態流：已接 WS 即時訂閱（`ride.accepted`/`driver.arrived`/`ride.picked_up`/
      `ride.completed`/`ride.cancelled` → 立即以 GET active 對帳；15s 輪詢保底）＋ 顯示司機名/ETA
      ＋ App 端取消。**未做**：抵達/上車等更細的分階段畫面。
- [~] B3. 即時追蹤：已訂閱 WS 生命週期事件 + 顯示上車 ETA。**未做**：地圖看車移動——
      需 (1) 後端把 `driver.location` 也發給該 customer（目前僅發 admin 廣播）、(2) 地圖 SDK + API key。
- [ ] B5. 完成後評分/付款入口（依賴後端 Phase C，先留位）
- 整體驗收：模擬器「叫車 → 看到司機移動與 ETA → 司機完成 → 收到完成」整條通。

## A. 司機端收尾

- [ ] A1. **真背景定位**（專案賣點「解 LIFF 死穴」的兌現）：現為 geolocator 前景回報，
      導入 foreground service + 常駐通知（或 flutter_background_geolocation）。
      驗收：鎖屏 10 分鐘後，後台地圖該司機座標仍持續更新。
- [ ] A2. FCM 推播收派單（依賴後端 D1 推播抽象層 + device_tokens 表；需 Firebase 專案 + 真裝置）。
      驗收：App 完全關閉 → 叫車 → 手機跳推播 → 點開可接單。
- [ ] A4. 回填 M6 計畫勾選框（附模擬器實跑證據）＋ 同步後端 repo STATUS.md。
- [ ] A5. iOS build（延後：需完整 Xcode + CocoaPods；Info.plist location always 權限）。

## 被後端擋住的項目

- [x] 司機端「上車後導航去**目的地**」：後端已補完整 dropoff 鏈路（pickup 回應帶 `dropoff_address`、
      司機端 `ride.accepted` 事件帶 dropoff；2026-07-08）。App 端 onTrip 階段已顯示目的地並可導航。
      下單端亦已補：乘客端 B2 最小叫車會帶 `dropoff_address`，端到端已通（LINE 傳位置叫車仍無目的地）。

## 品質/雜項

- [ ] 補司機端 controller 整合層測試（現有測試偏 models/WS 解析；`driver_controller.dart` 722 行無直接覆蓋）。
- [ ] 建 `flutter analyze` + `flutter test` 的 CI（跨 repo 項 E2）。
