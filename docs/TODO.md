# line-fleet-app — 補強清單

> 建立：2026-07-08 盤點（以程式碼實測為準）。最後盤點：**2026-07-30**。
> 編號沿用後端 repo 的
> [gap-analysis-plan](../../line-fleet-dispatch/docs/2026-07-07-gap-analysis-plan.md)（A=司機端、B=乘客端）。
> 每完成一項：實跑驗收 → 勾選回填 → commit + push（main 受保護，走 PR）。

## 這份文件怎麼讀

> 本檔已累積到 1600＋ 行，**不要從頭讀**。三種進場方式：
>
> - **要知道下一步做什麼** → 直接跳 [下次任務](#下次任務)（最後一段是「開工第一件事」）。
> - **要查某個功能為什麼長這樣** → 用下面的目錄找對應專章；每章都寫了**決策理由**，
>   不只寫做了什麼。
> - **要接手 debug** → 看 [第九輪盤點](#-2026-07-29-第九輪盤點下一輪的三個候選本批只盤點沒有修)
>   （目前最新、且已附證據指令），再往回翻第一～八輪確認同一個坑沒被查過。
>
> **三條寫作規則**（前幾輪踩過才立的，改這份文件請照做）：
> 1. **勾選要對齊程式碼現況**——大項 `[x]` 不可以蓋掉沒做的子項（2026-07-18 踩過：
>    「接單卡顯示全程」被大項勾掉，實際從未實作）。
> 2. **寫「驗過」就要寫**驗證方式與數字（`flutter test` 幾 passed、哪支指令、哪個裝置）；
>    只讀碼推論的要明講「未實跑」。
> 3. **過期敘述要當場更正**，不要只補新段落——同一件事有兩種說法比沒寫更糟
>    （2026-07-28 的 CI 敘述、2026-07-28 的 dev DB 機制都是這樣改掉的）。

## 目錄

**一、收尾清單（原始盤點）**
- [現況](#現況)
- [B. 乘客端 App（M7）— 收尾](#b-乘客端-appm7-收尾)
- [A. 司機端收尾](#a-司機端收尾)
- [2026-07-10 修掉的既有阻塞（非 UI 翻新引入）](#2026-07-10-修掉的既有阻塞非-ui-翻新引入)
- [被後端擋住的項目](#被後端擋住的項目)
- [品質/雜項](#品質雜項)

**二、功能專章（做了什麼、為什麼這樣做）**
- [🚨 後端 N/O/P 已全部上線——App 端補完進度](#-後端-nop-已全部上線2026-07-17app-端補完進度)
- [✅ O5：admin 車輛審核（三端）](#-o5admin-車輛審核2026-07-19-拍板並完成三端)
- [☎️ 司機聯絡電話填寫入口](#-司機聯絡電話填寫入口2026-07-22)
- [💰 建單前車資預估](#-建單前車資預估懸而未決-12026-07-23)
- [⭐ 乘客評分司機（B5）](#-乘客評分司機b52026-07-27)
- [🔐 登入頁 UI/UX 翻新＋驗證](#-登入頁-uiux-翻新驗證2026-07-23)
- [🧍‍♂️🧍‍♀️ 多乘客／多停靠點行程](#-多乘客多停靠點行程2026-07-16-規劃已於-2026-07-1721-全數實作)
- [🚗 司機車輛資訊（車種／車牌）](#-司機車輛資訊車種車牌2026-07-16-規劃已於-2026-07-1722-全數實作)
- [即時聊天／遺失物協尋](#即時聊天遺失物協尋2026-07-13-實作)
- [手續費／會費／司機收入](#手續費會費司機收入2026-07-11-規劃)
- [地圖引擎改用 flutter_map + OpenStreetMap](#地圖引擎改用-flutter_map--openstreetmap2026-07-16)
- [司機端內嵌概覽地圖](#司機端內嵌概覽地圖2026-07-16)
- [WS 斷線的真實狀態與 UI](#ws-斷線的真實狀態與-ui2026-07-16)

**三、Debug 輪次（每輪都是「先取證再修」）**
- [🧪 模擬器實跑驗收（2026-07-18）](#-模擬器實跑驗收2026-07-18m6_pixel--後端-docker全程截圖)
- [模擬器實跑發現（2026-07-15）](#模擬器實跑發現2026-07-15)
- [🐞 第一輪：4 個 bug ＋ 跨端契約對帳](#-2026-07-28-debug4-個-bug--跨端契約對帳)
- [🔎 第二輪：協尋鏈路、admin REST、模擬器 UI](#-2026-07-28-第二輪-debug協尋鏈路admin-rest模擬器-ui)
- [🔑 第三輪：token 過期後 App 整個說謊](#-2026-07-28-第三輪-debugtoken-過期後-app-整個說謊本批修掉)
- [🔁 第四輪：App 生命週期（背景→前景）](#-2026-07-29-第四輪-debugapp-生命週期背景前景本批修掉)
- [🎫 第五輪：搶單／多裝置](#-2026-07-29-第五輪-debug搶單多裝置app-對接單失敗一無所知本批修掉)
- [📶 第六輪：弱網（連得上但通不了）](#-2026-07-29-第六輪-debug弱網連得上但通不了本批修掉)
- [🧭 第七輪：「WS-only state」整族掃一遍](#-2026-07-29-第七輪-debug把ws-only-state整族掃一遍本批修掉-1-個)
- [📡 第八輪：事件收件人矩陣](#-2026-07-29-第八輪-debug事件收件人矩陣app-寫好的處理後端從沒送過本批修掉-2-個)
- [🔬 第九輪盤點：下一輪的三個候選（**未修，只取證**）](#-2026-07-29-第九輪盤點下一輪的三個候選本批只盤點沒有修)
- [🔧 第十輪：聊天室回前景補讀＋三條寫入路徑的逾時對帳](#-2026-07-29-第十輪-debug把第九輪的候選-23-修掉本批)
- [📲 第十一輪：乘客端推播接線（候選 1 的前半）](#-2026-07-29-第十一輪乘客端推播接線候選-1-的前半)
- [🔔 第十二輪：點推播喚醒的事件在沒人聽時被丟掉](#-2026-07-30-第十二輪點推播喚醒的那條路事件在沒人聽的時候就被丟掉了本批修掉)
- [💬 第十三輪：對話訊息的推播（兩端）](#-2026-07-30-第十三輪對話訊息的推播兩端)
- [🧪 第十四輪：把第十輪那兩項搬到模擬器實跑（抓到 1 個 bug）](#-2026-07-30-第十四輪把第十輪那兩項搬到模擬器上實跑本批抓到-1-個-bug)
- [🔦 第十九輪：司機端協尋畫面的實跑證據（沒抓到 bug，補了負向對照）](#-2026-07-30-第十九輪司機端協尋畫面的實跑證據沒抓到-bug補了一個負向對照)
- [📍 第二十一輪：定位串流死掉時，畫面永遠不會知道](#-2026-07-30-第二十一輪定位串流死掉時畫面永遠不會知道本批修掉)
- [📍 第二十二輪：乘客端的定位出口（＋第二十一輪的實跑尾巴）](#-2026-07-30-第二十二輪乘客端的定位出口本批修掉-31-個並補完第二十一輪的實跑尾巴)
- [🗓️ 預約司機＋常用地點（跨端新功能，含 debug 兩個）](#-預約司機常用地點2026-07-31跨端新功能)

**四、維護、決策與待辦**
- [🧹 清開發殘留 worktree／舊分支（維護項 5）](#-清開發殘留-worktree舊分支維護項-52026-07-28-完成)
- [🗄️ 清 dev DB 測試殘留（維護項 6）](#-清-dev-db-測試殘留維護項-62026-07-28-完成)
- [🧾 PR 佇列稽核：兩條 stack 做了同一件事](#-2026-07-29-pr-佇列稽核兩條-stack-做了同一件事本批清掉)
- [🚧 刻意沒做（寫明什麼條件成立才該做）](#-刻意沒做2026-07-22-盤點後決定不動)
- [🔮 懸而未決（需產品拍板）](#-懸而未決需產品拍板)
- [➡️ 下次任務](#下次任務)

## 現況

- 司機端（M6）主鏈路完成：登入→hero 上線→**前景服務 GPS**→全螢幕接單→導航→上車→完成／放棄（二次確認）。
- 乘客端（M7）：登入→叫車（目的地優先）→階段共用元件／地圖 Bottom Sheet→WS ETA→取消／完成卡。
- **UI/UX 翻新（2026-07-10）**：LINE 綠亮暗雙主題；司機駕駛情境 UI；乘客地圖為底＋卡片降級。靜態驗收 49 tests 通過；模擬器主鏈路待後端 docker 可起後補跑。
  **登入／註冊頁 2026-07-23 補齊翻新**（先前是唯一漏網畫面），詳見下方「🔐 登入頁 UI/UX 翻新＋驗證」。
- **座標導航（2026-07-10）**：司機端目的地導航改吃後端 `dropoff_point` 座標，地址僅供顯示與退路。
- 單元測試：**52 個測試檔、`flutter test` 407 passed**（2026-07-31 預約司機那批實跑；`flutter analyze` 無 issue）。
  ~~（54 項）~~ 是 2026-07-10 的數字，長期沒更新，已更正——**本節的數字請跟著最後盤點日一起改**。
- 遠端：`github.com/thothawei/fleet-app`。**2026-07-29 實查**：`git ls-remote --heads origin` 只有 `main`、
  `gh pr list` 三個 repo 的 open PR 皆為 0（開工前請自己再跑一次，見「下次任務」第 1 點）。

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

## 🔁 2026-07-29 第四輪 debug：App 生命週期（背景→前景）——本批修掉

> 「下一輪 debug 角落 1」。起點是一句可查證的事實：`grep -rn "AppLifecycle\|WidgetsBindingObserver" lib/`
> **全 App 零命中**——切到背景再回前景，App 什麼都不做。

**兩個機制（都在真裝置上取證，不是讀程式碼猜）**：

1. **司機端沒有任何輪詢**：`ride.assigned`／`ride.cancelled`／`ride.completed` 全靠 WS。
   背景期間連線被系統關掉的話，漏掉的事件**沒有第二條路補回來**——畫面會停在背景前的狀態，
   直到司機自己按下某個操作才被後端 409 打回。乘客端有 15 秒輪詢，但那個 timer 在
   Android 的 app freezer／iOS 的 suspend 下同樣不會跑。
2. **回前景時 WS 只能等退避**：離線久了退避已經長到 30 秒上限，而背景期間 timer 是凍結的，
   回前景那一刻它可能才開始倒數。使用者已經在看畫面了，卻還要等最多 30 秒才連得上。

**改了什麼**：
- `FleetWsClient.ensureConnected()`：沒連上就立刻開新連線（取消待定的退避 timer、退避歸零）；
  **已連上或正在連線時什麼都不做**——把好的連線砍掉重開只會製造更長的空窗。
  以 `_opening` 旗標擋重入，否則兩條 `_open()` 會互相蓋掉 `_channel` 並留下沒人取消的訂閱。
- 🐛 **順手修掉一個既有的說謊旗標**：`isConnected` 原本是 `_channel != null`，但斷線時
  （onDone／onError）只排重連，`_channel` 要等下一次 `_open()` 才清得掉——中間那段它指著
  一條已死的 channel。這個洞先前沒人踩到（外部沒人讀 `isConnected`），
  但 `ensureConnected()` 一讀它就會**永遠早退、永遠不重連**。
  是新測試（實測 3.016 秒＝走了退避 timer，不是立刻重連）抓到的，不是想出來的。
  改成與 `onConnectionChanged` 同步翻的 `_connected` 旗標，兩邊永遠說同一件事。
- `AppLifecycleReactor`（`lib/shared/widgets/`）：兩端 app root 各包一層，
  **只有真的離開過前景（paused／hidden／detached）再回來才通知**——inactive 是通知列下拉、
  來電橫幅、權限對話框這類短暫失焦，連線不會斷，把它當回前景等於每點一次通知就多打兩支 API。
- 兩端 controller 的 `onAppResumed()`：`ensureConnected()` ＋ 向後端**重新對帳**
  （司機：`rides/active`＋協尋清單；乘客：`refreshActive`＋協尋清單）。
  **一律靜默**：使用者只是把 App 切回來、沒按任何東西，失敗不該冒錯誤（同 2026-07-28 修掉的那一類）。
  **刻意不重查車輛審核狀態**：`refreshVehicle()` 失敗會打開 `vehicleLoadFailed`、整個畫面換成錯誤頁，
  等於網路一抖就把行程中的司機踢出首頁；審核狀態本來就有後端 gate 擋著。

**驗收**：
- 靜態：`flutter analyze` 無 issue、`flutter test` **249 passed**（原 240＋新 9）。
  新增 `test/app_lifecycle_test.dart`：WS 2 案（斷線後立刻重連／已連上時不砍掉重開，
  且不疊出第二條連線）、司機端 3 案（背景期間被取消的行程回前景後消失／對帳失敗靜默且不誤登出／
  未登入不打 API）、乘客端 3 案、reactor 1 案（inactive 不算回前景）。
  **反向確認**：拿掉兩端的對帳與 `_leftForeground` 判斷後，3 案 FAIL。
- **✅ 模擬器實跑閉環（2026-07-29，`m6_pixel` driver flavor ＋ dispatch docker compose）**，
  兩個機制各自用一組決定性時序取證：
  - **回前景立刻重連**：App 在背景時停掉後端 150 秒（退避長到 30 秒上限）→ 後端恢復並確認可服務
    → **等 20 秒，後端零 WS 連線**（證明背景中的重連鏈確實沒動）→ 回前景 `08:58:27`
    → **`08:58:28` WebSocket 已連線**（約 1 秒），同秒帶出 `rides/active` 與協尋清單查詢。
  - **漏掉的事件由 REST 補回**：司機上線→乘客叫車→App 接單（ride #10 行程卡）→按 HOME →
    重啟後端切斷 WS → **`09:01:02` 乘客取消訂單（當下司機 WS 不存在，事件送給沒有人）** →
    `09:01:04` App 在背景重連上 WS（**重連不會補送漏掉的事件**）→ `09:01:08` 回前景 →
    `SELECT rides WHERE driver_id=7 AND status IN (2,3)` **rows:0** →
    **行程卡消失、回到「等待派單中」**。修正前這張卡會一直留著，直到司機按下操作被 409 打回。
- **旁見（不是本批引入，記著別下次又追一遍）**：後端在那次「離線 3 分鐘＋process freeze」的極端情境
  留下 **3 筆 WebSocket 已連線**，但同時間裝置端 `/proc/net/tcp` 只有 **1 條 ESTABLISHED**——
  多的是握手在凍結期間才完成、之後就死掉的殭屍 socket（`_closeQuietly` 逾時 2 秒後就放手，
  既有行為）。客戶端沒有連線 churn。

---

## 🎫 2026-07-29 第五輪 debug：搶單／多裝置——App 對「接單失敗」一無所知（本批修掉）

> 「下一輪 debug 角落 2：多裝置／同帳號重複登入」。照待辦說的**先確認後端行為**，
> 結果查出來的東西比原本的題目大得多。

**後端實際行為（用兩位司機＋同帳號兩條 WS 對真後端跑過，payload 逐則印出來看）**：

| 查證 | 結果 |
|---|---|
| 同一個 driver id 的多條 WS 連線 | **全部都收到** `ride.assigned` 與 `ride.accepted`（`events.Hub` 依 (角色, id) 扇出，沒有踢舊 session 的機制） |
| 一張單派給幾位司機 | **同一輪同時派給半徑內每一位待命司機**（`dispatchRound` 迴圈 `pushOffer`）——搶單是常態，不是邊角 |
| 沒搶到的司機收到什麼事件 | **零**。`ride.accepted` 只送給接到的那位；逾時取消（`giveUpIfUnaccepted`）也只通知乘客 |
| 沒搶到的司機打 accept | **HTTP 200** `{"message":"手慢了，這單已被其他司機接走"}`——後端用 200＋文案表示失敗（**2026-07-30 後端已改成 409**，見下方回填） |
| 非待命狀態打 accept | 同樣是 200 `{"message":"您目前無法接單（非待命狀態）"}`（同上，已改 409） |
| 放棄非「已接」狀態的單 | 同樣是 200 `{"message":"此訂單目前無法放棄"}` |

**因此 App 有一個一直都在的謊**（`acceptOffer` 只看有沒有丟例外）：
沒搶到的司機按下接單後，App 會給他一張**完整但假的行程卡**——上車點、導航、乘客已上車、
放棄此單全都在——他會開車去接一個不存在的乘客，直到按下某個操作被 409 擋下才發現。
`_refreshActiveAfterAccept` 明明重讀了 `rides/active`（回 null），卻因為舊契約
「回 null 就保留樂觀行程」而把假單留著。那條契約寫的理由是「active API 對剛接的單短暫回 null」，
**實測推翻**：接單成功時後端在回應前就寫好 ride，讀不到就是真的沒有。

**改了什麼**（都在 App 端，不需要動後端）：
- **接單以後端的 active 為權威判成敗**（不 parse 文案，文案只拿來顯示）：
  回同一張單 → 成立（缺的欄位用樂觀 offer 補，見 `ActiveRide.filledFrom`）；
  回 null → 沒接到，清掉樂觀行程與接單卡並顯示後端那句話；
  回別張單 → 沒接到，但顯示**後端說的那一張**；
  重讀本身失敗（網路）→ 不知道就不亂改，維持樂觀（回前景會校正）。
- **放棄此單同一套**：後端拒絕（200＋文案）時把行程卡放回去並說明，不再讓司機以為已脫手。
- **`ride.accepted` 收掉同一張單的接單卡**——這就是多裝置的正解：事件後端本來就送了，
  是 App 在 `_activeRide == null` 時忽略它。收掉之後再跟後端要一次進行中行程，
  兩台裝置就看到同一張行程卡（只收卡片會顯示「等待派單中」，那是另一種說謊）。
- **「略過」要通知後端**（`POST /rides/:id/decline`，端點早就在、App 從沒呼叫過）：
  後端把司機加進該單的已拒接名單，重派時跳過他；否則同一張單重派還會再送到他面前。
  失敗靜默（附帶動作不該卡住畫面）。

**驗收**：
- 靜態：`flutter analyze` 無 issue、`flutter test` **259 passed**（原 249＋新 10）。
  新增 `test/driver_offer_race_test.dart`；既有 `driver_controller_test` 的舊契約那案改寫成
  「回別張單 → 以後端為準」，其 fake 也改成模仿真後端（接單成功後 active 就有這張單）。
  **反向確認**：拿掉四項修正後對應的 4 案 FAIL。
- **✅ 模擬器實跑閉環（2026-07-29，`m6_pixel` driver flavor ＋ dispatch docker compose）**：
  | 情境 | 真機結果 |
  |---|---|
  | 搶輸別人（ride #12，另一位司機先接走） | 按接單 → **沒有行程卡**，粉紅橫幅「手慢了，這單已被其他司機接走」，hero 回到「等待派單中」（修正前會顯示完整的假行程卡） |
  | 同帳號另一台裝置接走（ride #13，用同一個司機 token 打 API） | App 的全螢幕接單卡**自動消失**，並自動帶出**真的行程 #13**（地圖＋操作鈕），使用者在這台什麼都沒按 |
  | 略過（ride #14） | 後端 log `司機拒單 driver_id=7 ride_id=14`＋Redis 出現 `ride:14:rejected`（修正前後端完全不知情） |

**➡️ 留給後端的（跨 repo，不在本批）**：
1. ~~**接單／放棄失敗回 200＋文案**是 API 設計缺陷~~ ✅ **後端已修（2026-07-30，
   dispatch [PR #64](https://github.com/thothawei/fleet-dispatch/pull/64)）**：
   新增 `ErrRideTaken`／`ErrDriverNotIdle`／`ErrRideStarted`／`ErrRideStateChanged`
   四個 sentinel error，一律回 **409**，**文案一字未改**。
   實跑量到：重複接單 `409 {"error":"手慢了，這單已被其他司機接走"}`、
   已上車後乘客取消 `409 {"error":"行程已開始，無法取消"}`。
   **App 這端不需要改**：司機端 `acceptOffer` 會顯示後端文案、接單卡由 `ride.taken` 收掉；
   乘客端 `cancelOrder` 本來就把 `ApiException.message` 顯示出來——先前 200 時它反而什麼都不說。
   **既有的「逾時才對帳」退路留著仍然無害**（弱網逾時是 `statusCode == null`，與 409 不同條路）。
2. **沒搶到的司機收不到任何事件**：後端可對「本輪收到 offer 但沒接到」的司機補送
   `ride.taken`（或把 `ride.assigned` 的 payload 加上 `offer_expires_at`），
   App 才能在司機**完全沒動作**時也把卡片收掉。目前只有他按下接單、或
   `ride.cancelled`／`ride.completed` 剛好帶到同一個 rideId 時才收得掉。
3. 逾時取消（`giveUpIfUnaccepted`）也只通知乘客，司機端同上。

---

## 📶 2026-07-29 第六輪 debug：弱網（連得上但通不了）——本批修掉

> 「下一輪 debug 角落 3」。弱網比整條斷線難處理：**TCP 還活著**，所以 WS 不會收到 FIN、
> `isConnected` 是真的、畫面上的「即時連線正常」也沒說謊——但東西就是進不來也出不去。
>
> **量測手法**：`adb emu network delay/speed` 對 `10.0.2.2` 這條 host loopback **沒有作用**
> （實測套用後請求照樣秒回），改用 **`docker pause` 凍結後端** ——連得上、不回應，
> 正是弱網的逾時分支。下次要再驗用這招，不要再花時間在模擬器限速上。

**實跑量到的三件事（修正前）**：

| 觀察 | 數字／畫面 |
|---|---|
| 逾時文案 | 「請求逾時，請稍後再試」**第一次在真裝置上驗到**（先前只有單元測試層） |
| 請求堆積 | 同時連線數 **1 → 3**：位置每 8 秒一個 tick，但單筆最久要 25 秒（連線 10＋接收 15），沒有任何併發保護 |
| 畫面說謊 | hero 照樣顯示「上線中／**等待派單中**」＋「即時連線正常」——可是後端的 `NearbyDriverIDs` 只收 `updated_at` 在 `DRIVER_OFFLINE_SEC`（預設 60 秒）內的司機，**他早就不是派單候選了** |

**改了什麼**：
- **位置回報一次只放一筆在路上**（`_reportingPosition`）。被擋下的 tick **直接丟掉不補送**——
  下一個 tick 送的是更新的座標，回報位置只在乎最後一筆；堆著送反而可能讓舊座標後到，
  把司機在派單池裡的位置往回拉。
- **hero 誠實降級**：`locationStale`（超過 `AppConfig.driverOfflineSec` 沒成功回報）→
  紅底 `cloud_off`「位置回報失敗，暫時收不到派單」。門檻**取自後端的 `DRIVER_OFFLINE_SEC`**，
  不是自己編一個數字（後端調整時 `AppConfig` 要跟著改，已註明）。
- **接單逾時 → 跟後端對帳**（`_adoptRideIfAccepted`）：逾時不代表後端沒接到，
  請求可能已處理、只是回應沒回來。不對帳的話司機會再按一次，然後拿到
  「手慢了，這單已被其他司機接走」——**他自己搶走自己的單**。
- **乘客建單逾時 → 跟後端對帳**（`_handleCreateFailure`）：同一個機制，但後果更嚴重——
  沒有進行中訂單就不會啟動輪詢，**車已經在派了乘客卻停在叫車畫面**；再按一次會撞
  「已有進行中的訂單」這條死路。**只有連線類（`statusCode == null`）才對帳**：
  後端明確拒絕（限流、車種不合）時它本來就沒建單。

**驗收**：
- 靜態：`flutter analyze` 無 issue、`flutter test` **268 passed**（原 259＋新 9）。
  新增 `test/weak_network_test.dart`。**反向確認**：拿掉四項修正後對應案例 FAIL
  （併發保護 1、hero 降級 1、接單對帳 1、建單對帳 1）。
- **✅ 模擬器實跑（`m6_pixel` driver flavor ＋ dispatch docker compose，後端 `docker pause`）**：
  | 檢查 | 結果 |
  |---|---|
  | 請求堆積 | 修正後 72 秒內同時連線數**穩定在 2**（WS ＋ 最多一筆 REST），修正前為 3 |
  | hero 降級 | 凍結約 60 秒後轉紅底「位置回報失敗，暫時收不到派單」＋「請求逾時，請稍後再試」 |
  | 自動恢復 | 解凍後約 10 秒內 hero 回綠「等待派單中」，逾時橫幅被位置探針清掉（不需手動操作） |
  | 接單逾時（**負向**分支） | 後端確實沒接到（`driver_id=None`）→ App **不誤判**、接單卡留著讓他再按；再按時後端回 200 文案，App 也沒給假行程卡（PR #63 的防線同時生效） |
- **沒能在真裝置上驗到的**（誠實記錄）：接單／建單逾時的**正向**分支
  （後端其實成功、只是回應遺失）。`docker pause` 造不出這個競態——dio 逾時會關掉連線，
  凍結中的後端根本沒讀到那個請求，解凍後也不會處理。這條分支目前由單元測試
  ＋反向確認覆蓋；要在真裝置驗需要一支「轉發請求但吃掉回應」的代理。

---

## 🧾 2026-07-29 PR 佇列稽核：兩條 stack 做了同一件事（本批清掉）

> 這一輪的起點不是程式碼，是**盤點三個 repo 的實際狀態**：
> app **6 支 open PR（#59–#64）**、dispatch **2 支（#53／#54）**、admin **0 支**。
> 全部 CI 綠（#59 為 BLOCKED）。也就是說，「還有什麼可以補強」的答案當下不是再寫新功能，
> **是這些做完的東西沒有進 main**。

### 查出來的問題：兩條平行 stack 撞在一起

| stack | PR | 內容 |
|---|---|---|
| A | #59 → #60 → #61 | 回前景對帳／接單建單對帳／司機多裝置 |
| B | #62 → #63 → #64 | 回前景對帳／搶單假行程卡／弱網 |

**#59 與 #62 是同一個功能的兩份獨立實作**——連新檔名都一樣
（`lib/shared/widgets/app_lifecycle_reactor.dart`），由兩個平行 worktree 的 session
在兩小時內各做了一次；往上疊的 #60/#61 與 #63/#64 也大量重疊（接單結果對帳、
`ride.accepted` 的多裝置處理）。兩條都合會直接衝突。

**決策**：保留較新且較完整的 B 條（#62→#63→#64 全數合併），
關閉 A 條，但**先把 A 條獨有的三項救回來**（本 PR）——這正是
[清開發殘留](#-清開發殘留-worktree舊分支維護項-52026-07-28-完成) 那次學到的：
「看起來被取代」不等於「內容都在」，要逐條比對 diff。

### A 條獨有、已救回的三項

| 救自 | 修正 | 為什麼 B 條沒有 |
|---|---|---|
| #59 | **WS 客戶端心跳**（`pingInterval` 20 秒） | B 條只做了「回前景立刻重連」，但半開連線（對端沒了、本地收不到 FIN）**不會 onDone／onError**，重連鏈根本不會啟動；後端只做了另一半（54 秒 ping、60 秒沒 pong 砍連線），保護的是伺服器不留死連線 |
| #60 | **建單 409 也去對帳** ＋ 接手時共用建單成功的狀態切換 | B 條的 #64 只對帳連線類（`statusCode == null`），409 只顯示訊息；但 409 正是「後端說你有單、你的畫面沒有」，再按一次還是 409，出路只剩重開 App。接手時原本也只做 `_applyActiveRide`，編輯中的多乘客清單／預估會留到下一趟 |
| #61 | **司機端處理 `ride.stop_updated`** | B 條的 #63 收掉了 `ride.accepted` 的多裝置缺口，但停靠點沒有；兩台裝置會停在不同的「下一站」，而那是司機端唯一給操作鈕的一站。後端側同批合併 dispatch#53（該事件原本只推給乘客） |

**驗收**：`flutter analyze` 無 issue、`flutter test` **277 passed**（268 ＋新 9）。
新增 `driver_stop_updated_test.dart`（3）、`customer_create_conflict_test.dart`（4）、
`fleet_ws_client_test.dart` 兩案（心跳）。**反向確認**：拿掉 `ride.stop_updated`
處理後 1 案 FAIL、拿掉 409 分支後 2 案 FAIL；心跳那案先斷言預設 `pingInterval` 為 null
再斷言設定後的值，避免寫出恆真的斷言。
**✅ 模擬器實跑閉環（2026-07-29 同日補做，`m6_pixel` 雙 flavor ＋ dispatch docker compose，全程截圖）**——
原本這三項只有單元測試，當天稍後補跑，**兩項閉環、一項確認無法在這層驗**：

- **司機端跨裝置停靠點同步 ✅**（救自 #61 ＋ dispatch#53）：
  司機 `sim29drv`（driver 10）登入→上線（**Redis `drivers:geo` 含 10、`driver:10:loc` 存在
  ＝真的在派單池**）→ 乘客以 API 建 2 乘客 4 站訂單 ride #16 → **全螢幕接單卡**
  （帶「多乘客行程（4 站）」chip）→ 接單 → 行程卡列出全程 4 站、下一站「1. 乘客 A上車」帶操作鈕。
  接著**用 API 標記 stop 7 到達（＝第二台裝置／LINE 那條路徑）**，
  **手機全程未觸碰**：5 秒後第 1 站變綠勾「已完成」、下一站自動前移到「2. 乘客 B上車」
  並帶操作鈕、地圖上該站的紅釘轉灰、B 站變成醒目紅釘。
  修正前這台會**永遠停在第 1 站**（PR #61 實測是 8 分鐘沒動）。
- **乘客端建單 409 接手 ✅**（救自 #60）：
  乘客 `sim29cust`（customer 9）登入、**畫面上沒有任何進行中訂單**（此時 App 也不輪詢）→
  以 API 建 ride #17（＝另一台裝置／LINE）→ **立刻在 App 按「叫車」** →
  後端回 409 →**畫面直接切到「正在為您配對司機」**，不是錯誤 SnackBar。
  **交叉驗證（決定性）**：`ride_events` 裡 customer 9 的 `ride.requested` **只有兩筆
  （#16、#17，都是 curl 建的）**——App 那次按下**沒有產生任何新訂單**，
  且 `GET /customer/rides` 回 `[(17,1),(16,9)]` 沒有第三張單。
  接手的 ride #17 的 `pickup_address` 是「API建的上車點」，**不是 App 表單裡的值**，
  證明畫面上的行程來自後端而非本地樂觀狀態。
  （這條路徑不可能來自別的機制：無進行中訂單時輪詢是停的，而 `ride.assigned` 在
  `_activeRide == null` 時會早退。）
- **WS 心跳 ⚠️ 這層驗不到**：客戶端 ping 由 dart:io 直接送控制幀，
  gorilla 的預設 PingHandler 自動回 pong 但不寫 log，後端也沒有可觀察的計數器；
  要證明只能封包擷取。**維持單元測試層的證據**（在真 socket 上斷言
  `pingInterval` 從 null 變成 20 秒），半開連線的實機重現需要斷網卡層級的手法。

### 兩個 GitHub 操作坑（下次做 stacked PR 一定會再踩）

1. **`--delete-branch` 會連帶關閉以該分支為 base 的 PR**。合併 #62 並刪分支的當下，
   #63／#64 立刻被 GitHub 關掉，而且**重開會被拒**（`Cannot reopen`／
   `Cannot change the base branch of a closed pull request`）——只能 rebase 後另開新 PR
   （#63 → **#65**）。之後改用「**合併時不刪分支** → 把下一支 rebase 到 main →
   `gh pr edit --base main` → 再刪舊分支」，#64 的編號就保住了。
2. **CI 不會跑，因為 workflow 的 `pull_request: branches: [main]` 是 base 過濾器**。
   stacked PR 的 base 不是 main 時，push 不觸發 CI；把 base 改成 main 也不補觸發
   （`edited` 不在預設 types 裡）。要 `gh pr close` 再 `gh pr reopen` 才會跑。

### 第二輪比對：被取代的 PR 還藏著四條 main 沒有的測試（PR #69）

> 功能救回之後又做了一次**逐檔**比對（`git diff --diff-filter=A` 找只存在於那三支的檔案），
> 結果撈到兩個檔：`customer_place_order_timeout_test.dart`（#60）與
> `driver_multi_device_test.dart`（#61）。程式碼本身 main 都已經是對的，
> **缺的是釘住它的測試**——少了它們，下一個人重構 `_adoptRideIfCreated` 時會靜悄悄壞掉。

| 救回的斷言 | 壞掉會怎樣 |
|---|---|
| 接手既有訂單時**連司機資訊一起帶出來** | 乘客先看到一段假的「配對中」，直到 15 秒後輪詢才冒出司機——而司機可能已經在門口 |
| **對帳本身也失敗**時維持原錯誤 | 問不到卻假裝接手成功 |
| 後端回的是**終態**訂單 → 不算數 | 把已完成的上一趟接手過來，乘客盯著一張永遠不會動的行程 |
| **登出後 `ensureConnected()` 不可偷偷連回去**（救自 #59） | 已登出的 client 帶著**舊 token** 重連，上一個帳號的事件繼續進來 |

**反向確認的誠實結果**：前三案拿掉 `_applyActiveRide` 與 `isTerminal` 後 **2 案 FAIL**
（「對帳失敗」那案由既有 `catch` 覆蓋，拿不掉也不會紅）；第四案是 **defense-in-depth**——
`ensureConnected()` 與 `_open()` **各有一道** `_disposed` 守門，單獨拿掉任一道都仍 PASS，
**兩道同時拿掉才 FAIL**。這種案子仍值得留，但不能宣稱它釘住了某一行。

`flutter test` **281 passed**。至此 #59／#60／#61 的內容（功能＋測試）**全部在 main**，
三支遠端分支已刪除。

### 順手做的整理

- dispatch：#53（`ride.stop_updated` 也推給司機）、#54（結構化 JSON log ＋ request_id）已合併，
  遠端分支清空（只剩 main）；另補 **#55** 把 App 實跑查出的四個後端缺口記進後端自己的 TODO（T1–T4）。
- app 遠端殘留分支 `claude/todo-task-execution-pr-3978a3` 經比對 **tip 等於 PR #58 合併時的
  `headRefOid`**（沒有未合併內容），已刪除。
- 從本地 worktree 撈到一個**從未開過 PR** 的孤兒 commit（UI/UX 翻新計畫的 30 個 Step 回填），
  逐檔重新查證產出存在後補開 PR **#67** 合併。
- **app 遠端分支現在只剩 `main`**；三個 repo 的 open PR 皆為 0。

---

## 🧭 2026-07-29 第七輪 debug：把「WS-only state」整族掃一遍（本批修掉 1 個）

> 這個家族已經咬過三次（O7 司機電話只走 `ride.accepted`、遺失物 banner 只在卡片版、
> token 過期無人處理），所以這次**不等它再咬**：把兩個 controller 的 `_handleWsEvent`
> 會寫入的欄位全部列出來，逐一問「錯過這則事件之後，有沒有 REST 路徑把它補回來」。

**乘客端（15 個欄位）**：

| 欄位 | 錯過事件後 | 判定 |
|---|---|---|
| `_activeRide`／`_lastActiveRide`／`_driverName`／`_driverInfo`／`_driverArrived` | `_applyActiveRide` 由 `GET active` 全部補齊 | ✅ 有還原 |
| `_lostItems` | `refreshLostItems()`（登入、init、回前景、下拉） | ✅ 有還原 |
| `_liveEtaSec`／`_liveDistM`／`_liveDriverLat`／`_liveDriverLng` | 沒有 REST 來源，但司機每 8 秒回報一次位置 → **下一則 `driver.location` 就自癒** | ⚠️ 可接受 |
| `_cancelReason`／`_rideCancelled`／`_cancelledVehicleType`／`_redispatchNotice` | 都是「一次性通知」，錯過就沒有；行程本身的結局仍看得到（歷史清單） | ⚠️ 可接受 |
| **`_completedSummary`** | **完全沒有 REST 還原** → 完成卡永遠不再出現 | 🐛 **本批修掉** |

- [x] 🐛 **行程完成後重開 App 就再也報不了遺失物**（app PR #71）。
      完成卡的「物品遺失？聯絡司機」是**唯一**能建立協尋單的入口
      （`grep -rn 'CustomerLostItemScreen('` 全 App 只有兩處：完成卡與首頁 banner，
      而 banner **只顯示已存在的單子**）。`_completedSummary` 只由 WS `ride.completed` 設定，
      按「再叫一輛」、重開 App、或完成當下 App 在背景／WS 斷線，那顆按鈕就永遠不再出現——
      **而東西通常是下車以後才發現不見的**，正好都在完成卡消失之後。
      修法比照 B5 補評分：在「我的行程」給「物品遺失」入口，
      條件 `canReportLostItem` ＝已完成 ＋ 有司機（與後端 `CreateByCustomer` 同一組）。
      驗收：`flutter test` **285 passed**（新 4）、反向確認拿掉入口 1 案 FAIL。
      **未做**：沒有模擬器實跑（該輪 docker／模擬器已關），風險集中在按鈕出現條件，
      已由 widget 測試釘住。

**司機端（3 個欄位）**：`_activeRide`（`GET driver/rides/active` ✅）、
`_pendingOffer`（**WS-only，但後端沒有「目前 offer」端點**——錯過就等下一輪派單，
App 端補不了；已記在 dispatch TODO 的 T2）、`_loading`（純 UI 旗標）。

**兩端共通的小缺口（不修，記著）**：`_unreadChat` 是 WS-only 計數器，
重開 App 一律歸零——即使真的有未讀。訊息本身由 REST 歷史載得回來，
少的只是角標數字。要修得靠後端提供「未讀數」或 last-read 游標，**代價高於症狀**。

---

## 📡 2026-07-29 第八輪 debug：事件收件人矩陣——App 寫好的處理，後端從沒送過（本批修掉 2 個）

> 承上一輪的反向問題。上一輪問「**App 收到事件後有沒有還原路徑**」；
> 這一輪問「**這則事件到底有沒有送到這一端**」。
> 方法：把後端 13 個事件型別的**實際收件人**列成矩陣（逐一看 `s.publish(...)` 的 `Recipient`），
> 再對照 App 兩端的 handler 清單。

| 事件 | → 乘客 | → 司機 | App 端 handler |
|---|---|---|---|
| `ride.assigned` | – | ✅ | 司機 ✅（刻意不給乘客） |
| `ride.accepted` | ✅ | ✅ | 兩端 ✅ |
| `ride.completed` | ✅ | ✅ | 兩端 ✅ |
| `ride.stop_updated` | ✅ | ✅（dispatch#53） | 兩端 ✅ |
| `driver.location` | ✅ | – | 乘客 ✅（刻意不給司機） |
| **`ride.cancelled`** | ✅ | ❌ **從沒送過** | 司機**早就寫好了**——死碼 |
| **`ride.picked_up`** | ✅ | ❌ | 司機**早就寫好了**——死碼 |
| `ride.redispatched` | ✅ | ❌ | 乘客 ✅（司機側見下） |
| `driver.arrived` | ✅ | ❌ | 司機端無此階段，不需要 |

**共同形狀**：不是 App 漏接，是**後端從沒送**，而 App 那段處理一直是死碼——
只讀 App 或只讀後端都看不出來，要把兩邊擺在一起才會現形。

- [x] 🐛 **乘客取消已接的訂單，司機 App 完全不知道**（dispatch PR #56 ＋ app PR #72）。
      `cancelActiveRide` 的「通知司機」只有 `line.PushText`。司機端**沒有任何輪詢**
      （`grep -n "Timer.periodic" driver_controller.dart` 零命中），所以行程卡永遠留著——
      **他會繼續開往上車點接一個已經取消的乘客**，而後端在取消當下就已 `releaseAndReset`
      把他放回 Idle，畫面與真實狀態完全相反，期間甚至可能同時收到新派單。
      要按下「乘客已上車」被擋下才會發現。
      這是 **dispatch#52（司機放棄只推 LINE、App 乘客收不到）在司機側的鏡像**——
      同一個 bug 當時只修了一邊。
      App 這側同批補上說明「這筆訂單已被取消，不用再前往上車點」——
      **收到這則事件一定是別人取消的**（他自己放棄走 `ride.redispatched`，且不推給司機），
      所以說得出原因；`ride.completed` 則不說（那是他自己按的）。
- [x] 🐛 **「乘客已上車」只推乘客**（dispatch PR #57）。司機第二台裝置／LINE 標記後，
      這台停在「前往上車點」階段：按鈕仍是「乘客已上車」（按下去被後端拒絕），
      而「放棄此單」這時也已不可用（後端只接受 `Accepted`）。

- [x] 🐛 **沒搶到的司機，接單卡永遠不會自己消失**（dispatch PR #59 ＋ app PR #74）。
      一輪派單**同時**推給半徑內每一位待命司機，只有一位搶得到；先前 `ride.accepted`
      只送給接到的那位，逾時取消也只通知乘客——沒搶到的人要**自己按下去**拿到
      「手慢了，這單已被其他司機接走」才會消失，期間那張全螢幕卡蓋著整個畫面，
      新派單來了也只是再疊一張。**每一趟車都會發生在所有沒搶到的司機身上**，
      這是本輪影響面最廣的一個。
      根因在後端：`dispatchRound` 的 `offered` 只是遞迴中的記憶體 map，接單／取消流程拿不到。
      後端補 Redis `ride:<id>:offered` 集合並新增 **`ride.taken`** 事件（取消時則送
      `ride.cancelled` 給所有收過 offer 的人）；App 收到就把接單卡收掉，
      **不寫錯誤訊息**——他什麼都沒做，安靜收掉才對（對比按下接單後才該看到的「手慢了」）。

**驗收**：dispatch 三支各自新增真 PostGIS（＋Redis）測試（含「未派單的訂單不推給司機」
與「接到單的那位不該收到 ride.taken」的負向對照），反向確認拿掉 publish 後對應案 FAIL；
app `flutter test` **291 passed**（285 ＋新 6）。
**未做**：以上都沒有模擬器實跑（本輪 docker／模擬器已關閉）。

---

## 🔬 2026-07-29 第九輪盤點：下一輪的三個候選（**本批只盤點、沒有修**）

> 前八輪的候選清單（App 生命週期／多裝置／弱網）已經清空，本檔原本只留下一句
> 「再往下的 debug 題目要重新盤點」。這批就是那次重新盤點。
>
> **本批沒有改任何 `lib/` 程式碼**，產出就是下面三條候選。每條都附**當場跑過的指令**，
> 讓下一次開工的人不必從零盤一次；但三條**都只讀碼查證、沒有實跑**，
> 動手前請先照各自的「怎麼證實」復現一次再修——
> 本檔的規則是「沒實跑就要講出來」，這裡照做。

### 候選 1：乘客端完全沒有推播管道，**而後端的端點已經在那裡等**

**證據**（2026-07-29 實跑）：

```
grep -rn "firebase\|Firebase\|device-token\|PushService" \
     lib/customer/ lib/main_customer.dart lib/core/api/customer_api_client.dart | wc -l
→ 0

grep -rn "device-token" ~/Documents/line-fleet-dispatch --include=*.go
→ cmd/server/main.go:251  customerAuthed.POST("/customer/device-token", …RegisterByCustomer)
  cmd/server/main.go:252  customerAuthed.DELETE(…, …UnregisterByCustomer)
  cmd/server/main.go:272  authed.POST("/driver/device-token", …RegisterByDriver)
```

**機制**：司機端有整套 `DriverPushService` ＋ `POST /driver/device-token`（A2），
乘客端**一行都沒有**。後端的 `RegisterByCustomer`／`UnregisterByCustomer` 早就掛在路由上，
App 從沒呼叫過——又一個「後端做好、App 沒接」的缺口（同 O7 司機電話那一族，
只是這次反過來是 App 缺席）。

**後果**：乘客 App 被系統殺掉或使用者滑掉之後，**沒有任何通道叫得動他**——
WS 沒了、15 秒輪詢也停了，「司機接單」「司機已抵達」「行程完成」全部收不到，
只有他自己再打開 App 才由 REST 還原。而「司機到了」正是最需要即時通知的那一則。

⚠️ **這條同時推翻本檔原本列的一個題目**：「乘客端在 App 被系統殺掉後、從推播喚醒的還原路徑」——
**沒有推播就沒有喚醒**，那題的前提不成立。正確的題目是先把乘客端推播接起來。

**前置條件**：與 A2 相同（Firebase 專案＋`google-services.json`），所以**同樣卡在外部資源**。
但可以先做不需要憑證的那一半：device-token 的註冊／註銷接線與登出清理
（司機端 `_syncDeviceToken`／`unregisterDeviceToken` 是現成範本，含「session 失效時不要再打那支 API」的既有教訓），
推播內容的實機驗收再等憑證到位。

### 候選 2：聊天室的「WS 斷線保底」是**死路徑**

**證據**（2026-07-29 實跑）：

```
grep -rn "_loadHistory" lib/shared/screens/ride_chat_screen.dart
→ :54  initState 呼叫
  :66  定義
  :148 錯誤橫幅的「重試」按鈕

grep -rn "onAppResumed" -A 8 lib/driver/driver_controller.dart lib/customer/customer_controller.dart
→ 兩端都只有 ensureConnected() ＋ 對帳 active ＋ refreshLostItems，不碰聊天
```

**機制**：`ride_chat_screen.dart` 檔頭寫著「歷史：進場以 REST 載入，之後以 afterId 增量補讀
（WS 斷線重連保底）」，但那個增量補讀**沒有任何觸發點**——唯一呼叫它的 `initState` 那次
`_messages` 還是空的（`afterId = 0`，等於全量載入）。所以聊天室開著的期間，訊息**只靠 WS**；
而第四輪已經查證過「**重連不會補送漏掉的事件**」。

**後果**：切背景／WS 斷線期間對方送的訊息，回前景後**不會出現**，畫面停在舊訊息；
而且**連未讀角標都不會亮**——`setChatVisible(true)` 期間本來就不累計未讀。
使用者要離開聊天室再進來才看得到。

這是「**WS-only state**」家族的**第四個實例**（前三個：O7 司機電話只走 `ride.accepted`、
遺失物 banner 只在卡片版、`_completedSummary` 沒有 REST 還原）。
第七輪那次掃的是兩個 controller 的欄位，**沒掃畫面自己持有的本地狀態**——
下次做這類全族掃描，範圍要包含 `StatefulWidget` 的 `State`。

**怎麼證實**：兩端同時開同一張單的聊天室 → 一端按 HOME（或 `docker pause` 後端）→
另一端送兩則 → 回前景 → 看這台是否仍停在舊訊息、角標是否仍為 0。

**修法方向**：`RideChatScreen` 在 resume 時呼叫**既有的** `_loadHistory()`
（`afterId` 機制本來就寫好了，缺的只是觸發點）。可沿用已有的 `AppLifecycleReactor`
或就地 `WidgetsBindingObserver`；注意本檔第四輪的教訓——**`inactive` 不算回前景**
（通知列下拉、來電橫幅都會觸發它）。

### 候選 3：司機端**三條寫入路徑沒有逾時對帳**（第六輪只補了兩條）

第六輪替**接單**（`_adoptRideIfAccepted`）與**乘客建單**（`_handleCreateFailure`）補了
「連線類失敗 → 跟後端對帳」，理由是**逾時不代表後端沒收到**。同一個理由適用於下面三條，
但它們目前失敗時只做 `_setApiError`：

| 路徑 | 位置 | 逾時後畫面停在 | 司機再按一次 |
|---|---|---|---|
| `completeTrip` | `lib/driver/driver_controller.dart:697` | 行程卡留著（以為沒完成） | 後端已 completed → 被拒 |
| `pickUpPassenger` | `lib/driver/driver_controller.dart:677` | 「前往上車點」 | 後端已 on_trip → 被拒 |
| `_markStop` | `lib/driver/driver_controller.dart:136` | 下一站不前進 | 重複標記 409 |

**自癒路徑存在但不可靠**：`ride.completed`／`ride.stop_updated` 兩端都有 handler，
但**會讓請求逾時的網路，通常連 WS 也一起不通**，而重連不補送漏掉的事件（第四輪查證）。
真正兜得住的是切背景再回前景的 `onAppResumed → _restoreActiveRide`——
**使用者不會知道要這樣做**。

⚠️ **三條的嚴重度差很多，別一視同仁**：`completeTrip` 卡住 ＝ 司機以為這趟沒結束，
可能重按或不敢載下一位（且後端那邊車資已定格）；`_markStop` 只是下一站晚幾秒前進，
WS 一回來就對得上。**要做就先做 `completeTrip`**。

**怎麼證實**：`docker pause` 凍結後端（第六輪的手法，**模擬器限速對 `10.0.2.2` 無效**）→
按下該動作 → 等逾時 → 解凍 → 看畫面是否仍停在舊階段、再按一次是否被 409 擋下。

### 順手查證、**不是 bug** 的三件事（記著免得下次重查）

- `flutter analyze` 無 issue、`flutter test` **291 passed**（40 個測試檔）——
  與第八輪回填的數字一致，本檔沒有虛報。
- **open PR 為 0、app 遠端分支只剩 `main`**（`gh pr list` ／ `git ls-remote --heads origin`）——
  PR 佇列稽核那次清完之後沒有再長出來。
- **A2／A5 的前置條件今日重查仍未到位**：`android/app/google-services.json` 不存在、
  `ios/Runner/GoogleService-Info.plist` 不存在、`xcrun devicectl list devices` → `No devices found`。
  （2026-07-28 查過一次，這是第二次；**這兩條每次開工都值得重跑，因為它們是外部資源，
  隨時可能到位而沒有人會來通知**。）

> **➡️ 三條候選都動了**：2、3 見 [第十輪](#-2026-07-29-第十輪-debug把第九輪的候選-23-修掉本批)，
> 候選 1 的**接線那半**見 [第十一輪](#-2026-07-29-第十一輪乘客端推播接線候選-1-的前半)——
> 剩下的是 Firebase 憑證（同 A2）**與後端還沒有推播給乘客的送出路徑**。

### 維護項 8：又冒出一個殘留 worktree

`git worktree list` 目前有 `.claude/worktrees/fleet-improvements-todo-cc8d85`
（分支 `claude/e2e-salvaged-fixes`）。判定依據**照維護項 5 那套**，不靠 commit message：

- `git log main..claude/e2e-salvaged-fixes` → **空**（沒有 main 沒有的 commit）；
- `git diff --stat main..claude/e2e-salvaged-fixes` → 全是刪除（＝分支落後 main，不是有新東西）；
- 該 worktree `git status --short` → **乾淨**（沒有未提交的改動會被一起丟掉）。

三條都成立 ＝ 內容全在 main，可直接 `git worktree remove` ＋ 刪分支。
**刪之前先確認沒有 session 正在用它**（本檔 PR 佇列稽核那次的教訓：平行 worktree 的 session 彼此看不見）。

---

## 🔧 2026-07-29 第十輪 debug：把第九輪的候選 2、3 修掉（本批）

> 第九輪只盤點不修，這一輪把**兩條不需要外部資源**的補上。
> 候選 1（乘客端推播）仍卡在 Firebase 憑證，維持待辦。
> **兩項都只有單元／widget 測試，沒有模擬器實跑**（本輪 docker／模擬器未起）——
> 下面各自寫了「要實跑的話怎麼證實」。

### 1. 聊天室回前景補讀（候選 2）

**根因一句話**：`_loadHistory` 的 afterId 增量補讀**沒有觸發點**，
唯一呼叫它的 `initState` 那次 `_messages` 還是空的（afterId=0 ＝ 全量），
所以檔頭註解寫的「WS 斷線重連保底」從來沒有真的保底過。

**改法**：`RideChatScreen.build` 外面包一層**既有的** `AppLifecycleReactor`
（app root 已經在用同一支），回前景時呼叫既有的 `_loadHistory()`。
沒有新增任何補讀機制——缺的自始至終只是那個觸發點。

**兩個刻意的細節**：
- **回前景那次補讀失敗要靜默**（`_loadHistory({silent})`）：使用者只是把 App 切回來、
  沒按任何東西，失敗不該冒錯誤橫幅——這正是 2026-07-28 修掉的「背景動作汙染錯誤出口」那一族，
  不能一邊修好一邊又種一個。使用者自己按「重試」時照舊顯示原因。
- **`inactive` 不算回前景**：通知列下拉、來電橫幅都會觸發它而連線並沒有斷；
  沿用 `AppLifecycleReactor` 就自動有這個判斷（第四輪已經踩過）。

### 2. 三條寫入路徑的逾時對帳（候選 3）

新增共用的 `_reconcileAfterTimeout(rideId, {applied})`，在**連線類失敗**
（`statusCode == null` ＝ 沒收到 HTTP 回應）時跟後端要一次進行中行程當權威：

| 後端的回答 | 做什麼 |
|---|---|
| 沒有進行中行程 | 清掉行程卡與逾時訊息（完成／被取消都算，這張單已不在他手上） |
| 同一張單 | 以後端為準（`filledFrom` 補樂觀值）；`applied` 說寫入生效了才清訊息 |
| 別張單 | 也以後端為準，他要操作的那張已經不在了 |
| **這一問也失敗** | **不知道就不亂改**，畫面與訊息維持原狀（回前景時還會再對帳一次） |

三條各自的「生效判準」不同，所以用 `applied` 傳進去，而不是在 helper 裡猜：
`completeTrip` ＝ 後端已無進行中行程（null 分支就夠，不需要 `applied`）、
`pickUpPassenger` ＝ 階段已進到 `onTrip`、`_markStop` ＝ 那一站已不是待處理。

**為什麼非做不可**：逾時 ≠ 後端沒收到。畫面停在舊階段的話司機會再按一次，
然後被後端 409 擋下——**他自己擋自己**。其中 `completeTrip` 最嚴重：
後端車資已定格，他卻以為這趟沒結束。
**`statusCode != null` 一律不對帳**（例如 409）——那是後端的明確回答，再問一次沒有意義。

**驗收**：
- 靜態：`flutter analyze` 無 issue、`flutter test` **303 passed**（291 ＋新 12）。
  新增 `test/chat_resume_test.dart`（4 案：補讀且只取 afterId 之後／`inactive` 不補讀／
  補讀失敗靜默／使用者按重試仍顯示錯誤）與 `test/driver_write_timeout_test.dart`
  （8 案：三條路徑的「後端其實成功」與「後端說沒成功」各一，加上對帳本身失敗、
  409 不對帳）。
- **反向確認**（拿掉修正後跑同一組）：
  - 拿掉 `AppLifecycleReactor` 包裝 → chat 4 案中 **2 案 FAIL**；
    另 2 案（inactive、重試）本來就會過，**它們釘的是別的行為，不能當成這個修正的證據**。
  - 拿掉三處 `_reconcileAfterTimeout` 呼叫 → timeout 8 案中 **3 案 FAIL**，
    正好是每條路徑的「後端其實成功」那一案；其餘 5 案是負向守門，兩種版本都會過。
- ~~**未做：模擬器實跑**~~ ✅ **2026-07-30 補跑完畢，見下方
  [第十四輪](#-2026-07-30-第十四輪把第十輪那兩項搬到模擬器上實跑本批抓到-1-個-bug)**——
  當時寫「要在真裝置驗正向分支需要一支『轉發請求但吃掉回應』的代理」，那支代理已經寫出來了
  （[`tool/lossy_proxy.py`](../tool/lossy_proxy.py)），三條寫入路徑的正向分支全部在
  `m6_pixel` 上跑過。**實跑抓到一個測試層看不到的 bug**（幽靈錯誤橫幅）。
  ⚠️ 第六輪那條教訓仍然成立：`docker pause` **造不出**這個競態
  （dio 逾時會關掉連線，凍結中的後端根本沒讀到請求）——所以才需要那支代理。

---

## 📲 2026-07-29 第十一輪：乘客端推播接線（候選 1 的**前半**）

> 候選 1 原本整條卡在「要 Firebase 憑證」，但拆開看只有**後半**卡：
> 註冊／註銷 token、收到推播要做什麼、登出與 session 失效的處理——
> 這些都不需要任何憑證就能寫完並用測試釘住。憑證到位那天只要放進
> `google-services.json`，這條路就通了。

**先確認事實**（2026-07-29 實查）：後端 `POST/DELETE /api/customer/device-token`
（`RegisterByCustomer`／`UnregisterByCustomer`）**早就在路由上**，App 這端一行都沒有。

### 改了什麼

- **推播服務改成兩端共用**：`DriverPushService` → **`FleetPushService`**
  （檔名 `driver_push_service.dart` → `fleet_push_service.dart`），
  Firebase 實作改吃一個 `accepts` 過濾器，`createDriverPushService()`／
  `createCustomerPushService()` 兩支工廠只差在那個過濾器。
  **刻意不再抄一份**——「各抄一份」正是遺失物 banner 換版時掉了的根因。
- **乘客端關心哪些推播**（`isCustomerRidePush`）：`ride.accepted`／`driver.arrived`／
  `ride.completed`／`ride.cancelled`／`ride.redispatched`。
  **不含 `driver.location`**：司機每 8 秒回報一次，拿它當推播只會把電池與額度燒光，
  而且乘客 App 不在前景時本來也看不到地圖上的移動。
- **推播只當「去跟後端對一次帳」的訊號**（`_handlePushEvent` → `refreshActive(silent)`
  ＋`refreshLostItems()`），**payload 不直接套進畫面**：FCM data 的值全是字串又稀疏
  （見 `pitfall-fcm-data-all-strings`），直接餵進 `_handleWsEvent` 會把司機姓名／車牌／ETA
  洗成空的——**推播喚醒後的畫面反而比不開還糟**。REST 一定完整。
  司機端則相反，它必須直接用 payload 顯示接單卡（後端沒有「目前 offer」端點）。
- **登入註冊、輪替重註冊、登出註銷**：`_syncDeviceToken()` 在 `_applySession` 呼叫，
  `tokenRefresh` 也接到同一支；`logout()` 先 `unregisterDeviceToken` 再清 session——
  不註銷的話，**下一個在這台裝置登入的人會收到上一位乘客的行程通知**。
- 🔑 **session 失效（401）不可去註銷**：那支 API 只會再回一次 401（並再觸發一次清理）。
  乘客端原本 `logout()` 一支打天下，這批**拆成 `logout()`／`_clearSession()`**
  ——與司機端同一個結構，也是第三輪學到的同一條。
  ⚠️ **這個決定留下的洞已由後端補上（2026-07-30，dispatch
  [PR #65](https://github.com/thothawei/fleet-dispatch/pull/65)）**：401 不註銷 ⇒
  舊使用者的那一列會留在 `device_tokens` 裡，而 **FCM token 換人登入時不會變**，
  於是「A 的 token 過期 → B 在同一台手機登入 → A 的行程通知與**對話內容預覽**
  全送到 B 的手機」。後端改成「一支 token 只能有一位主人」（註冊時搬走別人身上的同一支），
  **App 這端維持不變仍然是安全的**。
- **註冊失敗、對帳失敗一律靜默**：兩者都是使用者沒按任何東西的背景動作
  （同 2026-07-28 修掉的那一族）。推播只是輔助管道，WS 與 15 秒輪詢照常運作。

### ⚠️ 這條路還沒通——**後端沒有推播給乘客的送出路徑**

`notify.Dispatcher` 目前**只有** `NotifyDriverRideOffer`；`grep -rn "RoleCustomer" internal/`
在 dispatch 只命中 device-token 的存取層。所以乘客的 token 現在是**存起來備用**：
App 這端該做的都做完了，真正的喚醒要等後端補送出路徑。

**➡️ 留給後端的（跨 repo，不在本批）**：
1. 行程狀態變化時，對該乘客的裝置送 FCM（`ride.accepted`／`driver.arrived`／
   `ride.completed`／`ride.cancelled`／`ride.redispatched`）。
2. **data payload 只需要 `type`（＋ `ride_id`）**——App 收到就去 REST 對帳，
   不依賴推播裡的欄位，所以這一側沒有額外契約要維護。

### 驗收

- 靜態：`flutter analyze` 無 issue、`flutter test` **312 passed**（303 ＋新 9）。
  新增 `test/customer_push_test.dart`：註冊／註銷 5 案（登入註冊＋登出註銷／
  401 不註銷／推播不可用時不打 API／註冊失敗靜默／token 輪替重註冊）、
  推播對帳 3 案（只帶 type 也能靠 REST 補齊司機姓名／對帳失敗靜默／未登入不打 API）、
  過濾器 1 案（`driver.location` 與 `ride.assigned` 都不算乘客端的）。
- **反向確認**（三組分別跑）：拿掉登入註冊＋登出註銷 → **3 案 FAIL**；
  把 session 失效改回呼叫 `logout()` → **1 案 FAIL**（它會去打那支必定 401 的 API）；
  拿掉 `_bindPushListener()` → **2 案 FAIL**。
- **未做**：真推播的端到端（**需要 `google-services.json`**，本檔 A2 的同一個卡點）。
  這批驗的是接線，不是推播本身；README 的「乘客端推播」段寫了憑證到位後要做什麼。

> **📌 2026-07-30 回填**：上面說的「留給後端的」**已經做掉了**——
> dispatch [PR #61](https://github.com/thothawei/fleet-dispatch/pull/61)
> 補上 `NotifyCustomerRideUpdate` 與五個發送點，data 也正好只帶 `type`＋`ride_id`。
> 現在缺的只剩 Firebase 憑證（A2 的同一個卡點）。

---

## 🔔 2026-07-30 第十二輪：點推播喚醒的那條路，事件在沒人聽的時候就被丟掉了（本批修掉）

> 起因：接完後端送出路徑（dispatch PR #61）後，順著問一句
> **「推播真的到得了 controller 嗎」**，才發現喚醒這條路徑從頭到尾沒有人走過。

### 根因（一句話）

`FirebaseFleetPushService` 用 `StreamController.broadcast()`，而**廣播串流在沒有訂閱者的當下
`add` 的事件會直接消失**（Dart 不緩衝）。冷啟動的順序正好是這樣：

```
main() → createXxxPushService() → initialize() → getInitialMessage() → _events.add(事件)
       → runApp() → Controller.init() → ... → rideEvents.listen(...)   ← 訂閱在這裡才發生
```

`getInitialMessage()` 是「**App 被殺 → 點通知 → 冷啟動**」唯一的取得管道，
而它在 `runApp` 之前就把事件送出去了。於是：

- **司機端**：A2 的招牌情境「App 被殺 → 點推播 → 接單卡」——**卡片永遠不會出現**。
- **乘客端**：第十一輪剛接好的「點推播 → 跟後端對帳」——**對帳永遠不會發生**。

兩端寫好的處理都在，缺的是事件本身。這是本專案第 N 次遇到同一個形狀
（「處理寫好了，訊號從沒到達」，見第八輪的事件收件人矩陣、`pitfall-ws-only-state-no-rest-restore`），
差別是這次的斷點在 **App 自己的串流層**，不是跨端契約。

### 改法

新增 `lib/core/push/pending_push_replay.dart` 的 `PendingReplaySink<T>`：沒有訂閱者時把事件
留著，第一個訂閱者上來時用 microtask 補送（`onListen` 在訂閱建立過程中被呼叫，
當下同步 `add` 不保證送得到那位訂閱者）。`FirebaseFleetPushService._events` 換成它，其餘不動。

**只留最後一則**：這些事件的用途都是「開一張卡」或「去對一次帳」，補送一整串舊事件
只會讓畫面閃過一連串過期狀態。**補送過就丟掉**——登出後重新訂閱不會再收到同一則。

### 驗收

- `flutter analyze` 無 issue、`flutter test` **317 passed**（312 ＋新 5）。
  新增 `test/pending_push_replay_test.dart`：沒人訂閱時到達要補送／補送只做一次／
  只留最後一則／已有訂閱者時照常即時送達／補送前就取消訂閱不 panic。
- **反向確認**：把 `add` 退回普通廣播行為（直接 `_controller.add`），**3 案 FAIL**。
- **未做**：真裝置端到端（同 A2，卡 `google-services.json`）。這批修的是「事件到不到得了
  訂閱者」，那是純 Dart 串流語意，不需要 Firebase 就能釘住。

---

## 💬 2026-07-30 第十三輪：對話訊息的推播（兩端）

> 後端同批補上送出路徑（dispatch [PR #62](https://github.com/thothawei/fleet-dispatch/pull/62)）：
> `ChatService.Send` 推給**收訊那一方**（不推發話者自己的其他裝置）。
> App 這端要把 `chat.message` 收下來並做對的事。

**為什麼要做**：對話先前**只走 WS**——對方 App 一離開前景 WS 就斷了，訊息只會躺在
伺服器上，要等他自己再打開 App 才看得到。斷掉的正是最需要的兩個情境：
**司機到了要聯絡乘客**、**乘客回報遺失物**。

### 改了什麼

- **白名單**：新增 `isChatPush`，兩端過濾器改成
  `isDriverPush ＝ 派單邀請 ∪ 對話`、`isCustomerPush ＝ 行程狀態五種 ∪ 對話`。
  原本兩支（`isRideOfferPush`／`isCustomerRidePush`）保留、語意不變。
- **收到對話推播只點亮未讀角標**，不做別的：
  - **不能餵進 `_handleWsEvent`**：推播 data 只有 `type` 與 `ride_id`，
    `RideMessage.fromJson` 會解析失敗被丟掉，角標根本不會動（司機端原本整條推播
    都直接進 `_handleWsEvent`，這次多了一層分流）。
  - **不必重讀行程／協尋**：對話不影響行程狀態，多打兩支 API 只是浪費。
  - **聊天室開著時忽略**：那代表 App 在前景、WS 也連著，同一則訊息已經由 WS 送到並顯示，
    再加一次會把角標加在使用者正在看的訊息上。
- 內容不放進推播 data，由聊天室自己以 REST（`afterId` 增量）補齊——與第十一輪
  「推播只當訊號」同一條原則。

### 驗收

- `flutter analyze` 無 issue、`flutter test` **328 passed**（317 ＋新 11，含協尋那批）。
  新增 `test/chat_push_test.dart`：白名單 2 案、司機端 3 案（角標 +1／聊天室開著忽略／
  **派單推播照樣開接單卡**）、乘客端 3 案（角標 +1 且不重讀行程／聊天室開著忽略／
  **行程狀態推播仍走對帳**）。後兩案是這次新增分流的回歸網——分流寫錯會把原路徑吃掉。
- **反向確認**：白名單拿掉對話 → 1 案 FAIL；兩端 controller 拿掉分流 → 2 案 FAIL。
- **未做**：真裝置端到端（同 A2，卡 `google-services.json`）。

### 同批：協尋單也走推播

**為什麼**：協尋的節奏是**小時級**（司機要回車上翻、乘客要等），雙方幾乎都不在 App 前景。
先前每一步都只走 WS，等於整條流程要靠當事人自己想起來去開 App 看——
建了單司機不知道、找到了乘客不知道、付了款司機不知道。

- 後端（dispatch [PR #63](https://github.com/thothawei/fleet-dispatch/pull/63)）在建單與每一次
  狀態轉換推給**對方**，標題講的是「收訊者接下來要做什麼」
  （`found` 對乘客是「司機找到你的遺失物了」＝該付處理費了）。
- App 兩端收到 `lost_item.created`／`lost_item.updated` → **只重讀協尋清單**。
  同樣**不能餵進 `_handleWsEvent`**（推播 data 沒有協尋單本體，`LostItemRequest.fromJson`
  會解析失敗被丟掉）；乘客端也**不走 `_handlePushEvent`**——那支會連行程一起重讀，
  但協尋單變了不代表行程變了。
- 驗收：`flutter test` **328 passed**（325 ＋新 3）；反向確認拿掉兩端分流 → 2 案 FAIL
  （乘客那案抓的正是「順手多打了一支行程 API」）。

### 🧪 推播實跑證據（2026-07-30，後端側，**不需 Firebase 憑證**）

> App 這三輪（十一～十三）的證據都是測試層。後端那側**用真服務跑過整條 HTTP 路徑**了，
> 結果貼在這裡，因為它同時證明了 App 端會收到什麼樣的 data：

沒有憑證時後端走 `LogPusher` stub，log 印得出「推給哪台裝置、什麼標題、什麼 data」。
以 `DRIVER-FCM-TOKEN`／`CUSTOMER-FCM-TOKEN` 兩個假 token 註冊後跑完整鏈路，
**10 則推播收件人全部正確**：`ride.assigned`→司機、`ride.accepted`／`driver.arrived`／
`ride.completed`→乘客、`chat.message`→對方、`lost_item.*` 四步→對方。
**data 一如 App 端的假設：只有 `type` 與 `ride_id`**（派單邀請除外，它要開接單卡所以帶完整欄位）。

取消那三條另跑一輪：**乘客自己取消 → 完全沒有推播**（負向斷言成立）、
admin 取消 → `ride.cancelled`、司機放棄 → `ride.redispatched`。

腳本收在 dispatch repo `scripts/push_e2e.sh`／`scripts/push_cancel_e2e.sh`（含四個踩過的坑）。
**仍未做**：真憑證下手機真的響（A2 的同一個卡點）。

---

## 🧪 2026-07-30 第十四輪：把第十輪那兩項搬到模擬器上實跑（本批抓到 1 個 bug）

> 第十輪自己記了「未做：模擬器實跑」，並寫明**卡在沒有工具**：
> `docker pause` 造不出「後端其實成功、只是回應遺失」的正向競態，
> 要驗得寫一支「轉發請求但吃掉回應」的代理。這一輪就是先做那支工具，再把三條路徑跑完。

### 工具：[`tool/lossy_proxy.py`](../tool/lossy_proxy.py)

`10.0.2.2:8081` → `127.0.0.1:8080` 的 HTTP／WS 代理，規則寫在一個 JSON 檔裡（改檔即生效）：

| 規則 | 行為 | 造得出什麼情境 |
|---|---|---|
| `blackhole: ["POST:/api/rides/\\d+/complete"]` | 請求照送（**後端真的執行**），回應**不交還** App，連線掛著 | 「寫入其實成功、只是回應遺失」的正向競態 |
| `ws_block: true` | 拒絕 WS 升級（503） | 「WS 斷了但 REST 還通」——把 WS 這條路徑排除，才知道畫面到底是誰補上的 |

App 用 `--dart-define=API_BASE=http://10.0.2.2:8081` 跑起來，其餘完全不改。
**為什麼要有 `ws_block`**：不關掉 WS 的話，聊天室的訊息可能是 WS 送到的，
「回前景補讀」這條路徑等於沒驗到。

### 實跑結果（`m6_pixel` ＋ 本機 dispatch，司機 driver_id=11）

1. **聊天室回前景補讀（候選 2）✅**：司機端開著行程 #18 的聊天室 →
   乘客以 API 發第一則，**WS 即時顯示**（基準線）→ 重啟代理並開 `ws_block`
   （既有連線斷掉、重連被 503 擋下，log 有 3 次 `WS BLOCK`）→ 按 HOME →
   乘客再發兩則 → 回前景 → **兩則同時出現，且第一則沒有重複**。
   **補讀真的是增量**：後端 log 那次 GET 回 `bytes=302`，而 `after=0` 是 448 bytes、
   `after=1` 是 302 bytes ——證明帶的是 `afterId=1` 而不是全量重載。
2. **`pickUpPassenger` 逾時對帳 ✅**：blackhole `pickup` → 按「乘客已上車」→
   代理 log `上游回 200，不交還 App` → 逾時 15 秒 → 對帳 → **行程卡自己前進到「行程中」**
   （出現「完成行程」與「導航去目的地」），**沒有錯誤橫幅**。
3. **`completeTrip` 逾時對帳 ✅**：同樣手法 → 逾時後**行程卡自己收掉**，
   後端 `customer/rides/active` 回 `{"ride":null}`。
   **後端 log 全程只有一次 `pickup`、一次 `complete`**——App 沒有重送，
   也就沒有「司機自己被自己的 409 擋下」。
4. **`_markStop` 逾時對帳 ⚠️ 抓到 bug**（見下）。

### 抓到的 bug：對帳把錯誤清掉了，但橫幅還留在螢幕上

**根因一句話**：`_markStop` 用 `return _reconcileAfterTimeout(...)`（沒有 `await`），
`try/finally` 的 finally——也就是**唯一那次 `notifyListeners()`**——在對帳完成**之前**就跑掉了，
於是對帳裡的 `_setError(null)` 沒有任何人通知畫面重畫。

**現象**：4 站行程的第 1 站按「已上車」，回應被吃掉 → 逾時 →
對帳確認後端其實標到了 → 清單前進到第 2 站，
**但「請求逾時，請稍後再試」的紅色橫幅留在畫面上超過兩分鐘**。

**為什麼三條路徑只有這條會**：`pickUpPassenger`／`completeTrip` 用的是 `await`，
finally 自然排在對帳之後；只有 `_markStop` 寫成 `return future;`。

**怎麼確定不是猜的**：加了臨時 log 重跑一次，
`DBGX reconcile ... applied=true` 與 `DBGX setError=null` 兩行都印出來了，
**狀態是乾淨的、螢幕不是**——所以問題在通知，不在對帳。
（順帶排除了另一個嫌疑犯：位置回報探針每 8 秒會清掉連線類錯誤，但它清的也是同一份已經是 null 的狀態。）

**修法**：`return await _reconcileAfterTimeout(...)`。一個字。

**驗收**：
- `flutter analyze` 無 issue、`flutter test` **334 passed**（328 ＋新 6）。
- 新增回歸案「對帳把訊息清掉之後，畫面要收到通知（否則橫幅是幽靈）」，
  釘的是**最後一次通知當下看到的錯誤**——只斷言「結束後 error 是 null」的話，
  修不修都會過（原本那案就是這樣漏掉的）。
- **反向確認**：把 `await` 拿掉 → 只有這一案 FAIL，其餘 8 案照過。
- **模擬器複驗**：修好後對第 3 站重跑同一情境 → 站別前進、**沒有橫幅**
  （這次還是離線狀態跑的，所以不可能是位置探針幫忙清掉的）。

### 同批：推播 data 的跨端契約測試

`test/push_backend_contract_test.dart`（5 案）把 **dispatch `scripts/push_e2e.sh` 實跑當下、
後端 log 印出來的那 10 則 data** 原樣抄進測試，斷言 App 解得開、而且分流到對的那一端。
既有的推播測試 payload 是我們自己寫的——後端改鍵名或改收件人，那些測試照樣全綠。
反向確認：把 `fleetEventFromPushData` 的字串轉數值拿掉 → 派單那案 FAIL
（就是 `pitfall-fcm-data-all-strings` 那個坑）。

### ⚠️ 更正一條過期敘述：第十二／十三輪**不是**「不需憑證就能在模擬器上驗」

上一輪的「下次任務」寫著三批都不需憑證、起模擬器時順手做掉——**這點是錯的，已更正**。
沒有 `google-services.json` 時 `initialize()` 回 false，兩端走的是 `NoOpFleetPushService`
（`rideEvents` 是 `Stream.empty()`），裝置上**沒有任何管道能讓一則推播進到 App**。
所以第十二輪（冷啟動補送）與第十三輪（推播分流）在模擬器上**驗不到**，
它們的證據上限就是單元測試＋上面那支跨端契約測試，直到憑證到位為止。
真正不需憑證的只有第十輪那兩項——已於本輪跑完。

**沒有重現、所以不列為 bug**：有一次 `adb install -r` 之後的冷啟動沒有發出
`GET /api/driver/rides/active`（行程卡沒還原）；同一支 build 之後 `force-stop` 再開就正常了，
判斷是安裝當下把 App 殺掉造成的連線競態，不是 App 的缺陷。留在這裡是為了下次再看到時有線索。

---

## 🧾 2026-07-30 第十五輪：把同一支代理套到乘客端（本批修掉 1 個）

> 第十四輪的「下次任務」寫著：**值得做的是把 [`tool/lossy_proxy.py`](../tool/lossy_proxy.py)
> 套到乘客端**——乘客端的建單／取消也有逾時對帳，當時一樣只有測試層證據。這一輪就是那件事。

### 實跑條件（`m6_pixel` ＋ 本機 dispatch，乘客 `customer_id=12`）

App 以 `--dart-define=API_BASE=http://10.0.2.2:8081` 走代理，其餘不改。
**兩種情境都要跑**：WS 通（基準線）與 `ws_block: true`（WS 升級被 503 擋下，只剩 REST）。
少了第二種就分不清畫面是誰補上的——第一次跑的時候，畫面其實是 WS 的 `ride.cancelled` 補的。

### 抓到的 bug：取消成功，畫面卻說「請求逾時，請稍後再試」

**根因一句話**：`cancelOrder` 對連線類逾時**完全沒有對帳**——司機端三條寫入路徑都有
`_reconcileAfterTimeout`、乘客端建單有 `_adoptRideIfCreated`，只有取消沒有——
於是一次其實已經生效的取消被報成失敗。

**現象**（blackhole `POST:/api/rides/\d+/cancel-by-customer` ＋ `ws_block`）：

- 代理 log：`上游回 HTTP/1.1 200 OK，不交還 App` ＝ 後端真的取消了
  （DB 那張單 `status=9`、`ride_events` 有一筆 `ride.cancelled`）。
- 訂單卡在 15 秒內被輪詢收掉，緊接著請求逾時 → 螢幕上唯一的回饋是「請求逾時，請稍後再試」。
- **沒有任何「行程已取消」的確認**：那句話是 WS 事件帶的，
  REST 輪詢走的 `_applyActiveRide(null)` 不會設取消旗標。

乘客於是同時看到「訂單不見了」與「請求逾時」兩個互相矛盾的訊號，無從判斷到底取消了沒有。

**為什麼這次不是幽靈橫幅**：乘客端的錯誤出口是一次性 SnackBar
（`_maybeShowError` 顯示後就 `clearError()`），不會像司機端第十四輪那樣留在畫面上。
這次的病是**內容說謊**，不是殘留。

**修法**：照司機端的模式補 `_reconcileAfterCancel`——逾時（`statusCode == null`）或 409 時
問一次 `GET /api/customer/rides/active`：
單子已經不在（或已是終態）→ 套用後端現況、補上與 WS 同一條「行程已取消。」通知、清掉錯誤；
單子還在 → 什麼都不動，錯誤留著讓他重試；這一問本身也失敗 → 同樣不動。
**409 也對帳**的理由與建單那條相同：那是後端在說「這張單當下不能取消」，
多半就是上一次逾時其實已經生效了。

**驗收**：

- `flutter analyze` 無 issue、`flutter test` **339 passed**（334 ＋新 5）。
- **反向確認**：把對帳呼叫關掉 → 只有新加的三案 FAIL（單子沒了／409／換成另一張單），
  其餘 11 案照過。
- **模擬器複驗（同一組 blackhole ＋ `ws_block`）**：對帳那一次 `GET active` 出現在代理 log 上
  （逾時後 1 秒內），畫面顯示「行程已取消。」，**沒有**「請求逾時」的 SnackBar。
  這次 WS 全程被擋，所以不可能是 WS 幫忙補的。

### 同批驗到（原本只有測試層證據）：乘客端建單逾時對帳

blackhole `POST:/api/rides` ＋ `ws_block` → 按叫車 → 回應被吃掉（後端已經建好單）→ 逾時 15 秒 →
`_adoptRideIfCreated` 查到訂單 → **畫面自己進到「正在為您配對司機」**，沒有錯誤訊息。
DB 裡那位乘客只有一筆新訂單，證明 App 沒有重送。

### 一條可重複用的觀察

乘客端與司機端的錯誤出口機制不同（一次性 SnackBar vs 常駐橫幅），
**同一個「沒對帳」的根因在兩端會長出不同症狀**：司機端留下幽靈橫幅、乘客端則是一句說謊的訊息。
所以「畫面上有沒有殘留」不能當成有沒有對帳的判準；
判準是**逾時之後有沒有再問一次後端**。

---

## 💸 2026-07-30 第十六輪：協尋單的六個寫入都沒有逾時對帳（本批全補上）

> 第十五輪盤點出的候選：`reportLostItem`／`payLostItem`／`closeLostItem` 把例外原樣丟給畫面，
> `lost_item_screen.dart` 的 `_run` 只 `setState(_error)`，**不會再查一次那張單**。
> 查下去發現司機端那三個（`markLostItemFound`／`markLostItemReturned`／`closeLostItem`）
> 一模一樣，所以這一輪把**兩端六條**一起補完（同一族一次掃完，與第七輪同一個做法）。

### 為什麼 `payLostItem` 是六條裡最該修的

那是**付款**。逾時後乘客只看到「請求逾時，請稍後再試」，而處理費可能已經收了——
「付了沒有」是有金額後果的狀態，再按一次只會撞後端的狀態衝突。

### 修法

兩端各一支 `_writeLostItem` helper（乘客端 `CustomerController`、司機端 `DriverController`）：
動作失敗且是連線類（`statusCode == null`）或 409 時，查一次
`GET /api/rides/:id/lost-items`，用各自的判準認定「其實已經生效」：

| 動作 | 判準 |
|---|---|
| `reportLostItem` | 這趟出現了一張**未結案**的單（進畫面時已確認過沒有） |
| `payLostItem` | 後端記到了 `paid_at` |
| `closeLostItem`（兩端） | `status == closed` |
| `markLostItemFound` | 已越過 `open`（`found`／`paid`／`returned`）——**不能只寫 `!= open`**，`closed` 也符合那個條件 |
| `markLostItemReturned` | `status == returned` |

**為什麼判準不用未結案清單**：`returned` 與 `closed` 都不在清單裡，分不出是哪一個生效了。
司機端因此新增 `FleetApiClient.fetchLostItemByRide`（端點是 MultiAuth，司機讀得到自己那趟）。

**一個容易寫錯的地方**：對帳查詢**不能**就地寫在 catch 裡再 `rethrow`——
那樣重擲的會是「對帳查詢的錯誤」而不是原本那個動作的錯誤。
查詢包成獨立方法（失敗回 null），catch 裡的 `rethrow` 才仍然是原本的例外。
這條有測試釘住（「對帳查詢自己也失敗 → 丟回原本那個錯誤」）。

### 驗收

- `flutter analyze` 無 issue、`flutter test` **351 passed**（339 ＋新 12）。
- **反向確認**：把兩端的對帳分支關掉 → 12 案裡 **6 案 FAIL**（正是「對帳應該成功」的那六案），
  另外 6 案（不該對帳／應丟原錯誤）照過。
- **模擬器實跑（`m6_pixel` ＋ 本機 dispatch，blackhole `POST:/api/lost-items/\d+/pay` ＋ `ws_block`）**：
  - 代理 log `上游回 HTTP/1.1 200 OK，不交還 App` ＝ 後端真的收款了。
  - 逾時 15 秒後代理 log 出現對帳那一次 `GET /api/rides/26/lost-items`。
  - 畫面自己變成「**已付款，等待歸還**／已付款，請與司機約定歸還方式。」，**沒有**錯誤訊息。
  - DB `lost_item_requests#4`：`status=paid`、`paid_at` 與 `updated_at` 同一個時間戳
    ＝**只收了一次款**，App 沒有重送。
  - 實跑資料是用 API 造的（admin/admin 登入 → 核准新司機的車輛 → 司機接單／上車／完成 →
    乘客建協尋單 → 司機標尋獲），沒有直接寫 DB。

### 同批查證掉一個「看起來像 bug 但不是」的疑慮

寫測試時撞到 `Cannot add to an unmodifiable list`——`fetchLostItems` 在回應格式異常時
`return const []`，而 controller 把那份結果當成可變的清單狀態（之後會 insert／removeAt）。
**推論是「空清單就會當機」，但實測否定了它**：後端空清單回的是 `{"lost_items":[]}`
（不是 `null`），所以那條分支平常走不到。仍把兩處改成回 `<LostItemRequest>[]`——
改的是形狀不是行為（成本一行，消掉一個真實存在的崩潰形狀）。

---

## ⭐ 2026-07-30 第十七輪：評分送出逾時也沒有對帳（本批修掉，逾時對帳整族清完）

> 第十六輪盤點出的候選 1。`submitRating` 的 catch 只 `return e.message`——
> 而後端「一趟一評」有唯一索引，所以逾時後**再送一次只會拿到 409**：
> 乘客看到「評分失敗」，卻沒有任何出路，而他其實已經評過了。

### 修法

逾時（`statusCode == null`）或 409 時查一次這趟的星等，有就當成成功：

- 新增 `CustomerApiClient.fetchRideRatingScore(rideId)`，讀
  `GET /api/customer/rides/:id` 的 `ride.rating.score`（尚未評分時該鍵不存在 → null）。
  **後端這支單筆查詢本來就帶 rating**，不必新開端點。
- 成功路徑那段狀態切換抽成 `_applySubmittedRating`，讓「真的送出成功」與
  「其實早就評過了」共用同一份清單更新（完成卡星等 ＋ 歷史列 `copyWith`）。
- **409 顯示的是後端記到的那個分數**，不是這次送出的——兩者可能不同
  （乘客第一次給 5 星逾時、第二次改給 3 星，後端記的是 5 星）。有測試釘住這條。

### 驗收

- `flutter analyze` 無 issue、`flutter test` **356 passed**（351 ＋新 5）。
- **反向確認**：關掉對帳分支 → 只有新加的兩個「應該當成成功」的案 FAIL，其餘照過。
- **模擬器實跑（blackhole `POST:/api/customer/rides/\d+/rating` ＋ `ws_block`）**：
  在「我的行程」對行程 #27 給 4 星送出 → 代理 log `上游回 200，不交還 App` →
  逾時 15 秒後出現對帳那次 `GET /api/customer/rides/27` →
  **評分表單自己關閉、那一列變成 ★★★★☆「已評分」**，沒有錯誤訊息。
  DB `ride_ratings` 只有一筆（`score=4`）＝ App 沒有重送。

### 逾時對帳的現況表（這一族到此為止）

| 路徑 | 對帳 | 哪一輪 |
|---|---|---|
| 司機 `pickUpPassenger`／`completeTrip`／`_markStop` | ✅ | 第六／十輪（第十四輪修掉幽靈橫幅） |
| 司機 `acceptOffer` | ✅ | 第五輪 |
| 乘客 `placeOrder` | ✅ | 第六輪（第十五輪補實跑證據） |
| 乘客 `cancelOrder` | ✅ | 第十五輪 |
| 協尋六條（兩端） | ✅ | 第十六輪 |
| 乘客 `submitRating` | ✅ | **本輪** |
| 聊天送出 | ❌ **刻意不做** | 見「下次任務」——訊息沒有唯一狀態，判準要跨端決定 |

---

## 💬 2026-07-30 第十八輪：聊天送出的冪等鍵（跨端，逾時對帳最後一條）

> 第十七輪把逾時對帳整族清完時，唯一剩下的就是聊天送出，並且**刻意沒做**——
> 當時的判斷是「這條不能照抄，需要後端冪等鍵，屬跨端決策」。這一輪就是把那個決策做掉。

### 為什麼這條不能用「查一次狀態」對帳

其他寫入（接單／取消／協尋／評分）在後端都有**唯一狀態**：查一次就知道生效沒。
訊息沒有——「同內容再送一次」本來就是合法行為，
所以 App 無法只靠 `afterId` 補讀分辨「上一次其實送出了」與「使用者真的想再說一次」。
**唯一的解法是由客戶端給一個鍵、後端據此去重。**

### 後端（dispatch [#68](https://github.com/thothawei/fleet-dispatch/pull/68)）

- migration 000024：`ride_messages` 加 `client_msg_id VARCHAR(64)` ＋ partial unique index
  `(ride_id, sender_role, sender_id, client_msg_id) WHERE client_msg_id IS NOT NULL`。
  去重範圍刻意是「同趟同發話者」而非全表——鍵由客戶端產生，跨使用者撞號不該讓後方那位發不出訊息。
- `ChatService.SendWithClientID`：帶鍵時先查既有那筆 → 有就回它，**不重複寫入也不重複推播**
  （否則對方會看到同一句話兩次）。查鍵排在**授權之後**，不然外人拿鍵去試就能反推那趟有沒有這則訊息。
- 反向確認分兩層：只關掉服務層預查 → 測試仍過（DB 唯一索引 ＋ `Create` 後的 fallback 接手）；
  兩層都關 → FAIL 於 `duplicate key ... uq_ride_messages_client_msg_id`。
  **兩層防線各自都足夠**——第一次只關一層時測試沒紅，差點誤判成「測試沒釘住」。

### App 端（本 repo）

- `RideMessage` 多 `clientMsgId`；兩端 `sendMessage` 多具名參數 `clientMsgId`
  （用 null-aware element `'client_msg_id': ?clientMsgId`，沒帶時請求形狀不變）。
- `ride_chat_screen`：
  - 這一則的鍵在第一次送出時產生，**失敗時留著**（`_pendingClientMsgId`）——
    重試沿用同一個鍵才不會在後端變成兩則；送出確認落地才清掉，下一則拿新的鍵。
  - 逾時（`statusCode == null`）→ 補讀 `afterId` 之後的訊息，**用鍵比對**：
    找到＝上一次其實送出了 → 泡泡出現、輸入框清空、不顯示錯誤。
    找不到 → 留著錯誤與內容讓他重試（重試安全）。
  - 補讀到的其他訊息（對方同時說的話）一併顯示——既然問了就別浪費。
  - 明確拒絕（有狀態碼，如 400 訊息過長）**不對帳**。

### 驗收

- App：`flutter analyze` 無 issue、`flutter test` **361 passed**（356 ＋新 5）。
  反向確認兩層：關掉補讀對帳 → 2 案 FAIL；重試不沿用同一個鍵 → 1 案 FAIL。
- 後端：6 案整合測試（testcontainers）本機全綠；CI 純單元集照過。
- **模擬器實跑（blackhole `POST:/api/rides/\d+/messages` ＋ `ws_block`，WS 全程被擋）**：
  1. 代理 log `上游回 200，不交還 App` ＝ 後端真的寫入了。
  2. 逾時 15 秒後出現對帳那次 `GET /api/rides/26/messages`。
  3. 畫面出現自己的綠色泡泡、輸入框清空、**沒有錯誤橫幅**。
  4. DB `ride_messages` 只有一則，`client_msg_id = customer-1785385960604-0`（`role-毫秒-序號`）。
- **冪等性在真後端上直接驗過**（curl，dev DB 已跑 migration 24）：
  - 帶**同一個鍵**重送 → 回 `id=6`（連 `created_at` 都是原本那筆），DB 沒有新增。
  - 帶**不同鍵**、同樣內容 → 新的 `id=7`。「真的想再說一次」照樣成立。

---

## 🔦 2026-07-30 第十九輪：司機端協尋畫面的實跑證據（**沒抓到 bug**，補了一個負向對照）

> 第十七／十八輪列的下一輪候選 1：**第十六輪補的司機端三條協尋寫入只有單元測試**。
> 乘客端那條（`payLostItem`）當時在模擬器上跑過，司機端三條沒有。這一輪就是把它們跑掉。
> **結論：三條都照設計運作，這一輪沒有修任何程式碼**——但多做了一件當初沒做的事：
> 一個**負向對照**，證明「畫面上沒有錯誤訊息」不是取樣沒抓到。

### 實跑條件（`m6_pixel` ＋ 本機 dispatch，司機 `driver_id=14`／`t19drv01`）

App 以 `--dart-define=API_BASE=http://10.0.2.2:8081` 走 [`tool/lossy_proxy.py`](../tool/lossy_proxy.py)，
其餘不改；**全程 `ws_block: true`**（proxy log 每 30 秒一則 `WS BLOCK`），
所以畫面上的每一次變化都不可能是 WS 補的。
資料以 API 造（司機註冊→填車輛→admin 核准→接單／上車／完成→乘客建協尋單），沒有直接寫 DB。

**取樣方式**：按下之後用 `uiautomator dump` **連續**取樣（同一次 shell 呼叫，約 2 秒一筆，
涵蓋整段逾時＋對帳窗口）。這點是被自己坑到才改的——第一次跑負向對照時，
兩次 shell 呼叫之間有 11 秒空檔，SnackBar（顯示 4 秒）整段掉進空檔裡，
差點得出「錯誤訊息根本不會出現」的錯誤結論。

### 四個情境的結果

| # | 情境 | POST 被吃掉 | 對帳 GET | 畫面 | 錯誤訊息 |
|---|---|---|---|---|---|
| 1 | `markLostItemFound`（單 #8） | 14:58:56 上游回 200 | 14:59:11 | 卡片翻成「司機已尋獲，待支付處理費／等待乘客付款」 | 20 筆取樣**全無** |
| 2 | `markLostItemReturned`（單 #6） | 14:54:00 上游回 200 | 14:54:15 | 卡片消失（returned 不在未結案清單） | 16 筆取樣**全無** |
| 3 | `closeLostItem`（單 #8） | 15:00:14 上游回 200 | 15:00:30 | 卡片消失、剩「目前沒有待處理的協尋」 | 18 筆取樣**全無** |
| 4 | **負向對照**（單 #7，連對帳 GET 也 blackhole） | 14:57:33 | 14:57:48（**也被吃掉**） | 卡片**維持原狀**（不亂改狀態） | **14:58:03 出現「請求逾時，請稍後再試」** |

**第 4 列是這一輪唯一新增的方法論**：情境 1–3 的結論是「沒有錯誤訊息」，
而「沒看到」與「不存在」是兩件事。把對帳查詢一併吃掉之後，
**同一支取樣器、同一個節奏抓到了那則 SnackBar**——所以前三列的「全無」不是取樣漏掉。
它同時驗到第十六輪寫在註解裡的那條：對帳查詢自己失敗時，
**重擲的是原本那個動作的例外**（顯示的是「請求逾時」，不是「查詢失敗」）。

### 順帶把 409 分支也在裝置上驗掉（原本只有單元測試）

第十六輪的對帳條件是「逾時（`statusCode == null`）**或 409**」，409 那半從沒在真後端上跑過。
做法：先用 API 讓後端把單 #9 標成 found（模擬「上一次逾時其實已經生效」），
App 這邊畫面還停在 open → 按「已找到」→ proxy log
`POST:/api/lost-items/9/found -> HTTP/1.1 409 Conflict`（15:02:30）→
`GET:/api/rides/28/lost-items`（15:02:31）→ **1 秒內卡片翻成「已尋獲」，沒有錯誤訊息**。
這正是真司機重按一次會走到的路徑。

### 沒有重送（後端請求次數）

`grep -c` 後端 log：`lost-items/8/found`、`lost-items/6/return`、`lost-items/8/close`、
`lost-items/7/found` **各 1 次**。DB 最終狀態與畫面一致
（#6 returned、#5/#7/#8 closed、#9 found）。

### 驗收

- `flutter analyze` 無 issue、`flutter test` **361 passed**（本輪未改程式碼，數字與第十八輪相同）。
- 模擬器實跑證據如上表；收尾關閉模擬器、proxy、後端與 docker。

### 這一輪學到的一條

**「畫面上沒有出現錯誤」是一個負向斷言，需要先用正向案例校準取樣路徑**——
與 `pitfall-negative-assertion-wrong-path` 同一個道理，只是這次校準的不是取值路徑而是**取樣頻率**。
判準寫下來：凡是要斷言「某個短命 UI（SnackBar／toast）沒有出現」，
就得在同一輪跑一個一定會出現它的對照組。

---

## 📍 2026-07-30 第二十一輪：定位串流死掉時，畫面永遠不會知道（本批修掉）

> 逾時對帳那一族清完後換的新族：**司機端的定位健康度**。
> 這一輪沒有用代理，是讀碼提出假設再用注入的假 GPS 串流驗證的。

### 根因一句話

第六輪做的 `locationStale` 降級（位置久到後端不再把司機當派單候選 → hero 改說
「位置回報失敗，暫時收不到派單」）是**在 build 當下用 `DateTime.now()` 算的**，
而司機端沒有任何輪詢——**唯一會觸發重畫的就是位置回報本身**。
於是最該被它接住的情境（權限被撤、定位服務被關 → 串流不再吐 tick）
正好就是「重畫來源消失」的情境：狀態是對的，螢幕永遠不會知道。

再加上 `Geolocator.getPositionStream(...).listen(..., onError: (_) {})`——
串流丟出來的錯誤被**整個吞掉**，連一句話都沒有。

**後果**：司機把定位權限關掉（或系統把前景服務收走），hero 還寫著「等待派單中」，
他就在那邊等一張永遠不會來的單；後端 60 秒後早就不把他當派單候選了。

### 為什麼第六輪的實跑沒踩到

第六輪驗 `locationStale` 用的是 `docker pause`——那時**位置回報照樣每 8 秒送一次**
（只是失敗），每一次失敗都會 `notifyListeners`，畫面自然會重畫。
「串流本身死掉」與「送得出去但後端不理」看起來症狀一樣，重畫來源卻完全不同。

### 修法（兩半，缺一不可）

1. **`onError` 不再吞**：`_handlePositionError` 記下錯誤並通知畫面，
   而且**分開講**——`PermissionDeniedException` → 「定位權限已被關閉，請重新開啟才能接單」、
   `LocationServiceDisabledException` → 「裝置定位服務已關閉，請開啟才能接單」。
   兩者司機的下一步不同，含糊的「定位失敗」等於沒說。
   同時設 `_locationStreamFailed` 讓 `locationStale` **立刻**成立——
   已經知道不會再有位置送出去了，不必等滿 60 秒。成功回報一筆就自動解除。
2. **定期重評**：上線時起一支 10 秒的 timer，`locationStale` **值改變時**才通知
   （不是每個週期都重畫）。沒有它，串流靜靜停掉（不丟錯誤，例如室內長時間無 fix）
   一樣沒人會把畫面叫醒。離線／dispose 都會收掉。

### 順手補的測試接縫

`DriverController` 加 `positionStream` 注入點（比照既有的 `wsFactory`）。
**刻意不是「直接呼叫 onError handler」的測試入口**——那樣測不到「串流真的接上 handler」，
把 `onError:` 拔掉測試照樣會綠。現在測試是往假串流 `addError`，接線也一起釘住。

### 驗收

- `flutter analyze` 無 issue、`flutter test` **367 passed**（361 ＋新 6）。
- **反向確認分兩半各跑一次**：只拿掉 `onError` 接線 → 4 案 FAIL；
  只拿掉健康度 timer → **剛好 1 案** FAIL（「過了鮮度窗要自己通知一次」），其餘照過。
  兩半各自釘住不同的洞。
- **尚未模擬器實跑**：Android 撤定位權限會直接把 App 行程殺掉，
  要驗的是「關掉系統定位服務」那條（`adb shell settings put secure location_mode 0`）。
  下一輪起模擬器時順手跑掉。

### 這一輪的一條通則

**「時間到了才成立」的狀態，一定要問「誰會在時間到的時候叫醒畫面」。**
`locationStale`、token 過期、逾時提示都屬這一類：getter 算得對不代表使用者看得到。
判準很簡單——把會觸發重畫的那件事拿掉，狀態還能不能傳到螢幕上。

---

## 📍 2026-07-30 第二十二輪：乘客端的定位出口（本批修掉 3＋1 個，並補完第二十一輪的實跑尾巴）

> 第二十一輪換族到「定位健康度」，這一輪把同族的**乘客端**清完
> （該輪列的「同族還沒碰的角落 1」）。三個病都在 `placeOrder` 這一條路上。

### 根因三句話

1. **靜默**：`_acquirePosition` 只攔 `TimeoutException`，而系統定位服務被關掉時
   `getCurrentPosition` 丟的是 `LocationServiceDisabledException`；`placeOrder` 的
   `catch` 只收 `ApiException`，於是例外整個穿出去變成未處理的非同步錯誤——
   `_error` 沒被設、`busy` 被 `finally` 清掉，**乘客按下叫車只看到按鈕轉一下就回到原狀**。
2. **文案沒有出路**：`deniedForever` 之後 `requestPermission` 不會再彈任何視窗，
   但訊息只說「需要定位權限才能叫車」——乘客在 App 裡按到死都按不出結果，
   唯一的路是系統設定，而畫面沒說。
3. **不必要的阻擋**：多停靠點行程的 pickup／dropoff 由 stops 推導
   （後端 `prepareStops` 會覆蓋座標欄位，**根本不看** App 送的 pickup），
   `placeOrder` 卻照樣先要權限再等 GPS fix。程式碼裡那句
   「N3：多乘客模式下…故不需要定位」與它下面的實作**互相矛盾**，註解是對的、碼是錯的。

### 修法

- 新增 `lib/core/location/customer_locator.dart`：把 geolocator 的四個呼叫抽成介面。
  **接縫刻意開在最外層呼叫**，不是「餵一個錯誤給錯誤處理函式」——後者測不到
  「哪一種例外會從哪一支呼叫冒出來」，把 `on ...` 分支拔掉照樣會綠。
- `_resolvePickupPosition()`：三種失敗**分開講**（比照第二十一輪的司機端）——
  定位服務關閉／權限被永久拒絕（含「去系統設定」）／拿不到 fix。
- 多停靠點：跳過定位，`pickupLat/Lng` 直接用第一個上車點
  （＝後端推導出來的同一組；送 `(0,0)` 會被 `validatePickupCoords` 判成無效座標）。
- 順手：司機端 `goOffline()` 收掉定位串流那句紅字（見下方「順手修的第四個」）。

### 驗收

- `flutter analyze` 無 issue、`flutter test` **377 passed**（367 ＋乘客 8 ＋司機 2）。
- **反向驗證三半各跑一次**：拿掉例外分支 → 2 案 FAIL；拿掉 `deniedForever` 分岔 →
  2 案 FAIL；讓多停靠點回去走定位路徑 → 2 案 FAIL。三半各自釘不同的洞。
- **模擬器實跑**（`m6_pixel` ＋本機後端，customer flavor，`settings put secure location_mode 0`）：

| 情境 | 結果 |
|---|---|
| 正向對照：定位開著按叫車 | ride #35 建單成功，`pickup_address=目前位置 (25.03300, 121.56540)` |
| 定位服務關閉＋單點叫車 | SnackBar **「裝置定位服務已關閉，請開啟後再叫車」**（畫面實拍） |
| 同上、另一次嘗試 | 走到「目前無法取得定位，請確認 GPS 已開啟後再試」——geolocator 在同一情境下**有時丟 `TimeoutException`**（`getLastKnownPosition` 又回 null），兩條出口都有話講 |
| 定位服務關閉＋多停靠點叫車 | **建單成功** ride #36，`pickup_point=POINT(121.517 25.05285…)` ＝第一個上車點，`ride_stops` 兩筆（A pickup／dropoff）；全程沒有碰過 GPS |

- **Android 會先插一個系統對話框**（"For a better experience, turn on device location"）：
  按 **No thanks** 之後才會走到 App 的錯誤出口。要驗這條就得記得先關掉它，
  否則會誤以為 App 沒反應。

### 順手修的第四個：離線之後紅字還掛著

實跑時看到司機端按了離線，畫面仍寫「裝置定位服務已關閉，請開啟才能接單」。
`goOffline()` 清了 `_locationStreamFailed` 卻沒清那句話——第二十一輪只想到旗標。
修法**只清這一類**（`_locationStreamFailed` 為真才清），後端明確拒絕的業務錯誤
不能一起抹掉（那是司機唯一的失敗回饋，第二十一輪的教訓）；兩個方向各有一個測試。

### 第二十一輪留下的實跑尾巴：跑完了，而且比文件寫的更細

`adb shell settings put secure location_mode 0`（撤權限會直接殺掉 App 行程，驗不到）：

- **hero 真的會降級**：紅底「上線中／位置回報失敗，暫時收不到派單」，實拍。
- **時機分兩種**，取決於串流有沒有丟錯誤：丟了（`onError` 那一半）→ **約 2 秒**內降級；
  沒丟、只是靜靜停止吐位置 → 等鮮度窗那一半，實測**約 12～24 秒**之間翻面。
- **恢復也成立**：把定位服務開回來 → 位置又送得出去 → 自動回綠，不會掛著假紅字。
- **這台模擬器造不出「串流永久靜止」**：`location_mode=0` 之後 geolocator 有時仍持續吐位置
  （後端 log 在關閉後仍每 8 秒收到 `POST /api/driver/location` 200），
  此時 hero 回綠是**正確的**——位置真的送出去了，他仍在派單池裡。
  也就是說「定期重評」那一半在真裝置上**只驗到局部**（翻面看得到，永久靜止情境沒造出來）。
  要完整驗它得用真機關 GPS。**不要宣稱兩半都實跑過。**

### 這一輪學到的兩條

1. **同一個 API 在同一個情境下不保證丟同一種例外**：`getCurrentPosition` 在
   「定位服務關閉」下丟過 `LocationServiceDisabledException`，也丟過 `TimeoutException`。
   出口要按「使用者的下一步」分類，而不是賭它一定丟哪一種。
2. **第二十輪那條負向斷言的教訓要反過來用**：我這一輪一開始在裝置上「看不到 SnackBar」，
   差點下結論說錯誤沒有顯示——其實是**截圖落在它出現之前**（widget tree dump 顯示
   SnackBar 就在 Scaffold 的 snackBar slot、offset y=842.3、高 72）。
   短命 UI 要用**連拍**取樣（我最後用 12 連拍＋底部條帶亮度自動判定才定案）。

---

## 🗓️ 預約司機＋常用地點（2026-07-31，跨端新功能）

> 需求：乘客可以**預約未來的用車**（不是現在叫車），以及把**住家／公司等常去的地點存起來**，
> 叫車與預約時一鍵帶入。後端對應 dispatch 的 `scheduled_rides` 與 `customer_saved_places`
> 兩張新表（migration 000025／000026）。

### 為什麼預約是獨立一張表，不是 rides 加一個狀態

`rides` 的既有查詢散布在派單池（`status='requested'`）、乘客 active、歷史、報表、admin 訂單列表。
多塞一個「還不該被派單」的狀態進去，得**逐一稽核每一支查詢**有沒有把它排除掉——
漏一支就會出現「司機看到一張三天後才要出發的單」。
獨立表對既有路徑是純新增、零風險，代價只是幾個欄位重複。

### 到點怎麼變成真訂單

背景排程器 `ScheduledRideDispatcher` 每 30 秒掃一次，把**約定時間前 15 分鐘**（`ScheduledRideLeadMinutes`）
內的 pending 預約轉成真訂單。轉單走的是**與乘客手動叫車完全同一支** `RideService.CreateByCustomer`
——派單、審計、車種驗證、「同時只能有一張進行中訂單」的規則因此全部自動沿用。
若另外寫一份建單邏輯，兩條路徑遲早會長歪，而且是預約那條先歪（沒有人在旁邊看著）。

三個刻意的設計，每個都對應一種會出事的情況：

| 設計 | 防的是什麼 |
|---|---|
| 提前 15 分鐘發動 | 08:00 的車 08:00 才找司機注定遲到——派單本身要時間 |
| 建立時最少 20 分鐘後（＞提前量） | 比提前量還近的「預約」，使用者要的其實是現在叫車 |
| 認領帶 `attempt_count` 樂觀鎖 | 兩個排程器副本同時掃到同一筆 → 建出**兩張**要付錢的訂單 |

暫時性失敗（乘客當下還在另一趟行程上）維持 pending 等下一輪，最多 10 次；
永久性失敗（座標無效、車種無效）**立刻**判死，不佔著重試額度撐到約定時間才讓乘客發現沒車。

### 常用地點：home／work 是插槽，不是清單項目

`home`／`work` 每位乘客各限一筆（DB 部分唯一索引 `uq_saved_place_customer_kind`），
服務層是 **upsert 語意**——UI 上那顆按鈕叫「設定住家」，乘客預期住家換成新地址，
而不是收到「你已經有住家了」再自己去刪舊的。`custom` 才是可以有很多筆的自訂地點。

**判斷「這是不是住家」一律看 `kind`，不比對 `label`**：label 是使用者可以改的顯示名稱，
他把住家改叫「家」的那一刻，任何比對文字的寫法都會無聲失效。

### 本批 debug 抓到並修掉的兩個

1. **登出沒清掉常用地點與預約（隱私外洩）**——`_clearSession` 早就因為「上一個帳號的個人資料」
   在清行程歷史了，新加的兩份狀態卻漏了。住家與公司是**實體位置**、預約是「這個人什麼時候不在家」，
   比行程歷史更敏感。下一位在這台裝置登入的人一打開叫車頁，快捷列上就是上一位乘客的住家地址。
   同一族的坑見 `pitfall-device-token-multi-owner`。
   測試：`test/saved_places_test.dart`「登出殘留」；反向驗證拔掉清理後該支轉紅。
2. **排程器停機後會把積壓的過期預約全部派車**——`FindDue` 只有上界沒有下界。
   部署／當機／DB 不可用停了一段時間，重啟時昨天早上的預約會今天下午開一台車到乘客家樓下，
   而且他還得付那趟錢。修法是超過約定時間 30 分鐘（`ScheduledRideExpiryGraceMinutes`）就標
   `failed` 並寫原因——**標 failed 而不是留在 pending**，留著它會永遠掛在「即將到來」，
   而那台車永遠不會來。
   測試：`TestDispatcherSkipsLongExpiredSchedules`（先取證看到它真的被轉單，才動手修）。

### 驗收證據

- **後端**：`go build`／`go vet` 乾淨；`internal/service` 新增 15 支測試（真 PostGIS 容器）全綠。
- **反向驗證做了三次**，其中一次推翻了我自己的假設：
  - 拔掉 `FindDue` 的時間條件 → `TestDispatcherOnlyPicksDueSchedules` 轉紅 ✅
  - 拔掉 `ClaimForDispatch` 的樂觀鎖 → `TestDispatcherIsIdempotent` **仍然是綠的** ❌
    ——那支守的是「循序重跑」（第一輪改了狀態，第二輪 `FindDue` 就撈不到），不是併發。
    補了 `TestDispatcherConcurrentTicksCreateOneRide`，而且**第一版也是假的**：
    兩個 goroutine 各跑一次 `Tick`，先跑完的已經改掉狀態，後跑的撈不到，
    拔掉樂觀鎖連跑三次都綠。改成直接餵兩份 `attempt_count=0` 的相同快照進 `dispatchOne`
    才造得出真重疊——這版拔掉樂觀鎖會建出兩張訂單，連跑兩次都紅 ✅
- **App**：`flutter analyze` 無 issue、`flutter test` **400 passed**；
  新增 `test/scheduled_ride_test.dart`（17 支，含 widget 分區與車種顯示）與 `test/saved_places_test.dart`（12 支）。
  同樣做了反向驗證：拔掉 409 的狀態合併、拔掉 `sameSlot` 判斷、拔掉登出清理，三支各自轉紅。
  其中 `sameSlot` 那次**第一版測試也沒守住**（兩條測試都沒走到那個分支），
  補了「別台裝置改過住家、後端回不同 id」才真正覆蓋到。
- **端到端**：`scripts/seed_demo_data.sh` 對本機後端實跑成功（見下）——
  註冊、常用地點 CRUD、預約建立、取消、清單全部走真實 HTTP 200，
  且 gin 路由沒有 panic（新路由與既有 `/customer/rides/:id` 同層混用靜態段與參數段，
  那是**啟動即死、單元測試照樣全綠**的失敗模式，另補了 `scheduled_ride_route_shape_test.go`）。
  實跑後查 DB 確認三筆 pending 的 `attempt_count` 都是 0（沒有被誤轉單）。

### 到點轉單的真環境實跑（不只有測試）

塞一筆 5 分鐘後到點的預約，在跑著的後端上觀察排程器（30 秒一輪）：

| 輪次 | `attempt_count` | 結果 |
|---|---|---|
| 1–2 | 1 → 2 | 撈到並認領，建單被 `已有進行中的訂單` 擋下 → **維持 pending**、寫 `last_error`、等下一輪 |
| 3（把擋路的示範訂單結掉之後） | 3 | **轉單成功**：`status=dispatched`、`ride_id=39`、`last_error` 清空 |

交叉驗證訂單 39：起訖點正是預約上填的那兩個字串、`status=0`（已進派單池）。
這一跑同時證明了三件本來只有測試層證據的事——到期條件真的撈得到、
暫時性失敗真的是「等下一輪」而不是判死、成功後 `last_error` 真的會被清掉。

### 假資料怎麼塞

```
docker compose up -d postgis redis
DB_HOST=127.0.0.1 DB_PORT=5433 REDIS_ADDR=127.0.0.1:6379 go run ./cmd/server
PSQL_DSN='postgres://fleet:change_me@127.0.0.1:5433/fleet?sslmode=disable' \
  sh scripts/seed_demo_data.sh
```

塞出：示範乘客 `demo-customer-1`／`demo123456`，住家＋公司＋兩個自訂地點，
以及 pending／cancelled／dispatched／failed 四種狀態各至少一筆的預約。
**主路徑刻意走真實 HTTP API 而不是直接寫 DB**——這樣塞資料的同時也端到端驗過了那些端點，
不會塞出一份「只有 SQL 造得出來、API 其實不接受」的資料。
只有 `dispatched`／`failed` 非走 SQL 不可：它們是排程器到點後才產生的結果，沒有 API 建得出來。

### 這一批**沒有**做的（寫明條件）

- **預約不支援多停靠點**：`scheduled_rides` 只存單點起訖。多停靠點要另一張 stops 快照表，
  而預約多停靠點的實際需求還沒出現——等有人真的要預約一趟多人共乘再做。
- **預約沒有專屬推播**：轉單後走的是既有 ride 推播鏈路（乘客端第十一輪已接），
  所以「司機接單了」照樣會通知。缺的是「你的預約已轉為訂單」這則本身，
  以及「預約失敗」的通知——後者要等 `failed` 真的在生產環境發生過再決定值不值得。
- **admin 端看不到預約**：後端表與 API 都在，admin UI 沒做。等營運說得出要對預約做什麼再開。
- **司機端不知道自己接的是預約單**（自審時發現，本批刻意沒做）：轉單後那就是一張普通訂單，
  司機看不到「約定上車時間是幾點」。提前量 15 分鐘下多半剛好，但司機若 5 分鐘就到，
  乘客可能還沒下樓，而司機不知道該等。
  **要做的話動的是 `rides`**（帶一個 `scheduled_at` 或來源標記）＋司機端行程卡顯示，
  屬於功能擴充不是 bug，所以沒有夾帶進這批。
  **條件**：等實際跑過幾趟預約單、司機真的回報「到太早不知道要不要等」再做——
  現在做等於猜一個還沒發生的問題。

## 下次任務

> **🎯 2026-07-31 這一輪（預約司機＋常用地點）——開工先看這段**
>
> 這輪不是 debug 輪，是**跨端新功能**：`scheduled_rides`（預約行程）與
> `customer_saved_places`（常用地點）兩張新表、9 支新端點、一支背景排程器，
> 加上 App 端的預約頁、常用地點管理頁與叫車頁的快捷帶入。
> 詳見上方「🗓️ 預約司機＋常用地點」專章（含決策理由與三次反向驗證的結果）。
>
> **這一輪學到的一條（已寫進專章，值得單獨記住）**：
> **綠燈的測試不等於守得住的測試。** 這輪做了三次反向驗證，其中**兩次推翻了我自己的假設**：
> 名字叫 `TestDispatcherIsIdempotent` 的那支，拔掉樂觀鎖照樣綠（它守的是循序重跑，不是併發）；
> 補上的併發測試**第一版也是假的**，因為兩個 goroutine 沒有真的重疊。
> 判準是老規矩：**把防線拔掉，測試會不會紅**——不會紅的那支，它的名字在說謊。
> App 端的 `sameSlot` 也踩到同一件事（兩條測試都沒走到那個分支）。
>
> **➡️ 下一輪候選**（依價值排序）：
> 1. **預約的通知缺口**——轉單後走既有 ride 推播鏈路（會通知「司機接單了」），
>    但「你的預約已轉為訂單」與「預約失敗」這兩則本身沒有。
>    **條件**：等 `failed` 真的在生產環境發生過，再決定值不值得為它做一條通知。
> 2. **admin 端看不到預約**——後端表與 API 都在，admin UI 沒做。
>    **條件**：等營運說得出要對預約做什麼（強制取消？改時間？）再開，
>    做在前面只會做出沒人用的畫面（與維護項 7 同一個判準）。
> 3. **前景服務被系統收走**（Android 省電模式殺掉常駐通知）——
>    這是第二十二輪盤點時就列為「本族唯一剩下的角落」，
>    但 **2026-07-30 已被 [PR #94](https://github.com/thothawei/fleet-app/pull/94) 認領**
>    （`claude/round23-fgs-health`）。**下一輪開工前先確認那支的狀態**，別撞題。
>
> **開工第一件事仍然是 `gh pr list`（三個 repo）**——這一輪開工時查到 #94 正在進行中，
> 所以刻意避開了它的題目改做新功能。這條規則第三次證明有用。


> **🎯 2026-07-30 這一輪做完了什麼（開工先看這段）**
>
> 主題是「**推播這條通道從頭到尾打通**」。本 repo 合併了 6 支 PR：
>
> | PR | 內容 |
> |---|---|
> | [#79](https://github.com/thothawei/fleet-app/pull/79) | **冷啟動推播補送**（第十二輪）——`getInitialMessage()` 早於 `runApp`，事件在沒人訂閱時被丟掉，兩端的「點推播喚醒」都是死路徑 |
> | [#80](https://github.com/thothawei/fleet-app/pull/80) | 對話訊息推播（第十三輪）：兩端白名單＋只點亮未讀角標 |
> | [#81](https://github.com/thothawei/fleet-app/pull/81) | 協尋單推播：兩端白名單＋只重讀協尋清單 |
> | [#82](https://github.com/thothawei/fleet-app/pull/82) | 回填推播鏈路的實跑證據與現況表 |
> | [#83](https://github.com/thothawei/fleet-app/pull/83) | 回填「接單失敗回 200」已由後端改 409 |
> | [#84](https://github.com/thothawei/fleet-app/pull/84) | 標注「401 不註銷 token」留下的洞已由後端補上 |
>
> 後端同批：dispatch #61（乘客行程狀態送出路徑）／#62（對話）／#63（協尋）／
> #64（接單失敗改 409）／#65（一支 token 只能有一位主人，**隱私外洩**）。
>
> **➡️ 推播只剩一個外部卡點：Firebase 憑證**（`android/app/google-services.json`，
> 乘客 flavor 另需一份）。憑證放進來後**不需要再改任何程式碼**——後端送出路徑已用真服務
> 逐則驗過（10 則全部推對人）。憑證到位那天要驗：
> 司機端「App 被殺 → 點推播 → 接單卡」、乘客端「App 被殺 → 點推播 → 冷啟動後畫面已是最新」。
>
> ~~**仍然沒有模擬器實跑的三批**（都不需憑證…）~~ **這句話當時寫錯了，2026-07-30 更正**：
> 只有**第十輪**那兩項不需憑證——**已於第十四輪跑完，並抓到一個 bug**（見該段）。
> 第十二／十三輪（冷啟動補送、推播分流）**在沒有憑證的裝置上根本驗不到**：
> `initialize()` 失敗時走的是 `NoOpFleetPushService`，`rideEvents` 是空串流，
> 沒有任何管道能把一則推播送進 App。
> **本機後端怎麼起**（實測有效，`.env` 是給 docker 內用的，跑在主機要覆寫三個變數）：
> `docker compose up -d postgis redis` ＋
> `DB_HOST=127.0.0.1 DB_PORT=5433 REDIS_ADDR=127.0.0.1:6379 go run ./cmd/server`
> （dispatch repo；Docker registry 拉不到映像，別用 `--build`）。
> **弱網／回應遺失要用 [`tool/lossy_proxy.py`](../tool/lossy_proxy.py)**，不要再試 `docker pause`。
>
> **這一輪學到的一條**：`StreamController.broadcast()` 在沒有訂閱者時 `add` 的事件會**靜默消失**。
> 只要「發送點」與「訂閱點」不在同一個生命週期階段，就要問「**發送比訂閱早的那一次去哪了**」。

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
> 8. ~~**清掉殘留 worktree `fleet-improvements-todo-cc8d85`**~~ ✅ **已完成（2026-07-30）**：
>    連同另一個殘留 `todo-list-enhancement-abdd77` 一起移除，五支已合併的本機分支
>    （`claude/e2e-salvaged-fixes`／`customer-push-wiring`／`chat-resume-and-timeout-reconcile`／
>    `driver-cancel-notice`／`todo-list-enhancement-abdd77`）一併刪掉。
>    **判定用的是兩點 diff 而非 `--merged`**（squash 合併下 `--merged` 全漏，
>    見 `pitfall-stale-branch-deletion`）：`git diff main <branch>` 若只剩「main 比它新」的反向差異，
>    代表內容已全在 main。刪之前也用 `ps aux` 確認沒有 session 正在用那兩個目錄。
>
> **2026-07-28 又補了一項（不在原清單上）**：`docs/IOS_PLAN.md` 的**勾選框與散文不一致**——
> 階段 1 的四項、3-4、7-1 的散文說完成、勾選框卻仍是 `[ ]`／`[~]`。
> 只讀清單的人會以為要重跑那些 sudo 步驟。已逐條重新取證後補勾（見 IOS_PLAN「執行進度」）。
> **前置條件當日實查**：`android/app/google-services.json` **不存在**（A2 仍卡）、
> `xcrun devicectl list devices` → **No devices found**（A5 階段 5 仍卡）。
> **2026-07-29 再查一次，兩者仍未到位**（另加驗 `ios/Runner/GoogleService-Info.plist` 也不存在）——
> 這兩條**每次開工都值得重跑**：它們是外部資源，隨時可能到位，而不會有人來通知我們。
> **2026-07-30 第三次實查：三者依然都不在**（兩個 Firebase 設定檔不存在、
> `xcrun devicectl list devices` → No devices found）。
> **2026-07-30 第十四輪開工前第四次實查：仍然都不在**（同三條指令）。
> **2026-07-30 第十九輪開工前第五次實查：仍然都不在**；同時 `gh pr list --repo` 三個 repo
> 的 open PR 皆為 0（沒有撞題風險）。
> **2026-07-30 第二十二輪開工前第六次實查：三者依然都不在**
> （`android/app/google-services.json`、`ios/Runner/GoogleService-Info.plist` 不存在、
> `xcrun devicectl list devices` → No devices found）；三個 repo 的 open PR 同樣皆為 0。
>
> **2026-07-28 收尾**：清單清空後改做 debug——修掉 4 個 bug、做完一輪跨端契約對帳，
> 見上方「🐞 2026-07-28 debug」。**六份清單（本檔、admin TODO、IOS_PLAN、gap-analysis-plan、
> 兩份 UI/UX 執行計畫）的勾選現在全部對得上程式碼現況**，文件層面沒有可清的東西了。
>
> **🎯 下次開工第一件事**（2026-07-30 第十三輪後更新）：先跑 `gh pr list`（三個 repo），
> 再看下面這張「推播整條鏈路現在缺什麼」的表——**除了憑證，其餘都通了**：
>
> | 環節 | 狀態 | 在哪 |
> |---|---|---|
> | 乘客 App 註冊 token、收到推播去對帳 | ✅ 第十一輪 | 本 repo |
> | 後端對乘客送出（行程狀態 5 種） | ✅ dispatch [#61](https://github.com/thothawei/fleet-dispatch/pull/61) | dispatch |
> | 冷啟動時事件送得到訂閱者 | ✅ 第十二輪 | 本 repo |
> | 對話訊息推播（兩端） | ✅ dispatch [#62](https://github.com/thothawei/fleet-dispatch/pull/62)＋App [#80](https://github.com/thothawei/fleet-app/pull/80) | 兩邊 |
> | 協尋單每一步推播（兩端） | ✅ dispatch [#63](https://github.com/thothawei/fleet-dispatch/pull/63)＋App [#81](https://github.com/thothawei/fleet-app/pull/81) | 兩邊 |
> | 後端整條 HTTP 路徑實跑 | ✅ **10 則推播收件人全對**（見上方「推播實跑證據」） | dispatch |
> | **Firebase 憑證** | ❌ **卡住** | 要你建 Firebase 專案 |
> | 真裝置端到端驗收 | ❌ 等憑證 | — |
>
> **2026-07-30 第十四輪之後補一句**：上表不變（推播仍只卡憑證），但**第十輪那兩項已經有實跑證據了**，
> 而且實跑抓到一個測試層抓不到的 bug（幽靈錯誤橫幅）。
> ~~下一輪要再往前推的話，值得做的是**把同一支代理套到乘客端**~~
> ✅ **已於第十五輪做掉**（見上方專段）：乘客端建單逾時對帳補上了實跑證據，
> 並抓到「取消成功卻報成逾時」——`cancelOrder` 是這三端唯一沒有對帳的寫入路徑。
>
> ~~**➡️ 第十五輪盤點出的下一輪候選**：遺失物協尋的三個寫入沒有逾時對帳~~
> ✅ **已於第十六輪做掉**（見上方專段），而且**兩端六條**一起補完
> （司機端的 `markLostItemFound`／`markLostItemReturned`／`closeLostItem` 同一個病）。
> `payLostItem` 已在模擬器上驗到：付款回應被吃掉、WS 被擋，畫面仍自己變成「已付款，等待歸還」。
>
> ~~**➡️ 第十六輪盤點出的下一輪候選**：`submitRating` 與聊天送出~~
> ✅ **`submitRating` 已於第十七輪做掉**（見上方專段，含模擬器實跑）。
> **逾時對帳這一族到此清完**，現況表在第十七輪那段。
>
> ~~**➡️ 剩下唯一一條逾時路徑：聊天送出——刻意先不做**~~
> ✅ **已於第十八輪做掉（跨端）**：後端加冪等鍵（dispatch #68 的 migration 000024）、
> App 端逾時後用鍵比對補讀，見上方專段。**逾時對帳整族到此完全清完。**
> 下面這段保留當時的判斷理由——它解釋了為什麼這條非得動後端：
> 訊息可能其實送出了，畫面只顯示錯誤、輸入框內容留著，乘客重送 →
> **後端多一筆重複訊息**（沒有冪等鍵）。
> **不能照抄協尋／評分那套判準**：協尋單與評分在後端都是唯一狀態（查一次就知道生效沒），
> 訊息不是——「同內容再送一次」本來就是合法行為，App 端無法只靠 `afterId` 補讀分辨
> 「上一次其實送出了」與「使用者真的想再說一次」。
> **這是跨端決策**：要嘛後端在 `POST /rides/:id/messages` 收一個 client 產生的冪等鍵
> （建議這個），要嘛接受重複訊息、由 UI 讓乘客自己看得懂（成本低但體驗差）。
> 先開一支 dispatch 的討論再動 App。
>
> **➡️ 逾時對帳以外、還沒碰過的角落**（依價值排序，都不需外部資源）：
> 1. ~~**司機端的協尋畫面沒有實跑證據**~~ ✅ **已於第十九輪做掉**（見上方專段）：
>    三條寫入路徑（found／returned／close）＋409 分支全部在裝置上跑過，**沒有抓到 bug**；
>    另外補了一個負向對照，證明「畫面上沒有錯誤訊息」不是取樣漏掉。
> 2. ~~**admin 端（line-fleet-admin）完全沒有逾時對帳的概念**~~ ✅ **已於第二十輪做掉（跨 repo）**：
>    admin [PR #29](https://github.com/thothawei/fleet-frontEnd/pull/29)
>    ＋ dispatch [PR #69](https://github.com/thothawei/fleet-dispatch/pull/69)。
>    盤點九條寫入後的結論是**不要照抄 App 那套**——admin 的寫入多為冪等設定，
>    真正的病是「`onError` 只跳訊息、從不重讀後端」，而文案還寫著「請稍後再試」。
>    實跑抓到的完整壞法：強制取消的回應被吃掉（後端其實已取消）→ 畫面停在「前往接客」→
>    操作者照著訊息再按一次 → **後端回 500「訂單狀態已變更」**（這是 dispatch 的第二個 bug，
>    狀態衝突本該是 409，乘客端早就這樣分類、admin 那支是漏網的）。
>    修法：連線類或 409 → 重讀 query ＋ 不宣稱失敗的措辭；確認對話框送出後一律關閉。
> 3. **乘客端協尋只有 `payLostItem` 有實跑證據**（第十六輪）：
>    同一支 controller 的 `reportLostItem`／`closeLostItem` 仍只有單元測試。
>    做法與第十九輪完全相同，換 customer flavor ＋ blackhole
>    `POST:/api/rides/\d+/lost-items`／`POST:/api/lost-items/\d+/close`。
>    **價值低於第 2 項**——同一支 helper、同一組判準，第十九輪已證明這套機制在裝置上成立。
>
> **➡️ 第十九／二十輪之後**：逾時對帳這條線**三端都清完了**——
> App 兩端（第五～十九輪）、admin ＋ dispatch（第二十輪）。
> 剩下的第 3 項是同機制的重複驗證，價值很低。
> **下一輪請換一個還沒碰過的族**，別再往這條線挖。
>
> ✅ **第二十一輪就是換族的第一輪**：司機端定位健康度（見上方專段），
> 修掉「定位串流死掉時畫面永遠不會知道」。~~**它留了一條實跑尾巴**~~
> ✅ **已於第二十二輪跑完**（`location_mode=0`）：hero 真的會降級、恢復也成立；
> 但**「定期重評」那一半只驗到局部**——這台模擬器造不出「串流永久靜止」，
> 詳見第二十二輪專段那張表，別把它當成兩半都驗過。
>
> **同族還沒碰的角落**：
> 1. ~~**乘客端有沒有同一種病**~~ ✅ **已於第二十二輪做掉**：有，而且是三個
>    （靜默、`deniedForever` 文案沒出路、多停靠點被不必要地擋住）。
>    順帶查清一件事：**地圖跟隨完全不吃裝置定位**（司機 marker 來自 WS，
>    `lastPosition` 為 null 時退回台北市中心），所以那條路徑沒有出口要補。
> 2. **前景服務被系統收走**（Android 省電模式殺掉常駐通知）：
>    現在只有定位串流的 onError 會知道，服務本身消失時 App 端沒有任何偵測。
>    **這是本族目前唯一剩下的角落**，也是下一輪的首選。
>
> **第二十輪順帶學到的一條**（已寫進坑卡）：反向驗證要還原檔案時，
> **先 `cp` 一份再改、改完從備份還原**——這一輪順手打了 `git checkout -- <file>`，
> 把同一個檔案裡還沒 commit 的修正一起抹掉了，得重寫一次。
>
> 也就是說：**憑證一到位，推播就該直接會動**，不需要再寫程式碼。
> 憑證到位那天要跑的驗收：司機端「App 被殺 → 點推播 → 接單卡」、
> 乘客端「App 被殺 → 點推播 → 冷啟動後畫面已是最新狀態」。
> ~~**第十輪那兩項修正仍只有測試層證據，沒有模擬器實跑**~~
> **已於第十四輪跑完（過期敘述，2026-07-30 更正）**——當時卡的「`docker pause` 造不出正向競態」
> 也已解決，工具是 [`tool/lossy_proxy.py`](../tool/lossy_proxy.py)。
> 維護項只剩 7（等營運需求）；8 已於 2026-07-30 做掉。
> 第 1–4 項仍全部需要你提供外部資源或拍板——Firebase 專案（A2）／
> iPhone＋Xcode Personal Team（A5 階段 5）／金流方案（付款）／車種供給為零的產品方向。
>
> 想再往前推、又不解上述卡點的話，**剩下有價值的方向是繼續 debug**：
> ~~遺失物協尋鏈路、admin 端 REST 形狀、模擬器 UI 層~~ 三者已於第二輪補完；
> **第三輪（2026-07-28）修掉 token 過期後 App 說謊**，見上方「🔑 第三輪 debug」。
>
> **➡️ 下一輪 debug 還沒碰過的角落**（依價值排序，都不需外部資源）：
> 1. ~~**App 生命週期**~~ ✅ **已完成（2026-07-29）**，見上方「🔁 第四輪 debug」——
>    原本兩件事都沒做：回前景不重連 WS、也不跟後端對帳（司機端連輪詢都沒有）。
>    順手修掉 `isConnected` 在斷線後仍回 true 的說謊旗標。
> 2. ~~**多裝置／同帳號重複登入**~~ ✅ **已完成（2026-07-29）**，見上方「🎫 第五輪 debug」——
>    後端確實不踢舊 session、兩邊都收派單；但查下去撈到更大的洞：
>    **搶輸／接單失敗時後端回 200，App 會給司機一張假的行程卡**。已一併修掉。
> 3. ~~**弱網**（非全斷）~~ ✅ **已完成（2026-07-29）**，見上方「📶 第六輪 debug」——
>    逾時文案已在真裝置驗到；同時修掉請求堆積、hero 在「已不在派單池」時仍說
>    「等待派單中」、以及接單／建單逾時後不跟後端對帳的三個洞。
>    （**模擬器限速對 `10.0.2.2` 無效**，要用 `docker pause` 凍結後端。）
>
> **➡️ 三個角落都清完了**，重新盤點已於 2026-07-29 做完，見
> [第九輪盤點](#-2026-07-29-第九輪盤點下一輪的三個候選本批只盤點沒有修)。結論是三條候選：
>
> | # | 候選 | 需要外部資源？ | 建議順序 |
> |---|---|---|---|
> | 1 | **乘客端完全沒有推播管道**（後端 `/api/customer/device-token` 已就緒、App 從沒接） | 憑證那半要 Firebase（同 A2） | ✅ **接線（第十一輪）＋後端送出（dispatch #61）＋冷啟動補送（第十二輪）都已完成**；**只剩憑證** |
> | 2 | ~~聊天室的 `afterId` 增量補讀是死路徑~~ | 不用 | ✅ **已修（第十輪）** |
> | 3 | ~~`completeTrip`／`pickUpPassenger`／`_markStop` 沒有逾時對帳~~ | 不用 | ✅ **已修（第十輪）** |
>
> ⚠️ **原本列在這裡的「乘客端被系統殺掉後從推播喚醒的還原路徑」已刪除**——
> 查證後發現乘客端根本沒有推播（候選 1），**那題的前提不成立**。
> 另一個原本的方向「多停靠點行程在弱網／背景切換下的狀態一致性」則**收斂進候選 3**：
> 讀碼查到的具體缺口就是 `_markStop` 逾時後不對帳。
>
> ---
>
> **🎯 2026-07-29 收尾（PR 佇列稽核那一批，見上方專段）——下一次開工先做這三件**：
>
> 1. **開工第一件事是 `gh pr list`，不是 `git log`**。這一輪盤點發現三個 repo 有
>    **8 支 open PR**，其中兩支是同一個功能的獨立實作——**平行 worktree 的 session
>    彼此看不見對方**，題目又都取自本檔的「下一輪 debug 角落」清單，撞題是必然的。
>    要嘛開工前先看 PR 佇列，要嘛在本檔把認領的題目**當場劃掉**。
> 2. ~~**本批救回的三項只有單元測試，沒有模擬器實跑**~~ ✅ **同日補完**（見上方專段）：
>    司機端跨裝置停靠點同步、乘客端建單 409 接手**都已在 `m6_pixel` 上閉環**
>    （含 `ride_events` 交叉驗證「App 那次按下沒有產生新訂單」）。
>    **只剩 WS 心跳驗不到**——客戶端 ping 在後端沒有可觀察的痕跡，要證明得封包擷取。
> 3. **stacked PR 的兩個 GitHub 坑**（`--delete-branch` 連帶關閉、
>    `pull_request: branches: [main]` 的 base 過濾器擋掉 CI）已寫在上方專段，
>    下次再疊 PR 前先看那兩條。

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
