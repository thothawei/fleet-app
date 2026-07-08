# line-fleet-app — 補強清單

> 建立：2026-07-08 盤點（以程式碼實測為準）。編號沿用後端 repo 的
> [gap-analysis-plan](../../line-fleet-dispatch/docs/2026-07-07-gap-analysis-plan.md)（A=司機端、B=乘客端）。
> 每完成一項：實跑驗收 → 勾選回填 → commit + push（main）。

## 現況

- 司機端（M6）主鏈路完成：登入→上線→**前景服務 GPS**→WS 收派單→接單→導航→上車→完成／放棄。
- 乘客端（M7）最小可用版已落地：登入→叫車（含目的地）→WS 追蹤 ETA→狀態流→取消。
- 單元測試：`test/widget_test.dart`（24 項）。
- 遠端：`github.com/thothawei/fleet-app`。

## B. 乘客端 App（M7）— 收尾

- [ ] B6. M7 slice 實作計畫（可選，主鏈路已通）
- [x] B1. 乘客登入/註冊（2026-07-08）
- [~] B2. 叫車帶目的地：文字 + 地圖選點接線完成。**待填** Google Maps API key 才顯示地圖。
- [~] B3. 即時追蹤：文字 ETA/距離已通；地圖追蹤待 API key。
- [x] B4. 行程狀態流 + App 端取消 + 分階段畫面（尋找／前往／司機已抵達／行程中；2026-07-08）。
- [ ] B5. 完成後評分/付款（依賴 Phase C）
- 整體驗收：模擬器「叫車 → 看到司機 ETA → 司機完成 → 收到完成」整條通。

## A. 司機端收尾

- [x] A1. **真背景定位**（2026-07-08）：`getPositionStream` + Android `ForegroundNotificationConfig`
      前景服務常駐通知；切到 Google Maps / 鎖屏仍回報。權限含通知（Android 13+）與
      `locationAlways` 加分請求。iOS 已補 `UIBackgroundModes: location` + 用途說明。
      **待真機驗收**：鎖屏 10 分鐘後後台地圖座標仍更新。
- [ ] A2. FCM 推播收派單（依賴後端 D1 + device_tokens 表 + Firebase）。
- [x] A4. 回填 M6 計畫勾選框 + 同步後端 STATUS.md（2026-07-08；證據以 commit / `flutter test` 為主，
      A1 鎖屏長跑仍待真機）。
- [ ] A5. iOS build（延後：需完整 Xcode + CocoaPods + pod install）。

## 被後端擋住的項目

- [x] 司機端「上車後導航去目的地」：後端 dropoff 鏈路 + App 端已通（2026-07-08）。

## 品質/雜項

- [ ] 補司機端 controller 整合層測試。
- [ ] 建 `flutter analyze` + `flutter test` 的 CI（跨 repo 項 E2）。
