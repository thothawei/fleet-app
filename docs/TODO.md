# line-fleet-app — 補強清單

> 建立：2026-07-08 盤點（以程式碼實測為準）。最後盤點：2026-07-10。
> 編號沿用後端 repo 的
> [gap-analysis-plan](../../line-fleet-dispatch/docs/2026-07-07-gap-analysis-plan.md)（A=司機端、B=乘客端）。
> 每完成一項：實跑驗收 → 勾選回填 → commit + push（main）。

## 現況

- 司機端（M6）主鏈路完成：登入→hero 上線→**前景服務 GPS**→全螢幕接單→導航→上車→完成／放棄（二次確認）。
- 乘客端（M7）：登入→叫車（目的地優先）→階段共用元件／地圖 Bottom Sheet→WS ETA→取消／完成卡。
- **UI/UX 翻新（2026-07-10）**：LINE 綠亮暗雙主題；司機駕駛情境 UI；乘客地圖為底＋卡片降級。靜態驗收 49 tests 通過；模擬器主鏈路待後端 docker 可起後補跑。
  **登入／註冊頁 2026-07-23 補齊翻新**（先前是唯一漏網畫面），詳見下方「🔐 登入頁 UI/UX 翻新＋驗證」。
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
- [~] B5. 完成後評分/付款：**評分已上線 ✅ 2026-07-27**（見下方「⭐ 乘客評分司機」）；
      **付款仍待 Phase C**（無車資時保留「查看費用（即將開放）」佔位，需真金流）。
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
- [~] A5. iOS build — **規劃已展開，見 [`docs/IOS_PLAN.md`](IOS_PLAN.md)**（2026-07-20）。
      **2026-07-21 進度**：CocoaPods 已裝好（`pod 1.17.0`，階段 1-4 ✅）；
      階段 3 不需 Xcode 的缺口先補完——`AppConfig.apiBase` 依平台分流（iOS→`127.0.0.1`）、
      Info.plist 加 ATS `NSAllowsLocalNetworking` 與 `NSLocalNetworkUsageDescription`、
      3-6 查證後確認不需改（現況已走 https 退路）。`flutter analyze` 無 issue、`flutter test` 169 passed。
      **✅ 階段 1–3 全部完成（2026-07-21，使用者跑完 sudo 三行後）**：
      Xcode 26.6 ＋ iOS 26.5 模擬器 ＋ `flutter doctor` 全綠；
      `flutter build ios --no-codesign` **一次過**（20.4MB `.app`，預期的 deployment target 坑沒發生——
      firebase/geolocator/permission_handler 都走 SPM，只有 `flutter_secure_storage` 走 pod）。
      **iPhone 17 Pro 模擬器實跑**：乘客端登入＋OSM 圖磚；司機端登入→車輛 gate 強制跳轉→
      上線（iOS 定位權限對話框）→ **WS 派單接單卡 ride #12** → 接單後內嵌 OSM 概覽地圖。
      `http://` 與 `ws://` 皆通過 ATS，後端 log 交叉驗證。
      **✅ 階段 4 雙 flavor 也完成（2026-07-21）**：9 組 build configuration＋`driver`／`customer`
      兩個 shared scheme，bundle id 對齊 Android（`dev.linefleet.line_fleet_app.driver`／`.customer`），
      顯示名走 xcconfig 變數；模擬器主畫面「司機端」「乘客端」**兩個 icon 並存不互相覆蓋**。
      **✅ 階段 7 收尾**：README 補 iOS 段與 `API_BASE` 平台預設對照表；
      CI 的 `build-ios` job（macos-latest，customer flavor 不簽名 build）**已在 main 並且真的在跑**——
      2026-07-28 查證最近一次完整執行 `build-ios` **success（6 分鐘）**。
      先前寫的「已寫好但推不上去（token 缺 `workflow` scope）」是**過期敘述，已更正**。
      ⚠️ 但它**不是 branch protection 的必要檢查**：pending 時 PR 照樣合得進去（PR #49 即如此）。
      **2026-07-28 補驗**：`flutter build ios --no-codesign --flavor driver -t lib/main_driver.dart`
      實跑過（`20.6MB`，Xcode build 116.8s）——先前只驗過 customer flavor 的不簽名 build。
      **➡️ 只剩階段 5 實機部署**（需使用者接上 iPhone＋Xcode 選 Personal Team＋手機信任憑證，
      產出是 A1「鎖屏長跑背景定位」的 iOS 實機驗收）**與階段 6 推播**（卡在付費 Apple 帳號）。
      **實機已有、Apple 帳號為免費 Personal Team**：階段 1–5（含實機部署與 A1 背景定位實機驗收）
      皆可執行；只有階段 6（FCM 推播）因 APNs 需付費 Developer Program 而卡住。

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

## 🧪 模擬器實跑驗收（2026-07-18，`m6_pixel` + 後端 docker，全程截圖）

> 驗「概覽地圖多點連線（N）」與「取消原因 UI 呈現（P4）」兩項 UI。
> **實跑抓到 3 個 App bug＋1 個後端 bug**，全數當場修掉（app PR #30/#31、dispatch PR #37）——
> 這些 bug 靜態測試與先前 widget 測試全部測不到，是實跑的直接產出。

**驗過的行為**：
- **多停靠點概覽地圖**：2 位乘客 4 站單（台北101→國父紀念館→台北車站→西門町）。
  接單後地圖畫出全程：折線串「司機→下一站→後續待處理站」、下一站全彩＋乘客標籤、
  之後的站半透明；標記「已上車」→ 該站變灰、下一站前移、地圖即時重框；
  「跳過」（二次確認）→ 該站從地圖消失、清單刪除線；全站處理完 → 折線消失只剩灰標記；
  「乘客已上車」進行程中 → 清單與多點地圖仍在。行程走完 status=4、車資 25500 分（8501m）。
- **WS 路徑（接單當下）**：接單卡帶「多乘客行程（4 站）」chip；按接單**當下**
  行程卡即有全程清單＋多點地圖（不需重啟還原）——此路徑因下述 3 個 bug 原本全斷。
- **取消原因 banner（P4）三種文案全驗**：
  指定寵物車無車 → 「附近暫無寵物用車…」＋**「改用不指定車種」快捷**（按下車種歸不指定、banner 收）；
  不指定但無司機逾時 → 「抱歉，附近暫無可用司機，請稍後再試。」僅「知道了」；
  乘客主動取消 → 「行程已取消。」僅「知道了」。
  P5 順帶驗到 bps=0 顯示「目前不加收清潔費」。

**實跑抓到並修掉的 bug**：
1. **司機首頁整個 body 空白**（app #30）：RideStopsList 操作鈕放 Row，
   全域主題按鈕 minimumSize 寬＝infinity → `BoxConstraints forces an infinite width`。
   **例外只出現在 `flutter attach` console，不進 logcat**——盲抓半天，最後用
   `(sleep;printf 't';…) | flutter attach` 管線送鍵 dump render tree 才定位。
   回歸測試改用真 `appLightTheme` pump（先前用預設主題所以綠）。
2. **「乘客已上車」後多停靠點資訊消失**（app #30）：`ActiveRide.copyWith` 漏帶 stops。
3. **接單當下沒有全程**（app #31）：`RideOffer` 沒解析 stops、`acceptOffer` 沒帶——
   只有重啟 App 走 rides/active 還原才看得到。規劃段「接單卡顯示全程」其實從未實作，
   卻被補完清單的 [x] 蓋過——**分段勾選要對齊，別讓大項 [x] 蓋掉子項 [ ]**。
4. **後端 dispatch 漏接線**（dispatch #37）：`dispatchService.SetStops` 沒在 main.go 呼叫
   → WS `ride.assigned` 一律不帶 stops（N4 只做了一半）。
5. 旁見（環境）：模擬器 Impeller 首幀偶發空白（重啟 App 復現機率高，Skia 同樣出現後
   確認非 renderer 問題而是上述 1.）；customer flavor build **必須帶 `-t lib/main_customer.dart`**，
   漏了會把 driver UI 包進 customer 包。

## 🚨 後端 N/O/P 已全部上線（2026-07-17）——App 端補完進度

> 後端 dispatch 的 **N、O、P 三章已全數實作並合併進 main**（PR #29–#36），
> 且已跑過 docker compose 全服務 live E2E。App 端正在追上。
>
> **最緊急的事實：O3 gate 已上線 → 沒填車輛的司機一律無法接單（後端回 409）。**
> 司機端車輛設定頁是唯一解，已於本批完成。

**App 端補完清單**：

- [x] **司機車輛設定頁＋強制跳轉**（O2／O3）✅ 2026-07-17
      `DriverVehicleScreen`（車種下拉＋車牌）、`_DriverRoot` 加第三態強制導向、首頁 AppBar 入口。
      **三態不可混淆**：`vehicleChecked`（查過沒）／`hasVehicle`（填了沒）——
      查完之前不能判斷「沒填」，否則登入後會閃一下設定頁再跳回首頁；
      查詢失敗時維持「未載入」，不可因網路錯誤就把司機推去強制頁。
      `hasVehicle` 以**後端回的 `has_vehicle` 為準**，不自行判斷「兩欄皆非空」（與 O3 gate 同一條件）。
- [x] **司機收入頁清潔費分項**（O6）✅ 2026-07-17
      等式改為 **營業額 − 手續費 + 清潔費 = 實得**；只在 `> 0` 時顯示該列。
      （後端 `total_cleaning_fee_cents` 曾漏回，由 live E2E 抓到並修掉，見 dispatch PR #36。）
- [x] **乘客端車種選擇＋清潔費預告**（P2／P5）✅ 2026-07-17
      `VehicleTypePicker`：預設「不指定」（維持後端現行行為，也不會讓乘客莫名被加價）。
      選寵物用車時**當場**查 `GET /api/customer/fees` 顯示「將加收清潔費 X%」，費率快取一次。
      **查費率失敗靜默降級**顯示「上限 30%」且**不擋叫車、不顯示錯誤**——
      因為查費率失敗而叫不到車是不可接受的。
      選其他車種時說明「找不到時會通知您，不會改派其他車種」（呼應後端 P4 不降級）。
- [x] **乘客端顯示司機車種／車牌／電話**（O4／O7）✅ 2026-07-17
      `DriverVehicleCard`（司機途中階段）：車種顯示名、**車牌放大＋等寬字型＋字距**
      （路邊要能快速比對，這是這張卡存在的理由）、`tel:` 撥號按鈕。
      撥號失敗時把號碼顯示在 SnackBar，不讓乘客卡住。
      無車輛資訊時整塊不顯示（**後端空值不帶鍵**，缺鍵＝沒有該資訊，不留空白欄位）。
- [x] **完成卡清潔費分項**（O6）✅ 2026-07-17
      `CompletedRideSummary` 加 `cleaningFeeCents`／`hasCleaningFee`／`totalCents`。
      有加收時拆「車資 ＋ 寵物車清潔費 ＝ 合計」（拍板：**不可只給總額**）；
      沒加收時維持單行「車資」——後端未加收時不帶該鍵，故 null ＝ 沒加收。
- [x] **取消原因明確化**（P4）✅ 2026-07-17（controller 層；UI 呈現同日完成，見下）
      `CancelReason` enum ＋ `cancelMessage()`：**用機器可讀的 code 判斷，不 parse 文案**。
      指定車種找不到 → 「附近暫無寵物用車，請稍後再試或改用不指定車種重新叫車」；
      `shouldSuggestAnyVehicle()` 供 UI 決定要不要給快捷操作。
      **容忍缺席**：只有逾時取消帶 `cancel_reason`，乘客主動取消／司機放棄解析為 null →
      走泛用「行程已取消。」，不編故事。未知 code 也回 null（後端新增原因時不崩潰）。
- [x] **多乘客／多停靠點 UI**（N，最大塊）——**全部完成（2026-07-17）**
      - [x] **資料鏈路**：`RideStop`／`StopKind`／`StopInput`／`PassengerTrip`／`buildStops`；
            `ActiveRide` 加 `stops`／`hasStops`／`nextStop`（單點訂單為空 list ＝ 既有行為）。
            座標解析同時吃 num 與 String——FCM data 值全是字串（見 pitfall-fcm-data-all-strings）。
      - [x] **司機端行程卡**（N6／N7）：`RideStopsList` 依序列出全程，每站給「是誰、在哪、處理了沒」；
            **只有「下一站」給操作**（已上車／已下車／跳過），一次一件事避免誤按後面的站；
            已跳過的站用刪除線。跳過需二次確認並說明「不可復原、不計入車資」。
            標記後**重讀 active** 讓狀態由後端決定，不在本地猜。
      - [x] **乘客端停靠點編輯** ✅ 2026-07-17：`StopsEditor`。
            **預設不啟用**（多數行程只有一位乘客，維持既有單一目的地流程最簡單）；
            按「多位乘客同行」展開後**預設 1 位**、按「+ 新增乘客」漸進增加
            （App 端待拍板項，此為建議方案——一次逼使用者填滿 5 位太繁瑣）。
            啟用時**隱藏單一目的地欄位**：兩者同時出現會讓人以為要各填一次。
            移除乘客後**重新編號**（留下「A、C」會讓司機困惑），資料跟著搬。
            送出前 `buildStops` 轉扁平陣列並**保證**滿足 N2 配對規則；未填完的乘客
            **在本地就擋下**（`請至少填完一位乘客的上車與下車點`）——這種錯不該讓使用者
            跑一趟網路才知道。建單成功後清空編輯狀態。
      - [x] **概覽地圖多點連線** ✅ 2026-07-17：`DriverRideMap` 加 `stops` 模式——
            依序畫出全程停靠點、折線串「司機→下一站→後續待處理站」；
            **下一站全彩醒目、之後的站半透明、已到達灰色**（與 RideStopsList
            「一次一件事」同一原則），marker 下帶乘客標籤（A/B…）。
            **已跳過的站不畫**（乘客沒出現、司機不會再去，畫了會誤導路線；
            清單仍以刪除線保留紀錄）；已到達的站不入折線（避免看起來走回頭路）。
            單點訂單走原本的單一目標模式，畫面不變。純函式
            （visibleRouteStops／nextPendingStop／routePolylinePoints）有單元測試。
      - [x] **取消原因 UI 呈現**（P4）✅ 2026-07-17：叫車表單頂部取消通知卡——
            文案由 `cancelMessage()`（機器可讀 code）產生；`no_vehicle_of_type`
            時多給「改用不指定車種」快捷（一鍵把車種改回不指定＋收起通知），
            其他情況只陳述事實＋「知道了」。**reason 為 null 也要通知**
            （乘客主動取消／司機放棄走泛用文案），故 controller 加獨立
            `_rideCancelled` 旗標，不能只看 cancelReason。
            新叫車／登出時清空；反向確認拿掉旗標會讓測試 FAIL。

## ✅ O5：admin 車輛審核（2026-07-19 拍板並完成，三端）

> 使用者 2026-07-19 拍板「O5 先做」。O3 gate（**有填**車種車牌）已升級為
> O5 gate（**已審核**）；三個 repo 同批上線，契約一致。

- **後端**（dispatch PR #40）：migration 000022 加 `vehicle_review_status`／`note`＋CHECK；
  `VehicleApproved()` 取代 `HasVehicle()` 當 gate（派單側＋接單側）；接單側分
  `ErrDriverNoVehicle`（沒填）與 `ErrDriverNotApproved`（待審核），司機知道下一步；
  `UpdateVehicle` **原子地**把 review 重置 pending（改車一律重審）；
  admin `POST /drivers/:id/vehicle-review`（ops 角色，只有 pending 可審、退回必附原因）；
  司機 `GET /driver/vehicle` 加 `review_status`／`review_note`／`can_accept`。
- **司機 App**（fleet-app PR #35）：`_DriverRoot` 三態→**四態**——未填→強制設定頁、
  pending→審核中等待頁、rejected→已退回（顯示原因＋重填重送審）、approved→首頁。
  `DriverVehicle` 加 `reviewStatus`／`reviewNote`／`canAccept`（**以後端 `can_accept` 為準**，
  App 不自行推導）；未知狀態→`none`、舊後端無 `can_accept` 時退回 `has_vehicle`（不誤鎖）。
- **Admin**（fleet-frontEnd PR #20）：司機管理頁加車輛欄（車種＋等寬車牌）、審核狀態 tag
  （退回 tooltip 帶原因）、待審核列的核准／退回（退回開 modal 填原因）；
  「N 台車輛待審核」快捷 tag＋篩選；搜尋含車牌。

**導入決策（一句 SQL 可改）**：既有已填車輛的司機**祖父化為 approved**，不因導入審核被鎖出；
新填／改動才進 pending。若要全體重審，改 migration 000022 的那行 UPDATE 即可。

**驗收**：三端各自 build/lint/test 綠（dispatch go test、app flutter test 169、admin vitest 110）；
**模擬器四態全走通**（未填→設定頁→填車→審核中→退回顯示原因→重送→核准→首頁）；
**admin 瀏覽器 E2E**（核准／退回附原因皆與後端一致）；
**後端 runtime 全鏈路**（待審核接單被擋「車輛審核中」→核准後接單成功）。

## ☎️ 司機聯絡電話填寫入口（2026-07-22）

> 盤點三端程式碼（不只看勾選）時發現的洞：**O7 拍板的「乘客可直接撥打司機電話」實質從未生效**。
> `drivers.phone` 欄位一直都在，乘客端 `DriverVehicleCard` 的 `tel:` 按鈕也早就寫好，
> 但**後端沒有任何寫入 phone 的路徑**——註冊不收、車輛端點也不收，只能手動改 DB。
> 所以每個司機的 phone 都是空字串，而「無車輛資訊時整塊不顯示」的規則讓撥號按鈕永遠不出現：
> 一個看起來三端都做完的功能，實際上一次都沒運作過。

- [x] **司機端設定頁加「聯絡電話」**（詳見下方「司機車輛資訊 → 司機端」條目）。
      後端同批新增 `PUT /api/driver/profile`（dispatch Q3），與車輛端點分開以免改電話重置 O5 審核；
      `GET /driver/vehicle` 順帶回 `phone` 供設定頁預填。
- [x] **模擬器實跑全鏈路 ✅（2026-07-22，`m6_pixel` 雙 flavor ＋ docker compose 三服務）**：
      司機端 App 註冊 → 車輛資訊頁填「轎車／SIM-7788／0912-345-678」→ 儲存（後端 `drivers.phone`
      實際寫入 `0912345678`，正規化生效）→ admin 核准 → 上線 → 乘客端叫車 → 司機接單 →
      **乘客端出現「撥打 0912345678」＋車牌 SIM-7788**，點下去 Android 撥號盤開啟並預填該號碼
      （`topResumedActivity=com.google.android.dialer`）。O7 的撥號功能**第一次真的運作**。
      重開司機端設定頁也確認電話預填 `0912345678`（`GET /driver/vehicle` 的 phone 回填）。
- [x] **後端 live E2E 22/22 綠**（同一批 docker compose，`scripts/` 之外的一次性腳本）：
      起始 phone 為空 → 無效號碼 400 → 填號碼正規化 → 設定頁回填 → **改電話不重置 O5 審核**
      （仍 approved／can_accept）→ WS `ride.accepted` 帶 `driver_phone` → REST 訂單詳情也帶 →
      他人查該單 403 → **負向對照：沒填電話的司機，WS 與 REST 都不帶 `driver_phone`**。
- [x] **實跑抓到並修掉的洞：乘客端只靠 WS 事件拿司機電話** 🐛（同日修，本 PR）。
      `ride.accepted` **只送一次**——app 在背景被接單、WS 重連、或重開 app 都收不到它。
      修正前 `CustomerRide` 沒有任何 driver 欄位、`_applyActiveRide` 也從不回填 `_driverInfo`，
      所以錯過事件＝撥號按鈕與車牌永遠不出現，**即使後端 `GET /customer/rides/active`
      一直都帶著 `driver_name`／`driver_phone`／車牌**（App 端註解「GET active 不含司機名」是過時的，已改）。
      這是模擬器實跑才會踩到的：切去司機端接單、再切回乘客端，畫面就只剩「司機前往中」。
      **修法**：`CustomerRide.driver`（鍵名與 WS payload 相同，共用 `RideDriverInfo` 解析）＋
      `_applyActiveRide` 在 status ≥ accepted 時 `??=` 回填（WS 值優先，不被輪詢覆蓋）。
      **驗證**：同一台裝置、同一張 ride #18、同樣冷啟動，修前只有「司機前往中」、
      修後顯示司機／車牌／「撥打 0912345678」；新增 5 個回歸測試，`flutter test` 188 passed。
- [x] **查清並修掉「按叫車沒有任何回饋」** 🐛（2026-07-22 追查，本 PR）。
      起因是實跑第一次叫車完全沒反應。**機制**：production 首頁是地圖版 `CustomerMapHomeScreen`，
      而它**從不讀取 `ctrl.error`**——舊的卡片版 `CustomerHomeScreen` 本來有 `_maybeShowErrorSnackBar`，
      換成地圖版時這個顯示掉了。於是 `placeOrder` 的**每一種**失敗都是靜默的：
      定位權限被拒、定位取不到、建單 API 失敗（token 失效／後端離線都算）。
      **兩條路徑都實跑重現**：①拒絕定位權限 → 畫面回原樣、後端零請求；
      ②停掉後端容器 → busy 轉幾秒後回原樣，什麼都沒說。
      **修法**：`CustomerMapHomeScreen` 加 `_maybeShowError`（postFrame 顯示 SnackBar），
      controller 加 `clearError()`——**顯示後要清掉**，否則畫面層的「和上次一樣就不重複顯示」
      去重邏輯會把第二次同樣的失敗吃掉，使用者再按一次又變成沒有回饋。
      **驗證**：修後同樣兩條路徑分別顯示「需要定位權限才能叫車」與「無法連線到伺服器，請檢查網路」；
      新增 2 個 widget 測試（含「同一錯誤第二次仍會提示」），`flutter test` 190 passed。
      **追查過程的教訓**：第一次驗收截圖沒看到 SnackBar，差點誤判修復無效——
      其實只是 SnackBar 出現在按下後約 4.5 秒、只顯示 4 秒，截圖時機錯過。
      靠暫時的 `debugPrint` 對照 logcat 才確認 error 有被設、顯示分支有走到（診斷碼已移除）。

## 🚧 刻意沒做（2026-07-22 盤點後決定不動）

> 不是忘了，是**現在做的價值低於代價**；每項都寫明「什麼條件成立才該做」。

- **訂單列表的多乘客標記**：admin／司機清單看不出哪些是多乘客行程。
  後端資料有（`stops`），純粹是清單沒標。**等實際有人抱怨看不出來再做**——
  現階段多乘客訂單量少，加欄位反而讓清單更擠。
- **車種供給為零時的選項處理**（下方 P 風險 2 也有記）：需要後端先提供「目前可用車種」查詢，
  **且要先想清楚產品要的是停用、隱藏、還是照選但提示可能配不到**。等產品定方向。
- **admin 代司機改車牌**（可選）：目前車牌只能司機自己改（改完回 pending 等審核）。
  代改要處理「代改要不要重審」「誰負責填錯的責任」，**在有客服實際卡住的案例前不做**。
- ~~**車資預估報價 API**~~ ✅ 已做（2026-07-23，見下方「💰 建單前車資預估」）。

## 🔮 懸而未決（需產品拍板）

> **等使用者拍板，未拍板前不要做**（2026-07-19 使用者：其他等我拍板）。

1. [x] **N 的衍生風險：乘客看不到預估車資 ✅ 已解（2026-07-23，拍板投資報價 API）**
   N5 拍板「車資＝全程實際路線（含繞路）」＋ 多停靠點 → **繞路越多車資越高**，
   舊狀況乘客建單時**完全看不到預估**（後端只在完成時定格計費，沒有報價 API）。
   **決策：投資一支報價 API**（非「先搭後知價」）。詳見下方「💰 建單前車資預估」段。

---

## 💰 建單前車資預估（懸而未決 #1，2026-07-23）

> 拍板投資報價 API：乘客在**建單前**就看到預估車資，不必到行程結束才知道多少錢。
> 多停靠點行程放大了「先搭後知價」的痛點（排一堆繞路卻看不到金額），這是本題的主因。
> **是預估不是定價**——後端仍於行程完成時依**實際行駛路線**定格計費，兩者可能不同。

**後端**（dispatch，分支 `claude/quote-fare-estimate-api`）：
- 新 `POST /api/customer/rides/estimate`（customer JWT，純唯讀、不建單、不寫 DB）。
- `service.EstimateService`：以全程規劃路線（起點 → 各停靠點 → 終點，**含繞路**）算里程，
  與完成計費**共用同一份 `FeeSettings.Quote`**——預估與實收落在同一套費率規則，
  差異只來自「規劃路線 vs 實際行駛路線」。距離走 `RouteVia`（與 N5 計費同一支多點 API），
  OSRM 掛掉時內部退回逐段 haversine，故**預估永遠算得出一個數**（近似），不會卡住乘客。
- 輸入形狀與建單相同（沿用 `validateStops`／座標驗證），**目的地座標必填**（沒終點無法路由）；
  車種選填（寵物車含清潔費）。回傳白名單欄位：`fare_cents`／`cleaning_fee_cents`／`total_cents`／
  `distance_m`／`duration_sec`——**不回手續費／實得等內部費率**（比照 `CustomerJSON`）。
- 測試：service 8 案（單點／多停靠點全程入路線／寵物清潔費／缺目的地 400／非法車種／
  min_fare 下限／未成對停靠點／未就緒）＋ handler 2 案（授權 401/403、綁定 400、未就緒 503）。

**App**（fleet-app，本分支）：
- `FareEstimate` 模型 ＋ `CustomerApiClient.estimateFare`；`CustomerController` 加預估狀態，
  **地圖選點目的地時**（單點）或**停靠點填完時**（多停靠點）自動算，**車種變更時重算**
  （寵物車加清潔費要即時反映）。dropoff 座標存在 controller 才能在車種變更時重算。
- 叫車表單顯示 `_FareEstimateCard`：有清潔費時拆「車資 ＋ 寵物車清潔費 ＝ 預估合計」，
  否則單一預估金額；附「約 X 公里・Y 分鐘」與**「實際車資依行駛路線可能不同，於行程結束時結算」**。
- **失敗一律靜默清空**——預估只是輔助資訊，不擋叫車、不彈錯誤（與 P5 查費率同一原則）；
  單點模式需要上車 GPS（優先用已取得的定位，8 秒逾時），多停靠點由 stops 推導不需 GPS。
- 測試：`customer_fare_estimate_test` 7 案（多停靠點帶 stops 不需 GPS／車種變更重算含清潔費／
  失敗靜默／clearEstimate／移除乘客清空／模型解析）；`flutter analyze` 無 issue、`flutter test` 197 passed。

**驗收**：三端（此處為兩端）各自 build/lint/test 綠——dispatch service+handler 單元測試綠、
app `flutter test` 197 passed。

**✅ 模擬器實跑 E2E 對帳（2026-07-23，`m6_pixel` ＋ 後端 quote-api worktree 本機起服務）**：
- **App UI 實跑**：地圖選目的地 → 叫車表單出現「預估車資」卡（**預估合計 NT$221・約 6.8 公里・
  10 分鐘**＋「實際車資依行駛路線可能不同，於行程結束時結算」免責文案）；GPS 上車點以模擬器
  `geo fix` 帶入，目的地由地圖選點（`geocoding` 反查）→ `setEstimateDropoff` 觸發預估。
- **完整鏈路對帳**：App 叫車建 ride #24（429m）→ 司機 API 接單→上車→完成（不補軌跡）→
  **App 完成卡顯示「車資 NT$94」**，與同座標 estimate 回的預估 **NT$94（9400 分）完全一致**。
- **API 層對帳（決定性，同一後端）**：預估與完成共用 `FeeSettings.Quote`＋同一 OSRM 路線 →
  單點（6811m）預估 fare 22100 ＝ 完成實收 22100；**寵物車**（清潔費率設 20%）預估
  fare 22100＋清潔費 4400 ＝ 完成實收 22100＋4400（**車資與清潔費皆一致**）。
- 結論：不繞路時**實收＝預估**（同路線同費率）；繞路時走 N5 既有 `max(軌跡, 路線)` 邏輯，
  故免責文案「實際依行駛路線可能不同」成立。

---

## ⭐ 乘客評分司機（B5，2026-07-27）

> 盤點後的事實：TODO 上**沒有任何不需外部資源就能做的純 App 項目**了
> （A2 卡 Firebase 專案、A5 階段 5–6 卡實機／付費 Apple 帳號、車種供給為零卡產品拍板）。
> 唯一還印著「即將開放」的出貨畫面是完成卡的評分按鈕——B5 從 2026-07-08 佔位至今，
> 註記「真實 API 待 Phase C」。後端當時確實沒有評分資料表與端點
> （`grep -i rating` 全 repo 零命中），本批兩端一起補齊。**付款不在本批**（需真金流）。

**後端**（dispatch，分支 `claude/b5-ride-rating`，詳見 dispatch TODO「S. 乘客評分司機」）：
- migration 000023 `ride_ratings`；**一趟一評、不可重評**（唯一索引）。
- `POST /api/customer/rides/:id/rating`（customer JWT）：非本人 403、不存在 404、
  **已評過／未完成 409**（狀態衝突不是輸入錯，App 據此知道不必請乘客改參數重送）。
- 讀回三處：`CustomerRideView.rating`、歷史列 `rating_score`、`GET /driver/me` 的
  `rating_avg`／`rating_count`。

**App**（本分支）：
- `RideRating` 模型 ＋ `CustomerApiClient.rateRide`；`CustomerRideSummary` 加
  `ratingScore`／`isRated`／`canRate`（**已完成 ＋ 有司機 ＋ 未評**，與後端同一組條件）。
- 共用 `lib/customer/widgets/rating_sheet.dart`：1–5 星必選、評論選填（200 字，與後端上限對齊）。
  **失敗時對話框不關**——分數沒送出去就把畫面收掉，乘客會以為評好了；錯誤留在原地，
  重試不必重選星等。
- **完成卡**：「留下評分（即將開放）」的 disabled 佔位換成可按的「留下評分」，
  送出後只剩星等＋「已評分」（後端一趟一評，沒有改評分）。
- **歷史清單**（`CustomerRideHistoryScreen`）：未評的完成行程給「評分」、已評顯示星等。
  **這是完成卡關掉後唯一的補評路徑**——`dismissCompleted()` 之後摘要就沒了，
  沒有這條路徑，錯過當下就永遠評不了。
- **司機收入頁**加「服務評價 4.5 ／ 5.0（12 則）」：沒有這塊，評分就是寫進去沒人看得到的資料。
  查失敗或尚無評分**整塊不顯示**，不擋收入頁（收入才是那頁的主體）。
- **controller `submitRating` 回錯誤字串而不寫 `_error`**：評分是對話框裡的動作，
  錯誤要留在對話框上；丟到全域 error 會變成關掉對話框才看到的 SnackBar。
  成功時就地 `copyWith` 更新歷史那一列，不重打 API（避免對話框關閉時整份清單閃一下）。
- **星等狀態綁 rideId**（`_completedRatingRideId`）：`_completedSummary` 有六處會被重設
  （登出、再叫一輛、新訂單、下一次 `ride.completed`…），只存分數就得在每一處記得清掉它，
  漏一處就會讓下一趟的完成卡一出現就顯示上一趟的星星。**反向確認**：拿掉這個綁定，
  「換一趟完成卡不會顯示上一趟星等」該案 FAIL。

**驗收**：
- 靜態：`flutter analyze` 無 issue、`flutter test` **216 passed**（原 204＋新 12）。
  新增 `test/customer_rating_test.dart` 9 案（模型解析／`canRate` 三條件／送出成功含清單就地更新／
  失敗不寫全域 error／未登入不打 API／星等綁 rideId／完成卡按鈕不再 disabled／歷史清單兩態）
  ＋ `driver_earnings_widget_test.dart` 3 案（有評分／尚無評分不顯示 0.0／查詢失敗不擋收入頁）。
  既有 `widget_test.dart` 的 B5 佔位斷言同步改成「評分入口可按、佔位文案消失」。
- 後端：`go build`／`go vet`／`gofmt` 乾淨；service 3 案（真 PostGIS 跑全部 migration，
  順帶驗證 000023 可套用）＋ handler 2 案（HTTP 邊界，不需 DB）。
- **✅ 模擬器實跑 E2E（2026-07-27，`m6_pixel` 雙 flavor ＋ dispatch docker compose，全程截圖）**：
  - **完成卡**：ride #26 完成 → 車資 NT$ 85 →「留下評分」是**可按的實心按鈕**
    （不再是 disabled 佔位，`即將開放` 文案已不存在）→ 開 sheet：5 顆空星、
    「想說的話（選填）」0/200、**未選星等時「送出評分」是 disabled**。
  - 選 4 星＋評論 `GreatDriver-B5` → 送出 → **DB 交叉驗證** `ride_ratings` 寫入
    `(ride 26, customer 8, driver 24, score 4, comment)` → 完成卡當場翻成
    **★★★★☆「已評分」**、評分按鈕消失。
  - **補評路徑**（本功能最關鍵的一條）：第二趟 ride #27 完成後按「再叫一輛」關掉完成卡 →
    進「我的行程」→ #27 顯示綠色「評分」鈕 → 給 5 星、**不留言** → 送出 →
    **清單那一列就地翻成 ★★★★★「已評分」**（沒有重打 API）；DB 的 comment 為空字串。
  - **`canRate` 三條件在真實資料上一次驗完**：#26/#27（已完成＋有司機）給入口；
    #25（已取消、無司機）**兩個入口都沒有**；#12（已取消但有司機）只有「聯絡司機」、
    **沒有評分鈕**。
  - **司機端**：`b5drv01` 登入（已核准 → 直接進首頁，O5 四態正確）→「我的收入」顯示
    **「服務評價 4.5 ／ 5.0（2 則）」**——與 `GET /driver/me` 的 `rating_avg=4.5`／
    `rating_count=2` 及 DB 的 (4+5)/2 **三處完全一致**。
  - **守門實打**（直打 API，App 已不給入口）：重複評分 **409** 且原分數未被覆寫、
    星等 6 → **400**、他人訂單 → **403**、已取消行程 → **409**。
  - 🐛 **實跑抓到一個真 bug（已修，dispatch PR #46）**：未完成行程的 409 文案是
    **「僅已完成的行程可申請遺失物協尋」**——後端 `RateByCustomer` 重用了遺失物的
    `ErrRideNotCompleted`，而這段訊息會**原樣顯示在乘客的評分對話框上**。
    單元測試斷言的是 `errors.Is(...)` 而非文案內容，所以測不到。
    已改用專屬的 `ErrRideNotRatable`，並補上「訊息不得提到遺失物」的斷言。
  - 收尾：模擬器、docker compose、位置心跳全數關閉。

**✅ 下游補完：admin 評分可見性（2026-07-27）**——評分原本**只有司機自己看得到**，
admin 端 `grep -i rating` 零命中，營運方對爛司機完全無感。
後端 dispatch PR #47（`GET /admin/drivers` 的 `rating_avg`／`rating_count`、
`GET /admin/rides/:id` 的 `rating`）＋ admin PR #22（司機管理頁「評價」欄可排序、
訂單詳情「乘客評分」卡）。至此 B5 三端齊備：**乘客評 → 司機看得到自己的平均分 →
營運看得出誰評價低**。

---

## 🔐 登入頁 UI/UX 翻新＋驗證（2026-07-23）

> 盤點發現：登入／註冊頁是**全 App 唯一沒吃到 2026-07-10 UI/UX 翻新的畫面**，
> 還留著開發期痕跡。先釐清事實：這是**真實帳密登入**（`POST /driver/login`／`/customer/login`
> 帶 `line_user_id`＋`password`），不是 LINE OAuth stub，所以是會出貨的正式畫面。
> 司機端與乘客端兩頁先前是 95% 重複的手抄，且**完全沒有任何測試**。

**修掉的問題**：
- **硬編測試帳密**（`sim-driver-001`／`password123`）預填在會出貨的畫面；
- **後端 URL** (`後端：http://…`) 直接印在登入頁；
- 沒有密碼顯示切換；錯誤只是一行紅字；無空欄位驗證。

**改了什麼**：
- 抽出共用 `lib/shared/widgets/auth_scaffold.dart`（controller-agnostic，登入邏輯由
  `onLogin`／`onRegister` callback 注入）；`driver_login_screen`／`customer_login_screen`
  收斂成薄包裝（各約 25 行，只差圖示／標題／文案）。
- **開發便利收進 `kDebugMode`**：預填測試帳密與後端 URL 顯示**只在 debug build 出現**，
  release build 一律留空、不顯示後端——**模擬器 E2E 仍保有預填**（本專案高頻使用，不可拿掉）。
- 新增：密碼顯示切換（eye toggle）、`Form` 空欄位驗證（LINE ID／姓名／密碼各自擋空並提示）、
  品牌圓形圖示 header（`primaryContainer`）、樣式化錯誤橫幅（`errorContainer`＋icon，取代紅字）、
  送出中 spinner、大螢幕置中限寬（440）、欄位 prefix icon（badge／person／lock）。
- 補上登入頁**第一份測試** `test/auth_scaffold_test.dart`（7 案：空欄擋下不呼叫 onLogin／
  trim 後帶值登入／註冊模式出現姓名欄／密碼切換 obscureText／錯誤橫幅／loading disabled＋spinner／
  debug 預填），全用真實 `appLightTheme` render。

**驗收**：
- 靜態：`flutter analyze` 無 issue、`flutter test` **204 passed**（原 197＋新 7）。
- **視覺實跑 ✅（2026-07-23，macOS driver flavor，`flutter run -d macos`，系統深色模式，截圖）**：
  登入頁 render 正確——品牌綠圓形計程車圖示、`badge`／`lock` 前綴圖示、密碼遮罩＋右側顯示切換、
  綠色「登入」鈕、「新司機？註冊」切換、底部 debug-only 後端 URL、置中限寬版面成立。
  FCM 如預期降級（macOS 無 Firebase 設定 →「可略過，仍可用 WS」NoOp 路徑生效）。
  （選 macOS 目標因登入頁在任何網路呼叫前即 render，不需起後端 docker 即可驗視覺。）
- **Android 模擬器登入／註冊真鏈路 ✅（2026-07-23，`m6_pixel` ＋ dispatch docker compose，雙 flavor 截圖）**：
  - **司機註冊**：切註冊模式（姓名欄出現）→ 填全新 `simdrvverify01` → 送出 → 越過登入進 O5 車輛 gate；
    **後端 DB 交叉驗證**：`drivers` 新增 id=23、`line_user_id=simdrvverify01`、name=測試司機（尚無車輛，對應 gate）。
  - **司機登入**（`pm clear` 清 session 後的全新 login POST，非還原）：`simdrvverify01`/`password123`
    → 登入成功落在車輛 gate。清 session 後正確回登入頁（非自動登入）。
  - **錯誤密碼負向**：不存在帳號送出 → **真 401 觸發樣式化錯誤橫幅**（粉紅 `errorContainer`＋
    `error_outline`＋中文「帳號或密碼錯誤」，`api_error` 分類端到端生效）。
  - **乘客登入**：build+install customer flavor（原裝置是舊版 APK，先前顯示舊登入頁——**證明兩 flavor
    須各自 build`-t lib/main_customer.dart`**）→ 新 AuthScaffold render 正確 → `sim-customer-001` 登入成功
    進乘客首頁（還原進行中行程）。證明 `CustomerController` wiring 正常。
  - **乘客註冊**：切註冊模式（姓名欄出現）→ 填全新 `simcustverify01` → 送出 → 進乘客叫車首頁（乾淨狀態，
    新帳號無進行中行程）。**後端 DB 交叉驗證**：`customers` 新增 id=20、`line_user_id=simcustverify01`、
    name=測試乘客。→ 表單→`POST /customer/register`→建列→token→session→首頁整條成立。
  - Light／Dark 兩主題皆驗（Android 亮色 ＋ macOS 深色）；debug 預填與後端 URL 僅在 debug build 顯示成立。
  - **一個 snapshot 坑**：以 `-no-snapshot-save` 開模擬器時，reboot 會載入舊 snapshot、把上一個 boot
    `flutter run` 裝的新 APK 丟掉（第二輪乘客又變回舊登入頁才發現）；同一 boot 內重跑 `flutter run` 即可。
  - 收尾：模擬器、docker compose、flutter run 全數關閉。

---

## 🧹 清開發殘留 worktree／舊分支（維護項 5，2026-07-28 完成）

> 三個 repo 累積的殘留：**76 條本地分支、18 個 worktree**。
> 這項的重點不是刪，而是**刪之前逐條證明內容真的在 main**——
> 前兩批「救回」（app PR #48、dispatch PR #49）就是因為有人把未合併的分支當成已合併。

**判定方法**（不靠 commit message、不靠「PR 看起來合併了」）：
1. `git merge-base --is-ancestor <branch> main` → 是 ancestor 就安全。
2. 非 ancestor 者查對應 PR，**MERGED 還要再比對 `headRefOid`**——
   squash merge 後本地 tip 可能又有新 commit，PR 頁面不會告訴你。
   全 40 條 MERGED 分支的本地 tip **都等於合併時的 tip**（無漏網）。
3. 剩下的例外逐條看 diff：**只有 4 條**不是「已合併且 tip 相同」。

**4 條例外的判定**：

| 分支 | 判定 | 依據 |
|---|---|---|
| app `claude/todo-review-priority-54ffe7`（PR #40 CLOSED） | 已救回 | 整合測試＋`tool/watch_driver_location.sh` 在 PR #48、功能碼在 PR #41 |
| app `claude/project-planning-docs-803c8e`（PR #37 CLOSED） | 已被取代 | 純文件；T1 車資預估已完成、T2/T3 仍列在下方、T5-2 評分已上線 |
| dispatch `claude/driver-phone-profile`（PR #42 CLOSED） | 已被取代 | 那份 service 測試的每一條都被 main 的 `handler/driver_profile_test.go`（真 DB）覆蓋，含「改電話不重置 O5 審核」；且**「空字串＝清除電話」在 main 已改成 400 拒絕**，原測拿到 main 反而會 FAIL |
| dispatch `claude/determined-shannon-17f4ac`（**從未開 PR**） | 🐛 有漏 → 已救回 | 功能碼（`PickUpResult`／`dropoff_lat`／tracking ETA）都在 main，但帶著一份 main 沒有的 `ride_dropoff_integration_test.go` |

- [x] **救回 dropoff repository 測試**（dispatch PR #50）：原檔測的 `GetDropoffCoords`
      在 main 已不存在，故改寫成對現有 API（`Create` → `GetByID`）的等價覆蓋。
      關鍵是**「未指定目的地 → `DropoffPoint` 必須是 nil」這條 main 完全沒有**——
      守的是踩過的 `GeoPoint.Scan` 坑：NULL 被當成掃描成功而留下 `(0,0)`，
      導航與計費會把幾內亞灣外海當真目的地且**不報錯**。
      負向斷言的取值路徑由同檔正向案例校準（同一個 `GetByID → DropoffPoint`），
      不會永遠 PASS。真 PostGIS（testcontainers）實跑 **2/2 PASS**、gofmt／go vet 乾淨。
- [x] **清除**（三端數字皆為實測 `git worktree list`／`git branch -a`）：
      本地分支 **76 → 5**（app 55→2、admin 2→1、dispatch 19→2）、
      worktree **18 → 3**（僅留兩個進行中的工作區）、
      remote 舊分支 **17 → 0**（app 7、dispatch 10；使用者 2026-07-28 同意含 4 條未合併的一併刪，
      GitHub 的 PR 頁面仍看得到 diff）。admin 端本來就乾淨。

---

## 🗄️ 清 dev DB 測試殘留（維護項 6，2026-07-28 完成）

> ⚠️ **先更正原本這條待辦寫錯的機制**：舊敘述說「十幾個殘留的『線上』司機**擋在派單佇列前**」。
> 讀 `dispatchRound` → `Store.NearbyDriverIDs` 後確認**跨 session 不成立**：
> 派單候選**只從 Redis 的 `drivers:geo` 取**，且每個候選還要 `driver:<id>:loc`
> 的 `updated_at` 在心跳鮮度內才算數。compose 的 redis **沒有掛 volume**，
> `docker compose down` 之後派單池是空的（實測 `dbsize` 0、`zcard drivers:geo` 0）。
> 所以 Postgres 裡的 `status=1` 殘留**本身不會**吃掉派單輪次；
> 2026-07-27 那次白跑，是**同一個 session 內**那些司機還在送位置心跳造成的。

**盤點到的真正的坑**（這個才會咬下一次的自己）：
`GoOnline` 對 `status=OnTrip` 的司機**直接 return、不改狀態**，`GoOffline` 則回
`ErrDriverOnTrip`。上次留下 **3 個卡在「載客中」的司機**（id 4 `o5-driver`、11、13）——
下次重用這些帳號時，**App 會顯示上線成功，但派單要求 `Idle` 所以永遠收不到單，也無法離線**，
沒有任何錯誤訊息。另有 **4 張未結案訂單**（#7 已派單但無司機、#11／#14／#16 已接單）
讓 customer 3／6／9／11 一律拿到「已有進行中訂單」。

**清理前的盤點**（只讀）：drivers 24（19 待命／3 卡載客中／2 離線）、customers 20、
rides 27（13 完成／10 取消／**4 未結案**）、ride_events 108、ride_stops 12、
ride_ratings 2、ride_messages 1、daily_driver_earnings 11、device_tokens 1。

- [x] **做法：整個砍掉重練**（使用者 2026-07-28 拍板；`ask-before-db-writes` 已遵守，
      盤點先只讀、把選項與代價列出後才動手）。`docker compose down -v` 刪掉
      `line-fleet-dispatch_postgis_data`。**動手前先核對過不會損失任何設定**：
      `fleet_settings` 的每個值都等於 migration 預設（8500／2000／8500／1500／300000／
      lost_item_fee_bps 1000／pet_cleaning_fee_bps 0），admin 帳號由 app 啟動時重種。
- [x] **驗證重建後仍是可用的 dev DB**（不只是刪掉）：`docker compose up -d` →
      migration 自動跑到 **000023**、admins 重種 1 筆（`admin`／superadmin）、
      `fleet_settings` 1 筆回到預設值，其餘業務表**全部 0 筆**；
      `POST /api/admin/login`（admin／admin）**200 並取得 token**、
      未帶 token 的 `GET /api/customer/fees` 正確回 **401**。
- [x] **順手清掉兩個孤兒 volume**（使用者同意）：`customer-ride-stops_postgis_data`／
      `driver-phone_postgis_data`，各 114MB、`LINKS=0`，是維護項 5 刪掉的 worktree 留下的。
      共釋出 **228MB**。

**下次做 E2E 前的提醒**：這個 DB 現在是全新的，所以**沒有任何測試帳號**——
司機／乘客都要重新註冊，司機還要走 O5 車輛審核（admin 核准）才能接單。
若又要收尾，離開前把 `status=OnTrip` 的司機與未結案訂單處理掉，
否則下一次又會踩上面那個「上線成功卻收不到單」的無聲坑。

---

## 🐞 2026-07-28 debug：4 個 bug ＋ 跨端契約對帳

### 修掉的 4 個（每個都先寫測試看它 FAIL 才修）

前三個是**同一家族**：使用者沒按任何東西的背景動作，汙染了使用者的錯誤出口，
或反過來把使用者真正需要看的訊息洗掉（app PR #52）。

1. **司機端定位探針洗掉業務錯誤**：`_reportPosition` 成功時清掉**所有**錯誤
   （理由是「探針成功＝後端可達」），但它 8 秒跑一次。司機按「完成行程」被 409 擋下時，
   那句唯一的回饋幾秒內就被無聲抹掉。**修法**：只清連線類
   （`ApiException.statusCode == null` ＝根本沒收到 HTTP 回應），4xx/5xx 必須留著；
   error 指派全部收斂到 `_setError`／`_setApiError` 才記得住這個分類。
2. **乘客端背景輪詢失敗彈 SnackBar**：15 秒一次，後端一斷線就每 15 秒蓋住 sheet 上的按鈕，
   使用者沒按過任何東西也無法讓它停。**修法**：`refreshActive({silent})`——
   輪詢與 WS 觸發的刷新靜默，使用者主動觸發的維持照舊回報。
3. **FCM token 輪替失敗冒紅色橫幅**：推播是可降級的輔助管道（README 明載「可略過，仍可用 WS」）。
   登入路徑剛好被後續的 `_setError(null)` 蓋掉，**token 輪替那條沒有任何保護**。
   ⚠️ 修了 (1) 之後這條橫幅不再被探針清掉，所以 (1) 讓 (3) 變得更必須修。
4. **司機放棄訂單時 App 乘客收不到任何事件**（dispatch PR #52 ＋ app PR #53）：
   後端**寫好了**文案「司機取消了行程，正在為您重新派車」，卻只走 `line.PushText`。
   App 乘客的司機卡片（含車牌與撥號按鈕）停在畫面上，直到最多 15 秒後的輪詢才無聲退回
   「配對中」——期間可能打給一個已經不來的司機。**修法**：補送 `ride.redispatched`
   （型別本來就定義好，先前只用於 audit）；**刻意不用 `ride.cancelled`**——
   行程沒取消只是回到派單中，送它會讓 App 清掉整筆訂單。
   App 端接住後清乾淨上一位司機的所有痕跡，並在配對中畫面顯示說明。

### 跨端契約對帳：**這些已驗過是乾淨的，下次不必重做**

方法：起真實後端，WS 同時掛上司機與乘客跑完整鏈路，抓**後端實際送出的 payload**
逐欄比對 App 的解析程式碼——不是讀程式碼猜。以下全部查證通過：

| 檢查 | 結果 |
|---|---|
| 13 個 WS 事件型別是否有 App 沒處理的 | 無漏接（`ride.requested`／`ride.redispatched` 當時只是 audit 型別） |
| 停靠點 8 個鍵（含 `arrived_at`／`skipped_at` 只在發生時才帶） | 完全對齊 |
| `cancel_reason` 機器可讀 code | 實跑驗到 `no_driver_available` 與 `no_vehicle_of_type`＋`required_vehicle_type`，兩端一致 |
| REST 巢狀 `pickup_point` vs WS 扁平 `pickup_lat` | App 兩種都解析 |
| 建單回 `ride_id`、其他端點回 `id`／`ID` | App 三種都接 |
| `rating_avg` 實際回**整數** `4`（Go 的 float64 4.0） | App 用 `as num?`，不會 TypeError |
| REST 帶 `cleaning_fee_cents: 0`（非缺鍵） | App 用 `> 0` 判斷，不會多顯示一行 NT$0 |
| App 讀的所有 JSON 鍵 vs 後端送出的所有鍵（集合差集） | 無「App 期待但後端不送」的鍵 |
| 乘客 REST 還原是否帶 `stops`／`rating` | `customerRideView` 兩者都帶（WS-only 的坑已補） |

**同時推翻的後端假設**（沒有 bug，不硬報）：`SetDriverEnabled` 已擋「載客中不可停用」、
`AcceptRide` 會再驗一次 `Status != Idle`、取消時 `releaseAndReset` 會把司機放回待命、
admin 的全域 query 錯誤處理有去重 key 且整個 repo 沒有 `refetchInterval`。

**下次要重跑對帳**：dev DB 是空的，腳本要重建帳號（司機還要走 O5 審核才能接單）。
腳本邏輯：註冊司機／乘客 → admin 核准車輛 → 上線＋回報位置 → 雙方連 `ws://…/ws?token=`
→ 叫車 → 接單 → 上車 → 完成 → 評分，全程把 REST 與 WS 的原始 payload 印出來比對。
**沒覆蓋到的**：~~遺失物協尋鏈路、admin 端的 REST 形狀~~ → **兩者都已於同日補完**（見下兩段）。

---

## 🔎 2026-07-28 第二輪 debug：協尋鏈路、admin REST、模擬器 UI

### 遺失物協尋鏈路（app PR #55）

**抓到 1 個 bug**：**production 首頁（地圖版）完全沒有協尋入口**——持久性 banner 只寫在
卡片版首頁裡，換版時掉了。唯一剩下的入口是完成卡，而它按「再叫一輛」或重開 App 就消失。
後果：乘客建了協尋單、司機標記「已尋獲」後，**必須付處理費才能拿回東西，卻沒有畫面進得去付**。
2026-07-15 的 E2E 之所以「驗過」，是因為當時本機無 Maps key 走的是**卡片版**。
修法：抽成共用 `LostItemBanner` 兩版共用（根因是各抄一份），掛在 sheet 最上方且不受行程狀態影響。

**其餘驗過乾淨**：`open→found→paid→returned` 四段狀態機、雙方 WS 事件、5 個狀態常數兩端一致、
「未結案」集合兩端一致（open/found/paid）、終態後雙方清單自動清空、司機角標由清單長度推導、
守門回應（404／409／403）皆有中文訊息。
處理費 2100 分一度看似算錯（20600×10%＝2060），查證是 `roundNtd` 把 NT$20.6 進位成
**NT$21**，符合整數台幣政策——**不是 bug**。

### admin 端 REST 形狀（admin PR #28）

**沒有 active bug**。揪出一個**型別謊言**：`PATCH /admin/drivers/:id/status` 實際回混合大小寫
且不含評價欄，前端卻宣告回 `Driver` 又不正規化——車輛三欄與評價都是 `undefined`。
目前呼叫端只 `invalidateQueries` 不看回傳值所以沒出事，但哪天有人拿去 `setQueryData`
就會讓那一列的車種車牌憑空消失。已改走 `normalizeDriver`，測試 mock 換成真後端形狀。

**驗過乾淨**：訂單列表 8 鍵、**六個篩選參數實跑證明真的有篩**（負向對照 `status=9`→0、
不存在關鍵字→0、未來日期→0）、分頁 `total` 正確、訂單詳情
`events`／`ride`／`track_geojson`／`stops`／`rating`（特地造一筆評過分的訂單才驗到）、
日／月報表欄位、遺失物 13 鍵、會費帳單 7 鍵（`period` 鍵名正確）。

### 模擬器 UI 實跑（`m6_pixel` ＋ customer flavor ＋ docker）

**這一輪沒有新 bug**，但把當天三個「靠讀程式碼修」的修正在**真 App 上閉環**：

| 修正 | 真機驗證結果 |
|---|---|
| 協尋入口（PR #55） | 地圖版首頁**即時**（未重啟，靠 WS）長出「遺失物協尋：藍色雨傘／司機已尋獲，待支付處理費」；點進去→付款 NT$21→狀態轉「已付款，等待歸還」→司機歸還後 banner 消失 |
| 司機放棄通知（PR #52／#53） | 司機卡片（車牌／撥號）**被清掉**並顯示「司機取消了行程，正在為您重新派車」＋回到配對中 |
| 背景輪詢靜默（PR #52） | 停掉後端 40 秒（跨 2 個輪詢週期）**零 SnackBar**；同一斷線下按「取消叫車」**仍跳出**「無法連線到伺服器，請檢查網路」 |

### 司機端 UI 實跑（同日追加，`m6_pixel` ＋ driver flavor）

**這一輪也沒有 bug**，但把司機端唯一沒在真 UI 上走過的流程補完：

| 檢查 | 結果 |
|---|---|
| O5 四態 gate | 未填→強制車輛頁／送出→審核中／admin 退回→**顯示退回原因**「車牌照片模糊，請重新提供」／改車→回審核中／核准→首頁，四態全對 |
| 退回頁沒有「重新整理」 | **合理**：後端只允許審核 `pending`，退回後必須改車重送，刷新沒有意義 |
| 電話格式驗證 | 打入非法字串 → 欄位轉紅＋下方「電話格式錯誤」，位置正確 |
| App 端要求電話（後端不強制） | 刻意：O7 補洞後 App 更嚴，與自己的文案一致 |
| 上線 → WS | 去系統設定授權背景定位後回來一度顯示「連線中斷」，**10 秒內自動重連**且 hero 與連線狀態同步恢復 |
| 全螢幕接單卡 | 新派單 #5、上車點／目的地、距離 338 公尺、ETA 約 1 分鐘、接單／略過 |
| 行程卡 | 內嵌 OSM 地圖（上車點紅釘＋司機綠車＋連線）、聯絡乘客／導航／乘客已上車／放棄此單 |
| 階段轉換 | 「乘客已上車」後 badge 轉「行程中」、地圖改畫**目的地藍旗**、按鈕換成導航去目的地／完成行程 |
| 放棄二次確認 | 「確定放棄這筆訂單？放棄後這筆訂單會回到派單池。」＋返回／確定放棄 |
| 收入頁 | 營業額 NT$206／手續費 −NT$30／實得 NT$176，與後端 20600/3000/17600 分**完全一致**；無評分時顯示「尚無評分」而非 0.0 |
| 遺失物空狀態 | 「目前沒有待處理的協尋」 |

**旁見（不是 bug，但下次做 UI 測試要知道）**：用 API 在 App 外建的訂單，**閒置中的 App 不會發現**——
`_activeRide` 為 null 時不輪詢，且 `ride.accepted` 的處理有 `if (active == null) return` 早退。
真實使用是 App 自己建單所以不受影響；跨管道（LINE 建單 ＋ App 開著）才會遇到，
要測 UI 就得從 App 建單、或重啟 App 走 REST 還原。

---

## 🔑 2026-07-28 第三輪 debug：token 過期後 App 整個說謊（本批修掉）

> 起點是一句可查證的事實：`grep -rn "401" lib/` **全 App 零命中**——兩端都沒有任何
> session 失效的處理路徑。後端 `JWT_EXPIRY_HOURS` 預設 **72 小時**，
> 所以這不是邊角情境，是**每個持續使用的司機／乘客三天後必然遇到**的。
> 開發時踩不到，因為我們每次 E2E 都是剛註冊剛登入。

**先對真後端取證**（用同一把 secret 簽一個 `exp` 在過去的 token 去打）：
`GET /driver/vehicle`、`POST /driver/location`、`GET /customer/rides/active`、
`GET /ws?token=` **全部 401 `{"error":"token 無效或已過期"}`**。

**過期之後 App 原本會怎樣**（機制，不是猜測）：

| 端 | 原本的行為 | 為什麼是 bug |
|---|---|---|
| 司機 | `isLoggedIn` 仍為 true → 停在首頁，開關顯示**「上線中／等待派單中」** | 位置回報每 8 秒被 401 擋下 ＝ 他**根本不在派單池**（後端沒收到任何位置），畫面卻說一切正常——與 `pitfall-driver-stuck-ontrip` 同一家族的「無聲失效」 |
| 乘客 | 停在叫車首頁，每按一次叫車跳一則 SnackBar **「token 無效或已過期」** | 使用者不知道 token 是什麼，畫面也沒告訴他唯一的出路是重新登入；地圖版首頁只有一顆不顯眼的登出鈕 |
| 兩端 | WS 帶失效 token 一直重連失敗 → 一直顯示「連線中斷」 | 看起來像網路不好，實際上永遠不會好 |

**修法**（app PR，本批）：
- `api_error.dart` 新增 `sessionExpiredMessage`（「登入已過期，請重新登入」）與 `isAuthPath()`。
- 兩個 api client 的 `_wrap`：**401 且非登入／註冊路徑** → 呼叫 `onUnauthorized` 並把訊息換成上面那句。
  **登入端點的 401 是「帳號或密碼錯誤」，一定要排除**——否則打錯密碼會變成「被登出」。
- 兩個 controller 注入 `onUnauthorized` → 本地登出（清 storage／WS／定位串流／所有跟著 session 的狀態）
  ＋設 error，登入頁本來就會顯示它，所以使用者一定看得到原因。
  **不打 `unregisterDeviceToken`**：token 已失效，那支 API 只會再回一次 401。
  以 `_sessionExpiring` 旗標擋並發 401 重入（輪詢與使用者操作可能同時撞上）。
- 司機端把登出與 session 失效共用的清理抽成 `_clearSession()`，**順手補上原本漏清的車輛狀態**——
  留著它，下一個登入的司機會在自己的資料載入前先看到別人的審核狀態。
- 乘客端 `logout()` **補清歷史行程**（`_rideHistory`／`_historyError`／評分星等）：
  這是上一個帳號的個人資料，換人登入後一進「我的行程」就會先看到前一位乘客的行程與車資。

**刻意沒做**：WS 握手失敗**不**判定 session 失效。`channel.ready` 的例外拿不到可靠的狀態碼，
硬解析字串會誤判。REST 已足以覆蓋——冷啟動一定走還原（REST），上線一定走位置回報（REST），
乘客任何操作都是 REST。**唯一漏網**是「司機登入後完全不上線、也不做任何操作」的閒置畫面，
它只會顯示「連線中斷」；一旦他做任何事就會被導回登入頁。

**驗收**：
- 靜態：`flutter analyze` 無 issue、`flutter test` **240 passed**（原 230 ＋新 10）。
  新增 `test/session_expiry_test.dart`：client 層 4 案（401 觸發＋換訊息／登入端點不觸發／
  乘客端同規則／409 不觸發）、司機端 3 案（冷啟動落回登入頁且不打 device-token／
  上線後位置回報 401 → 下線＋登出／已登出後不再發請求）、乘客端 3 案
  （冷啟動落回登入頁／登入頁把原因顯示出來／登出清歷史）。
  **反向確認**：拿掉 `onUnauthorized?.call()` 與歷史清理後，10 案中 **7 案 FAIL**
  （另 3 案本來就該 PASS：登入 401、409、client 層排除規則）。
- **✅ 模擬器實跑閉環（2026-07-28，`m6_pixel` 雙 flavor ＋ dispatch docker compose，全程截圖）**。
  讓 token 失效的手法是**輪替後端 `JWT_SECRET` 後重啟 app 容器**——舊 token 走的是
  與過期完全相同的 `ParseToken` 失敗路徑（實測回應一字不差），比等 72 小時可行。
  - **乘客端**：登入狀態＋進行中訂單（ride #4「正在為您配對司機」）→ 輪替 secret →
    **使用者沒按任何東西**，15 秒輪詢撞到 401 → App 自動落回登入頁＋粉紅橫幅
    **「登入已過期，請重新登入」**。（證明 silent 輪詢路徑也會處理 session 失效——
    它不寫全域 error，但 `_handleUnauthorized` 獨立於錯誤呈現。）
  - **司機端**：新帳號 `simexp01` 註冊→填車輛→admin 核准→登入直接進首頁（O5 四態正確）→
    上線（**Redis `drivers:geo` 含 driver 5、`driver:5:loc` 存在＝真的在派單池**）→
    輪替 secret → 約 10 秒後（下一次位置回報）**自動落回登入頁＋同一句橫幅**，
    狀態列的定位圖示消失＝前景定位串流也停了，不再留下「上線中」的假象。

---

## 🔄 2026-07-28 第四輪 debug：App 生命週期（背景→前景）

> 接續上一段列出的「下一輪還沒碰過的角落」第 1 項。
> 起點同樣是一句可查證的事實：`grep -rn "WidgetsBindingObserver\|didChangeAppLifecycleState" lib/`
> **全 App 零命中**——兩端從來不知道自己被切到背景過。

**三個獨立的缺口**（都不是「寫錯了」，是「從來沒做」）：

1. **司機端沒有任何回前景對帳**。司機端**沒有輪詢**，行程狀態 100% 靠 WS。
   背景期間只要斷過線（切網路、進隧道、後端重啟、系統凍結進程），
   `ride.cancelled` 就再也不會補送——**後端不補發歷史事件**。
   回前景後那張行程卡還掛在畫面上，司機會繼續開去接一個已經取消的乘客，
   直到他按下某個按鈕才被 409 擋下。
2. **WS 沒有心跳，偵測不到半開連線**。手機切背景、換網路、經過 NAT／LB 逾時後，
   對端可能已經沒了而本地 socket 收不到 FIN：`isConnected` 仍是 true、
   UI 顯示「即時連線正常」，卻永遠收不到派單，**而且不會觸發重連**
   （重連只由 `onDone`／`onError` 觸發，半開連線兩個都不會來）。
3. **回前景還要陪等退避**。退避在長時間離線後會拉到 30 秒上限；
   使用者剛回到前景、正盯著畫面等派單／等司機，卻還要再等最多 30 秒。

**順帶抓到一個既有的說謊**（本批新功能踩出來的）：`_scheduleReconnect()` **沒有清掉 `_channel`**，
所以整個重連等待期間 `isConnected` 都回 true——與同時回報 `onConnectionChanged(false)`
自相矛盾。舊碼沒出事是因為當時沒人讀 `isConnected`；`ensureConnected()` 一讀它就會
「以為還連著」而什麼都不做。已一併修掉（斷線時 `_channel = null` 並靜默關閉）。

**修法**：
- `AppLifecycleReactor`（`lib/shared/widgets/app_lifecycle_reactor.dart`）：**只對 `resumed` 動作**——
  `inactive`／`hidden` 在拉下通知欄之類的過場也會出現，對它們反應會在使用者根本沒離開 App 時
  打一堆沒必要的請求。兩端 root 各包一層（登入頁也在底下，controller 未登入時早退）。
- `DriverController.onAppResumed()`：`ensureConnected()` ＋ **以後端為準重讀 active** ＋ 協尋清單。
- `CustomerController.onAppResumed()`：`ensureConnected()` ＋ `refreshActive(silent: true)`——
  **silent**，這不是使用者按出來的刷新（沿用第一輪的原則）。
- `FleetWsClient`：預設連線改帶 **`pingInterval` 20 秒**（`IOWebSocketChannel`）→ 半開連線由底層偵測並關閉，
  走既有重連鏈；新增 `ensureConnected()`（已連上就什麼都不做，否則取消退避、歸零、立刻重試）。

**驗收**：
- 靜態：`flutter analyze` 無 issue、`flutter test` **248 passed**（240 ＋新 8）。
  新增 `test/app_lifecycle_test.dart`：reactor 2 案（只對 resumed／移除後不再收通知）、
  司機端 2 案（**背景期間行程被取消 → 回前景後行程卡消失**／未登入不打 API）、
  乘客端 1 案（立刻對帳且失敗不彈錯誤）、`ensureConnected` 3 案（斷線中 2 秒內重連、
  已連線不重建、登出後不偷連——後三案用真的本機 WebSocket 伺服器）。
  **反向確認**：三處修正各自拿掉後，對應的 3 案 FAIL。
- **✅ 模擬器實跑閉環（2026-07-28，`m6_pixel` driver flavor ＋ docker compose）**：
  - **漏事件重現**：司機接單（ride #6 行程卡在畫面上）→ HOME 切背景 → `docker stop app`
    （WS 斷、進入退避）→ 等 45 秒 → `docker start app` 後**在 App 重連之前**用乘客 API 取消
    （後端 18:47:03 起來，取消也在 18:47:03；App 那時還在退避）→ 回前景 →
    **行程卡消失，回到「等待派單中」**。
    後端 log 交叉驗證：**回前景的同一秒（18:47:59）**收到
    `SELECT * FROM rides WHERE driver_id = 5 AND status IN (2,3)`（＝`GET /driver/rides/active`）
    與 `lost_item_requests` 查詢——這兩個請求在修正前**根本不存在**。
  - **回前景立刻重連**：`docker stop app` 70 秒（退避已達 30 秒上限）→ `docker start app` →
    **不動 App，5 秒後畫面仍是紅底「連線中斷，暫時收不到派單」**＋「未連線，派單可能延遲」→
    切背景再回前景 → **2 秒後就變回「即時連線正常」**。

**沒做／已知限制**：心跳只在 App 前景真的有效（背景被系統凍結時 timer 不跑），
但那正是回前景對帳要補的洞，兩者互補。iOS 尚未在實機驗過（A5 階段 5 仍卡）。

---

## ⏱️ 2026-07-28 第五輪 debug：「其實成功了」與「其實沒成功」

> 接續第 3 項（弱網／逾時分支）。查下去發現真正的問題不在逾時文案，
> 而在**兩端都把「沒有丟例外」當成「成功」**。

**先對真後端取證**（curl 打實際端點）：

| 情境 | 後端實際回應 | App 原本怎麼解讀 |
|---|---|---|
| 同一乘客第二次建單 | **409**「已有進行中的訂單」 | 原樣顯示——但乘客畫面上根本沒有任何訂單，這句話無法行動 |
| 司機接一張已被別人接走的單 | **HTTP 200** ＋「手慢了，這單已被其他司機接走」 | **當成接單成功**：樂觀行程卡留在畫面上 |
| 司機非待命狀態接單 | **HTTP 200** ＋「您目前無法接單（非待命狀態）」 | 同上 |

**兩個真 bug**：

1. **司機抱著一張別人的行程卡出發**。`acceptOffer` 只在丟例外時才算失敗，而後端這兩種
   拒絕都是 200。舊碼的重讀 active 又寫著「回 null 或別的 rideId 時**寧可保留樂觀設定**」，
   於是沒接到的情況下畫面照樣顯示行程卡，直到司機按「乘客已上車」被 409 擋下才發現。
2. **弱網下「請求送達、回應丟失」＝ 使用者被騙**。
   - 司機端：接單其實成功了，App 卻報錯。司機按「略過」→ 行程從畫面消失，
     而後端已把他設成載客中——**收不到新派單、也無法離線**，畫面上什麼都沒有
     （這正是 `pitfall-driver-stuck-ontrip` 的成因之一）。
   - 乘客端：建單其實成功了，App 停在叫車表單說「請求逾時」；再按一次就得到
     409「已有進行中的訂單」——唯一的出路是重開 App。

**修法**（同一個原則：**有副作用的請求，結果要向後端問，不能只看有沒有丟例外**）：
- 司機端 `acceptOffer`：接單後一律重讀 active，以「是不是這張單」判定三態
  （`_AcceptOutcome`）。**confirmed** → 以後端資料覆蓋樂觀值（順帶補齊推播路徑缺的 stops）；
  **rejected** → 收掉樂觀行程卡並說明「這單已被其他司機接走」；
  **unknown**（重讀本身也失敗＝網路仍不通）→ 保留樂觀行程，因為「真的接到卻看不到行程」更糟。
  逾時（`statusCode == null`）也走同一條確認：確認到了就當作接單成功，不報錯。
  後端 `AcceptRide` 是同步寫入後才回應，所以「回應之後 active 查得到」可以依賴——
  `null` 是真的沒接到，不是還沒寫好。
- 乘客端 `placeOrder`：逾時（`statusCode == null`）或 **409** 時先問後端有沒有進行中訂單，
  有就直接接手（含已被接單時的司機資訊）。**400 之類的輸入錯誤不觸發對帳**——那是真的沒建。
  建單成功與「其實已經建好了」共用同一份狀態切換（`_applyCreatedRide`），
  避免兩份清單其中一份漏掉某項而把上一趟的司機／取消通知帶進這一趟。

**驗收**：
- 靜態：`flutter analyze` 無 issue、`flutter test` **257 passed**（248 ＋新 7 ＋改寫 2）。
  新增 `test/customer_place_order_timeout_test.dart` 7 案（逾時已建／409 已建／逾時期間已被接單
  連司機資訊帶出／真的沒建照常報錯／對帳也失敗不編故事／400 不觸發對帳／終態訂單不算數）；
  `driver_controller_test` 加 2 案（逾時但其實接到了、逾時且真的沒接到）並**改寫**原本
  「回別的行程／null 時不覆蓋樂觀行程」那條——它釘的正是本輪要修掉的行為。
  **反向確認**：兩處修正各自拿掉後，5 案 FAIL。
- **✅ 模擬器實跑（`m6_pixel` driver flavor ＋ docker compose）**：
  司機 A（`simexp01`）上線收到 ride #8 接單卡 → **趁他還沒按，用 API 讓司機 B（`simexp02`）接走**
  → 司機 A 按「接單」→ 後端回 200「手慢了」→ **App 沒有出現行程卡**，
  改顯示紅色橫幅**「這單已被其他司機接走」**，畫面回到「等待派單中」。
  DB 交叉驗證 ride #8 `driver_id = 6`（司機 B），與畫面一致。
- **誠實標記**：「逾時但其實成功」這條在真機上不好精準重現（要讓回應剛好在
  `receiveTimeout` 後才丟失），**只有單元測試覆蓋**，未在模擬器上實跑過。

---

## 下次任務

> **✅ 維護項 5「清開發殘留」已完成（2026-07-28）**，詳見上方。
> 清理過程又撈到一份未合併的測試（dispatch PR #50）——
> **「從未開過 PR」的分支是最危險的一種殘留**：它不在任何 PR 列表裡，
> 只有逐條比對 diff 才看得到。
>
> **➡️ 下次任務：剩下的都被外部資源卡住**，開工前先確認前置條件到位：
> 1. **A2 真裝置推播**——需要你先建 Firebase 專案並提供 `google-services.json`（後端 FCM 已上線）。
> 2. **A5 階段 5 iOS 實機部署**——需要你接上 iPhone、Xcode 選 Personal Team、手機信任憑證。
>    （階段 6 iOS 推播仍卡付費 Apple Developer Program。）
> 3. **B5 的另一半：完成後付款**——需要真金流方案（後端 P4 #19），屬產品決策。
> 4. **車種供給為零時的選項處理**——等產品拍板要停用、隱藏、還是照選但提示。
>
> **不需前置條件、隨時可做的維護項**（2026-07-27 盤點新增）：
> 5. ~~**清開發殘留 worktree／舊分支**~~ ✅ **已完成（2026-07-28）**，見上方專段。
> 6. ~~**清 dev DB 測試殘留**~~ ✅ **已完成（2026-07-28）**，見上方專段
>    （**原本寫的機制是錯的**，一併更正）。
> 7. **評分的營運動作**（B5 下游）：三端現在都只「看得到」評分，
>    **沒有低分司機的處理流程**（通知／停權／申訴）。
>    **條件**：等實際累積評分、營運說得出要對低分司機做什麼再開——
>    做在前面只會做出沒人用的流程。
>
> **2026-07-28 又補了一項（不在原清單上）**：`docs/IOS_PLAN.md` 的**勾選框與散文不一致**——
> 階段 1 的四項、3-4、7-1 的散文說完成、勾選框卻仍是 `[ ]`／`[~]`。
> 只讀清單的人會以為要重跑那些 sudo 步驟。已逐條重新取證後補勾（見 IOS_PLAN「執行進度」）。
> **前置條件當日實查**：`android/app/google-services.json` **不存在**（A2 仍卡）、
> `xcrun devicectl list devices` → **No devices found**（A5 階段 5 仍卡）。
>
> **2026-07-28 收尾**：清單清空後改做 debug——修掉 4 個 bug、做完一輪跨端契約對帳，
> 見上方「🐞 2026-07-28 debug」。**六份清單（本檔、admin TODO、IOS_PLAN、gap-analysis-plan、
> 兩份 UI/UX 執行計畫）的勾選現在全部對得上程式碼現況**，文件層面沒有可清的東西了。
>
> **🎯 下次開工第一件事**：**維護項已經清空了**（5、6 都完成，7 要等營運需求）。
> 第 1–4 項全部需要你提供外部資源或拍板，**沒有前置條件就不要硬找事做**——
> 開工前先確認：Firebase 專案（A2）／iPhone＋Xcode Personal Team（A5 階段 5）／
> 金流方案（付款）／車種供給為零的產品方向。四者皆無時，正確答案是「這輪沒有可做的事」。
>
> 真的想再往前推、又不解上述卡點的話，**唯一剩下有價值的方向是繼續 debug**：
> ~~遺失物協尋鏈路、admin 端 REST 形狀、模擬器 UI 層~~ 三者已於第二輪補完；
> **第三輪（2026-07-28）修掉 token 過期後 App 說謊**，見上方「🔑 第三輪 debug」。
>
> **➡️ 下一輪 debug 還沒碰過的角落**（依價值排序，都不需外部資源）：
> 1. ~~**App 生命週期**~~ ✅ **已完成（2026-07-28 第四輪）**，見上方專段。
> 2. **多裝置／同帳號重複登入**：同一司機在兩台裝置上線，後端沒有踢舊 session 的機制，
>    兩邊都會收派單——先確認後端行為，再決定 App 該不該處理。
> 3. ~~**弱網**（非全斷）的逾時分支~~ ✅ **已完成（2026-07-28 第五輪）**，見上方專段
>    （真正的問題不是文案，是「沒丟例外 ＝ 成功」的判定）。
> 4. **其他有副作用的操作是否也有同一個洞**：`pickUp`／`completeRide`／`cancelRide`
>    在逾時後同樣可能「其實成功了」。本輪只修了最貴的兩條（接單、建單）——
>    完成行程逾時會讓司機重按，後端回 409 而司機仍停在行程卡上。
>    **條件**：等第五輪的做法在真機上跑一陣子沒問題，再用同一套 `_confirm*` 模式推廣。

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

**指數退避 ✅ 2026-07-21**：重連間隔改 **3→6→12→24→30 秒封頂**（`FleetWsClient.reconnectDelayFor`）。
固定 3 秒在長時間離線（隧道、後端維護）會一直打空包白耗電與流量；退避後最壞情況是恢復連線
最多晚 30 秒，對派單可接受。**第一次仍是 3 秒**，短暫閃斷的恢復速度不變；**握手成功即歸零**，
「連上又斷」不會沿用上一輪的長間隔。次數大到左移溢位（變負數）時夾到上限——否則會變 0 秒狂重連。
測試：純函式 6 個斷言＋「連上後 `reconnectAttempts == 0`」（`flutter test` 173 passed）。
**未做**：抖動（jitter）。後端重啟時所有司機會同時退避到同一秒重連，量體大時再加。

## 🧍‍♂️🧍‍♀️ 多乘客／多停靠點行程（2026-07-16 規劃，**已於 2026-07-17～21 全數實作**）

> 需求（使用者 2026-07-16）：乘客端可在一張訂單安排**多位客人**各自的上車／下車點，
> 中途設**中斷點**，**最多 5 位**；司機端同步收到「客人 A/B/C/D 在哪上車／下車、最終目的地」，
> 依最終目的地計費。
> **主規格與資料模型見** [line-fleet-dispatch/docs/TODO.md](../../line-fleet-dispatch/docs/TODO.md)「N. 多乘客／多停靠點行程」。
> **這不是陌生人拼車**，是同一張訂單、同行的多位乘客、依序停靠。

**依賴**：後端 N1–N6（`ride_stops` 表、建單 API 帶 stops、`ride.assigned`／`rides/active` 回 stops）。
**App 端在後端就緒前無法實作**（現行 model 只有單一 pickup／dropoff）。

### 乘客端

- [x] **停靠點編輯 UI** ✅ 2026-07-17（`StopsEditor`，詳見上方「App 端補完清單」）：
      叫車表單可新增／刪除「乘客 + 上車點 + 下車點」。
      ✅ 定案（2026-07-16）：**最多 5 位乘客、各自上下車 → 最多 10 個停靠點**。
      每個點沿用既有 `MapPickerScreen`（flutter_map 選點，免 key）取座標。
      這是目前叫車表單（單一目的地）之外最大的一塊 UI 改動。
- [x] **模型擴充** ✅ 2026-07-17：`CustomerRide` 加 `stops`；`createRide` body 帶 `stops` 陣列
      （`buildStops` 保證滿足後端 N2 的配對規則）。
- [x] **地圖呈現** ✅ 2026-07-21：`CustomerMapHomeScreen` 多停靠點模式——
      依序畫出全程停靠點（乘客標籤 A/B…）＋「司機→下一站→之後待處理站」折線。
      **下一站全彩放大、之後的站半透明、已到達灰勾、已跳過不畫**，與司機端概覽地圖同一套規則
      （純函式搬到 `lib/core/util/route_stops.dart` 共用，兩端各寫一套遲早會出現
      司機看到 A、乘客看到 B）。單點訂單走原本的單一紅釘，畫面不變。
- [x] **行程中顯示進度** ✅ 2026-07-21：`RideStopsProgress`（`司機途中`／`行程中` 兩階段都顯示）——
      「行程進度 N／M 站」＋「下一站：乘客 X上車」＋全程清單。
      **完全唯讀**（乘客不能標記到站，所以不放任何操作鈕）；
      已跳過的站寫「**未搭乘**」而不是「跳過」——跳過是司機視角的動作，乘客該看到的是結果。

> **後端配合已上線**：dispatch PR #41（N8）讓 `GET /api/customer/rides/active`／
> `GET /api/customer/rides/:id` 帶 stops（形狀與司機端 `DriverRideView.Stops` 完全相同），
> 並新增 WS **`ride.stop_updated`**（payload 帶整趟 stops）。
> App 端 `CustomerRide` 加 `stops`／`hasStops`／`nextStop`／`handledStopCount`，
> 收到事件**整批覆蓋**（不套用差異，漏收一則也不會讓進度永遠對不上；ride_id 不符則忽略）。
>
> **模擬器實跑驗收 ✅（2026-07-21，iPhone 17 Pro＋後端 docker）**：
> 乘客建 2 人 4 站訂單 → 地圖顯示 4 站與折線、進度卡「0／4 站・下一站：乘客 A上車」→
> 司機 API 標記第 1 站到達 → **App 未操作即時變 1／4、下一站改 B、該站綠勾「已完成」** →
> 司機跳過第 2 站 → **2／4、刪除線＋「未搭乘」、下一站前移到 A 下車、地圖上該站消失**。

### 司機端

- [x] **接單卡顯示全程** ✅ 2026-07-18（PR #31）：`RideOffer` 加 `stops`、`acceptOffer` 帶入。
      **這項曾被大項 [x] 蓋掉子項 [ ]**——規劃段寫了但從未實作，直到 2026-07-18 模擬器實跑
      才發現「接單當下沒有全程、要重啟 App 走 rides/active 還原才看得到」。
- [x] **行程卡依序列出停靠點** ✅ 2026-07-17：`ActiveRide` 加 `stops`，`RideStopsList` 依序列出全程，
      **只有「下一站」給操作**（已上車／已下車／跳過），一次一件事避免誤按後面的站。
- [x] **概覽地圖多點** ✅ 2026-07-17：詳見上方「App 端補完清單」的概覽地圖多點連線。
- [x] **導航按鈕** ✅ 2026-07-21：多停靠點時導航去**下一站**（`ride.nextStop`）而非最終目的地——
      司機依序停靠，導去終點會把中間的乘客載過頭；全部站處理完才退回最終目的地。
      按鈕文案跟著目標走（「導航去下一站（乘客 A上車）」）。
      **順帶修掉一個既有缺口**：`前往上車點` 的導航原本只送 `ride.address` 字串、
      沒帶 `pickupLat/pickupLng`——地址在 Google Maps 可能解析到同名的錯誤地點，
      而座標從 2026-07-16 起就已經有了（`DriverRideMap` 一直在用）。現在一律優先給座標。
      地址與座標都沒有時整顆按鈕不顯示（按了只會開出無意義的搜尋）。
      驗收：新增 2 項 widget 測試，反向確認拿掉修正會 FAIL；`flutter test` 173 passed。

### App 端待拍板

- 停靠點編輯的 UX：一次填滿 5 位很繁瑣，是否預設 1 位、按「+ 新增乘客」漸進展開？
- ~~車資預估：乘客建單時要不要先顯示預估車資？~~ ✅ 已做（2026-07-23，報價 API，見下方「💰 建單前車資預估」）。

---

## 🚗 司機車輛資訊（車種／車牌）（2026-07-16 規劃，**已於 2026-07-17～22 全數實作**）

> 需求（使用者 2026-07-16，含後續拍板）：乘客端顯示司機的**車種與車牌**；
> 司機**必須先上傳車種車牌才能接單**（**強制跳轉引導、不設寬限期**）；
> 車種為**選單**（轎車／休旅／七人座／無障礙／**寵物用車**）；
> **寵物用車加收清潔費**（上限 30%），**乘客端要分項顯示**；
> 司機換車後乘客仍能查到**當時車輛**與**司機聯絡方式**，並用**留言板**聯絡（沿用既有聊天）。
> **主規格見** [line-fleet-dispatch/docs/TODO.md](../../line-fleet-dispatch/docs/TODO.md)「O. 司機車輛資訊／寵物車清潔費」。

**依賴**：後端 O1–O7（`drivers` 車輛欄位、`GET/PUT /api/driver/vehicle`、派單/接單 gate、
`ride.accepted` 帶車輛資訊與司機電話、`rides` 車輛快照、`pet_cleaning_fee_bps` 與 `cleaning_fee_cents`）。

### 司機端

- [x] **車輛資訊設定頁** ✅ 2026-07-17（車種＋車牌）／**2026-07-22（聯絡電話補上）**：
      車種**下拉選單**（轎車／休旅／七人座／無障礙／寵物用車，顯示名稱在 App 對應，送後端 code）
      ＋車牌輸入＋**聯絡電話**，串 `GET/PUT /api/driver/vehicle`。
      **聯絡電話是 2026-07-22 才真正可填**：`drivers.phone` 欄位一直存在，但後端**沒有任何寫入路徑**
      （註冊不收、車輛端點也不收），所以 O7 拍板的「乘客可直接撥打司機電話」實質從未生效——
      乘客端 `DriverVehicleCard` 的 `tel:` 按鈕永遠不會出現。
      後端同批新增 `PUT /api/driver/profile`（dispatch Q3），
      **與車輛端點分開**：改電話不重置 O5 車輛審核，否則司機為了改號碼就被鎖出派單池。
      讀取端 `GET /driver/vehicle` 順帶回 `phone`，設定頁不必多打一支。
      **存檔順序：電話先、車輛後**——車輛存成功會讓 `hasVehicle` 變 true，
      強制情境下 `_DriverRoot` 當場把本頁換成首頁，排在後面的電話寫入就沒有畫面可以回報失敗。
      電話**必填**（沒號碼這張設定頁就少做了一半的事），只驗位數不驗樣式
      （車隊可能有市話或境外號碼，硬綁「09 開頭」會誤擋真號碼——與後端 `IsValidPhone` 同一策略）。
      驗收：新增 4 項測試（寫入順序、電話失敗不續寫車輛、正規化以後端回傳值為準、
      改電話不動審核狀態）；`flutter analyze` 無 issue、`flutter test` **183 passed**。
- [x] **強制跳轉引導** ✅ 已實作（2026-07-17）；定案（2026-07-16）：未填車輛資訊時**強制導向設定頁**，
      填完才能回到首頁／上線。不是「提示」而是 gate——
      使用者明確要求「強迫司機必須填寫才能開始接單（用跳轉方式引導）」。
      實作點：`driver/app.dart` 的 `_DriverRoot`（目前只有 `isLoggedIn ? Home : Login`），
      加第三種狀態 `已登入但無車輛資訊 → VehicleSetupScreen`。
      註：**後端也會擋**（O3），App 端跳轉只是提早給回饋、不能只靠 App。
- [x] **`DriverController` 狀態** ✅ 2026-07-17：加 `vehicle`／`hasVehicle`；`init()`／`login()` 後載入。
      注意 `hasVehicle` 未載入完成前不要誤判成「沒填」而閃跳轉（載入中要有明確狀態）。

### 乘客端

- [x] **顯示司機車種車牌** ✅ 2026-07-17（`DriverVehicleCard`）：`ride.accepted` 後的「司機前往上車點」階段，
      sheet 目前只顯示「司機：{name}」＋ETA，要加車種與車牌（醒目、方便路邊對車）。
      `CustomerController` 的 `driverName` 旁加 `driverVehicleType`／`driverPlateNumber`。
- [x] **司機聯絡方式** ✅ UI 2026-07-17／**號碼真的填得進去要到 2026-07-22**（見上方司機端設定頁）：
      **明碼**顯示可撥打的電話（`tel:` 連結）＋留言板入口。
      僅該趟乘客可見（後端 MultiAuth 控管，App 只在行程／協尋畫面顯示，不做任何司機列表）。
- [x] **清潔費分項顯示** ✅ 2026-07-17（`CompletedRideSummary`）：完成卡不可只給總額，拆「車資 ＋ 清潔費 ＝ 合計」。
      **只有乘客指定寵物車的行程才有清潔費**（依 `required_vehicle_type`，非司機車種）；
      未指定時完成卡不該出現清潔費欄位。
      `CompletedRideSummary` 目前只有 `fareAmountCents`，要加 `cleaningFeeCents`。
      沿用 `money.dart` 的整數元格式（M 已定案）。
- [x] **留言板入口補遺** ✅ 2026-07-19：加「我的行程」歷史畫面
      （`CustomerRideHistoryScreen`，首頁右上 receipt FAB 進入），列出過去行程
      （狀態／路線／時間／車資），**有派到司機的行程**給「聯絡司機」開 `RideChatScreen`
      （派單前取消的無對象可聯絡）。後端新增 `GET /customer/rides`
      （dispatch PR #39：`ListRecentByCustomer`，LEFT JOIN drivers 取司機名，只回本人）。
      沿用既有聊天，`RideChatScreen` 已按 `rideId` 過濾，重用 `ctrl.chatStream` 安全。
      **模擬器實跑驗過**：完成 ride #9 → 歷史畫面顯示（NT$212／司機名）→ 聯絡司機
      → 發訊右靠綠泡 → 後端持久化、司機端 `GET /rides/9/messages` 讀到 `customer:...`。

### 乘客指定車種（✅ 2026-07-16 拍板採此方案，依賴後端 P1–P5）

> 清潔費依**乘客指定的車種**加收（不是司機車種）→ 乘客端必須能選車種。
> 主規格見 [line-fleet-dispatch/docs/TODO.md](../../line-fleet-dispatch/docs/TODO.md)「P. 乘客指定車種」。
> **不只服務寵物車**——無障礙／七人座同樣是乘客有需求才指定。

- [x] **叫車表單加車種選擇** ✅ 2026-07-17（`VehicleTypePicker`）：預設「不指定」，可選轎車／休旅／七人座／無障礙／寵物用車。
      `createRide` body 帶 `required_vehicle_type`（未選則不帶，維持現行行為）。
- [x] **選寵物車時當場顯示加價** ✅ 2026-07-17：選擇的當下就看得到「將加收清潔費 X%」，
      不能等完成才知道。後端已拍板（2026-07-16）開 **`GET /api/customer/fees`**（P5，customer JWT，
      唯讀白名單，只回 `pet_cleaning_fee_bps` 等乘客該知道的欄位）→ App 在車種選擇 UI 呼叫它。
      快取一次即可（費率不常變），失敗時降級顯示「將加收清潔費（上限 30%）」不擋叫車。
- [x] **找不到指定車種的回饋** ✅ 2026-07-17（controller）＋UI 同日；後端拍板（2026-07-16，P4）：**不降級**、
      取消時 WS `ride.cancelled` payload 會帶 `cancel_reason=no_vehicle_of_type`＋`required_vehicle_type`。
      App 端依 `cancel_reason` 顯示明確訊息（「附近暫無寵物用車」）——**用機器可讀欄位判斷，
      不 parse 文案字串**；並考慮引導「改用不指定車種重新叫車」的快捷操作。
- [ ] **車種供給為零時**：該選項是否停用／隱藏（依後端是否提供「目前可用車種」查詢，P 風險 2）。

### App 端待拍板

- 車牌顯示格式：是否放大／等寬字型方便對照？（乘客在路邊要快速比對）
- 車種選擇的 UI 形式：下拉選單 vs 橫向卡片（帶圖示＋加價標示）——
  寵物車有加價，用卡片較能同時呈現「車種＋加價」，但佔版面。
