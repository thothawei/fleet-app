# iOS 開發規劃（A5 展開）

> 建立：2026-07-20。對應 [`docs/TODO.md`](TODO.md) 的 **A5. iOS build**。
> 依「階段」順序執行，每階段跑完驗收才往下。

## 🧪 iOS 模擬器實跑驗收（2026-07-21，iPhone 17 Pro／iOS 26.5 ＋ 後端 docker）

> **階段 1–3 全數完成並實跑驗過**（階段 1 的 sudo 三行由使用者執行）。
> 以下每一項都有截圖與後端 log／API 交叉驗證，不是「應該可以」。

- **乘客端**：登入（`sim-customer-001`）→ 叫車主畫面，**OSM 圖磚正常渲染**；
  後端 log 同時出現 `WebSocket 已連線 id=8 role=customer`。
- **司機端**：登入（`sim-driver-001`）→ **O2/O3 強制跳轉車輛資訊頁**（新司機沒填車輛，
  iOS 上同樣生效）→ 以 API 填車輛（sedan／IOS-0721）＋ admin 核准 → 重啟 App 進首頁。
- **定位權限**：按「上線」→ iOS 權限對話框（文案來自我們的 Info.plist）→ 允許 →
  hero 轉綠「上線中」、狀態列藍色定位指示、位置每 8 秒回報（後端 log 可見）。
- **WS 派單全鏈路**：乘客建單 ride #12 → **司機端全螢幕接單卡即時跳出**
  （距離 54 公尺／ETA 1 分鐘，距離是用模擬器 `simctl location` 設的座標算的）→
  按「接單」→ 行程卡 #12 **內嵌 OSM 概覽地圖在 iOS 正常渲染**（紅色上車點釘＋綠色計程車 marker），
  聯絡乘客／導航／乘客已上車／放棄此單按鈕齊全。
- **結論**：`http://` REST 與 `ws://` WebSocket 在 iOS 上都通，ATS 設定正確；
  Android 上既有的行為（強制車輛 gate、WS 派單、內嵌地圖、Keychain session 還原）在 iOS 上一致。

**驗收方法備忘（下次省事）**：模擬器沒有 `adb input tap` 這種東西，本次用
`osascript` 取得 Simulator 視窗座標 ＋ `cliclick`（`brew install cliclick`）點擊、
`screencapture -R<視窗矩形>` 截圖、`xcrun simctl location booted set <lat>,<lng>` 餵座標。
`System Events` 的 `click at` 會回 `-25204` 失敗，別再試。

## 執行進度（2026-07-21）

- ✅ **1-4 CocoaPods 已安裝**：`brew install cocoapods` → `pod --version` = **1.17.0**（`/opt/homebrew/bin/pod`）。
- ✅ **階段 3 的純程式碼／plist 缺口先行補完**（不需 Xcode 即可做）：3-1、3-2、3-3 已改，
  3-6 查證後確認**本來就不需要改**。靜態驗收：`plutil -lint` OK、`flutter analyze` 無 issue、
  `flutter test` **169 passed**。**這三項的 runtime 驗收都要等階段 2 模擬器跑起來才算數。**
- ✅ **1-1／1-2／1-3 由使用者執行完成**（需 sudo，Claude 代打不了）。
  驗證：`xcode-select -p` = `/Applications/Xcode.app/Contents/Developer`、
  `xcodebuild -version` = **Xcode 26.6 (17F113)**、`xcrun simctl` 有 **iOS 26.5 runtime**
  ＋ iPhone 17 Pro／17 Pro Max。
- ✅ **1-5 `flutter doctor -v`**：Xcode ✓（CocoaPods 1.17.0）、**No issues found!**
- ✅ **階段 2、3、4 全部完成並實跑驗過**（見上方實跑驗收段與階段 4 各項）。
- 🧹 **順手修掉一個 iOS build 帶進來的副作用**：`flutter analyze` 一度冒出 **13158 個 issue**，
  全部來自 `build/ios/SourcePackages/checkouts/`（iOS build 把 flutterfire 等 SPM 相依 clone 進
  `build/`，裡面的 dartpad 範例本來就編不過）。`analysis_options.yaml` 加 `exclude: build/**` 後
  回到 **No issues found**、`flutter test` 169 passed。CI 是乾淨 checkout 所以沒被影響，
  但本機分析會被淹沒。
- ✅ **階段 7（收尾）也完成**：CI 加了 iOS job、README 補了 iOS 段、TODO 回填。
- ➡️ **只剩階段 5（實機）與階段 6（推播，需付費帳號）**。
  階段 5 需要使用者把 iPhone 接上電腦，並在 Xcode 幫 Runner target 選 Personal Team（簽名）
  ＋在手機上信任開發者憑證——這兩件事是 GUI 操作，Claude 代勞不了。
  這階段最大的產出是 **A1「鎖屏長跑背景定位」的 iOS 實機驗收**，模擬器測不出來。

## 0. 環境現況（2026-07-20 實測）

| 項目 | 實測結果 | 是否阻塞 |
| --- | --- | --- |
| Xcode.app | `/Applications/Xcode.app` 26.6 ✅ 已安裝 | 否 |
| `xcode-select -p` | `/Library/Developer/CommandLineTools` ❌ | **是** |
| `xcodebuild -version` | 報錯 `requires Xcode, but active developer directory is a command line tools instance` | **是** |
| `xcrun simctl` | `unable to find utility "simctl"` ❌ | **是** |
| CocoaPods (`pod`) | `command not found` ❌ | **是** |
| 系統 Ruby | 2.6.10（macOS 內建，不建議 `sudo gem install cocoapods`） | 需繞道 |
| Flutter | 3.44.4 stable ✅ | 否 |
| `ios/` 目錄 | Flutter 預設骨架；**無 Podfile**（首次 build 才生成）、只有 `Runner` 單一 scheme、無 flavor 設定 | 待做 |

**結論**：Xcode 安裝完成 ≠ 可以 build。上面四個 ❌ 是第 1 階段要清掉的。

---

## 階段 1 — 工具鏈打通（必須先做，會需要 sudo 密碼）

- [ ] **1-1 切換 developer directory**
      `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
      驗收：`xcodebuild -version` 印出 `Xcode 26.x`。
- [ ] **1-2 同意授權 + 安裝首次啟動元件**
      `sudo xcodebuild -license accept` → `sudo xcodebuild -runFirstLaunch`
      驗收：兩個指令 exit 0。
- [ ] **1-3 安裝 iOS 模擬器 runtime**（Xcode 26 預設不含）
      `xcodebuild -downloadPlatform iOS`
      驗收：`xcrun simctl list devices available | grep iPhone` 有裝置。
- [x] **1-4 安裝 CocoaPods** ✅ 2026-07-21
      `brew install cocoapods`（避開系統 Ruby 2.6）。
      驗收：`pod --version` → **1.17.0**，`which pod` → `/opt/homebrew/bin/pod`。
- [ ] **1-5 `flutter doctor -v`**
      驗收：Xcode 與 CocoaPods 兩列都是 ✓，無 `!`。

> ⚠️ 1-1 / 1-2 需要 sudo 密碼，Claude 無法代打。下次 session 開場請使用者自己跑這兩行，或允許互動輸入。

---

## 階段 2 — 首次 build 起來（先不管 flavor / 推播）

- [x] **2-1 `flutter build ios --no-codesign -t lib/main_customer.dart`** ✅ 2026-07-21
      **一次就過**：`✓ Built build/ios/iphoneos/Runner.app (20.4MB)`（Xcode build 221s）。
      **預期的 deployment target 坑沒發生**——Flutter 3.44 下 firebase／geolocator／permission_handler
      全走 **Swift Package Manager**，`IPHONEOS_DEPLOYMENT_TARGET` 維持 13.0 即可編譯；
      `pod install` 只處理唯一不支援 SPM 的 `flutter_secure_storage`（3.8s）。
- [x] **2-2 模擬器實跑乘客端** ✅ 2026-07-21（iPhone 17 Pro／iOS 26.5）
      **刻意不帶 `--dart-define`**，才能同時驗 3-1 的平台預設值。
      登入畫面顯示「後端：http://127.0.0.1:8080」→ 登入成功 → 叫車主畫面
      **OSM 圖磚真的從網路渲染**（台北信義區街道圖、中文地名齊全）。
      後端 log 交叉驗證：`customers WHERE line_user_id='sim-customer-001'`、
      **`WebSocket 已連線 id=8 role=customer`**、rides/active 與 lost_items 查詢全數進來。
- [x] **2-3 `ios/Podfile` + `ios/Podfile.lock` 進版控** ✅ 2026-07-21
      `ios/.gitignore` 只排除 `Pods/`，沒排除 Podfile 兩檔。連帶進版控的還有
      pod install 改動的 `ios/Flutter/*.xcconfig`（`#include?` Pods 設定）、
      `project.pbxproj` 的 Pods 整合、`Runner.xcworkspace/contents.xcworkspacedata`，
      以及 SPM 的 `Package.resolved`（鎖住 firebase-ios-sdk 等版本）。

---

## 階段 3 — App 端 iOS 專屬缺口（實際要改的程式碼／設定）

以下都是掃過現有程式碼確認的**真實缺口**，不是通用清單：

- [x] **3-1 `AppConfig.apiBase` 的 iOS 預設值** ✅ 2026-07-21（程式已改，runtime 待階段 2）
      原本 [`lib/core/config/app_config.dart`](../lib/core/config/app_config.dart) 硬寫
      `http://10.0.2.2:8080`——那是 **Android 模擬器**專用位址，iOS 模擬器要用
      `http://127.0.0.1:8080`。
      改法：`apiBase` 從 `const` 改成 **getter**，`--dart-define=API_BASE` 有值時一律優先
      （`_apiBaseOverride.isNotEmpty`），沒帶才依 `Platform.isIOS || Platform.isMacOS` 分流。
      全 repo 無 const 情境使用 `AppConfig.apiBase`（已 grep），改 getter 不會編譯失敗。
      **驗收待辦**：iOS 模擬器不帶 `--dart-define` 也連得到本機後端。
- [x] **3-2 ATS（App Transport Security）擋 http/ws** ✅ 2026-07-21（plist 已加，runtime 待階段 2）
      後端開發環境是 `http://` + `ws://`，iOS 預設全擋。
      `ios/Runner/Info.plist` 已加 `NSAppTransportSecurity` → `NSAllowsLocalNetworking = true`
      （**刻意不用 `NSAllowsArbitraryLoads`**，那會連公網 http 一起放行）。`plutil -lint` OK。
      **未驗證**：`NSAllowsLocalNetworking` 對 `127.0.0.1` 與 RFC1918 私有 IP 的實際涵蓋範圍
      沒有查到 Apple 原文（文件頁是 JS 渲染，抓不到內文），**以階段 2 模擬器實跑的結果為準**；
      若模擬器連 `127.0.0.1` 仍被擋，再依當下錯誤訊息調整。
      驗收：模擬器能打 API 且 WebSocket 連得上（司機 marker 會動）。
- [x] **3-3 區網權限說明** ✅ 2026-07-21（plist 已加，驗收要等階段 5 真機）
      iOS 14+ 存取區網要 `NSLocalNetworkUsageDescription`，已寫入 Info.plist。
      驗收：真機第一次連 `192.168.x.x:8080` 時出現權限詢問並可連線。
- [ ] **3-4 背景定位 Info.plist 補齊**
      現況已有 `UIBackgroundModes: location` + 兩則位置用途說明 ✅，階段 5 實機驗背景定位夠用。
      `remote-notification` 留到階段 6（買付費帳號）再補——現在加了也沒有 APNs 可用。
      程式面 [`driver_location_settings.dart`](../lib/core/location/driver_location_settings.dart)
      的 `AppleSettings` 已寫好（`automotiveNavigation` + 不自動暫停），這塊不用改。
- [x] **3-5 `permission_handler` 的權限巨集** ✅ 2026-07-21 查證＋實跑，**不需要改 Podfile**
      規劃寫的「Podfile `post_install` 開巨集」是舊 CocoaPods 路徑。本專案的
      `permission_handler_apple 9.4.10` **走 SPM**（`Podfile.lock` 裡只有 `flutter_secure_storage`），
      巨集改由套件的 `Package.swift` 決定：`PERMISSION_LOCATION` 在 **Info.plist 有
      `NSLocationWhenInUseUsageDescription`／`NSLocationAlwaysAndWhenInUseUsageDescription`
      任一鍵時 = 1**（我們兩個都有），`PERMISSION_NOTIFICATIONS` 預設就是 1。
      **實跑驗收**：司機端按「上線」→ iOS 跳出定位權限對話框，且說明文字正是我們 Info.plist 的
      「上線時需要定位以回報司機位置供派單使用。」→ 選「使用 App 期間允許」→ hero 轉綠「上線中」、
      狀態列出現藍色定位指示。
- [x] **3-6 `url_launcher` 開外部地圖** ✅ 2026-07-21 查證後**不需要改任何東西**
      重讀 [`lib/core/util/maps.dart`](../lib/core/util/maps.dart)：只組
      `https://www.google.com/maps/search/?api=1&query=...` 並 `launchUrl(externalApplication)`，
      **沒有 `comgooglemaps://`、也沒有 `canLaunchUrl`** → 不需要 `LSApplicationQueriesSchemes`。
      規劃時寫的「先走 https 退路」其實就是現況。真機若想改開 Google Maps App 再另議。
- [x] **3-7 `flutter_secure_storage` Keychain** ✅ 2026-07-21 觀察通過，未加任何 entitlement
      司機端登入後用 `simctl terminate` + `launch` 重啟，**直接回到已登入首頁**
      → token 有寫進 Keychain 也讀得回來，沒有 `-34018`。

---

## 階段 4 — 雙 flavor（driver / customer）

Android 已用 `productFlavors` 分 `.driver` / `.customer`
（見 `android/app/build.gradle.kts`），iOS 目前**只有一個 Runner scheme**，要補對等設定。

- [x] **4-1 建立兩組 shared scheme** ✅ 2026-07-21：`driver`、`customer`
      （`ios/Runner.xcodeproj/xcshareddata/xcschemes/`），launch/test/analyze 走 `Debug-<flavor>`、
      profile 走 `Profile-<flavor>`、archive 走 `Release-<flavor>`。
- [x] **4-2 建立對應 build configuration** ✅ 2026-07-21
      9 組：原本的 `Debug/Release/Profile` 加上 driver／customer 各三組。
      `PRODUCT_BUNDLE_IDENTIFIER` = `dev.linefleet.line_fleet_app.driver` / `.customer`
      （與 Android `applicationId` + `applicationIdSuffix` 完全對齊）。
      **每個 flavor 配一個 `ios/Flutter/<Config>.xcconfig`**，各自 `#include?` 對應的
      `Pods-Runner.<config>.xcconfig` 再 `#include "Generated.xcconfig"`；
      `ios/Podfile` 的 `project 'Runner'` 對應表補上 6 個新 configuration，
      否則 `pod install` 不會產這些 xcconfig。
      **踩到的坑（兩個，都已修）**：
      1. 用 `xcodeproj` gem 新增的 base configuration 參照要寫成 `Flutter/Debug-driver.xcconfig`
         ——Flutter 群組本身沒有 `path`，只寫檔名會解析成 `ios/Debug-driver.xcconfig`（不存在），
         `pod install` 會警告「did not set the base configuration」。**用 `File.exist?(ref.real_path)` 驗**。
      2. **pbxproj 不要放非 ASCII**：中文顯示名寫進 build settings 後，`xcodeproj` 在
         沒有 UTF-8 locale 的 shell 讀檔會丟 `invalid byte sequence in US-ASCII`，
         而 `pod install` 每次都要讀它（`flutter` 呼叫 pod 時會自帶 `LANG`，手動跑就會炸）。
         改成把顯示名放 xcconfig，pbxproj 維持純 ASCII。
- [x] **4-3 顯示名稱分流** ✅ 2026-07-21：`Info.plist` 的 `CFBundleDisplayName` 改成
      `$(APP_DISPLAY_NAME)`，值在各 xcconfig 定義（司機端／乘客端／Line Fleet App）。
- [x] **4-4 驗收 ✅ 2026-07-21（iPhone 17 Pro 模擬器實跑）**
      `flutter run --flavor driver -t lib/main_driver.dart` 與
      `flutter run --flavor customer -t lib/main_customer.dart` 兩包都裝得起來且**互不覆蓋**：
      安裝後的 Info.plist 實測 —— driver 包 `CFBundleIdentifier=dev.linefleet.line_fleet_app.driver`／
      `CFBundleDisplayName=司機端`，customer 包對應 `.customer`／`乘客端`；
      **模擬器主畫面「司機端」「乘客端」兩個 icon 並存**（順手移除了無 flavor 的舊安裝）。
      ⚠️ 已知坑（見記憶卡 `pitfall-flutter-flavor-needs-target`）：`--flavor` 一定要配對 `-t`，
      漏了會裝出錯的那一端。

---

## 階段 5 — 實機部署（免費 Apple ID / Personal Team）

**現況：有實機、有 Apple ID，但非付費 Developer Program。** 免費帳號可以簽名裝上自己的裝置，
所以本階段做得了——而且能補掉 `docs/TODO.md` 裡 **A1 待驗的「鎖屏長跑背景定位」** iOS 那半。

- [ ] **5-1 Xcode Signing 設定**：Runner target → Signing & Capabilities →
      勾 Automatically manage signing → Team 選自己的 Personal Team。
      兩個 flavor 的 bundle id 都要能註冊成功。
- [ ] **5-2 裝置信任**：裝置接上後 Xcode 註冊裝置；首次安裝要在 iPhone
      設定 → 一般 → VPN 與裝置管理 → 信任該開發者憑證，否則點 App 會直接跳「不受信任的開發者」。
- [ ] **5-3 實機跑兩端**：
      `flutter run -d <device-id> -t lib/main_driver.dart --flavor driver --dart-define=API_BASE=http://<電腦區網IP>:8080`
      驗收：登入、WS 連得上（此時階段 3-3 的區網權限詢問會出現）。
- [ ] **5-4 A1 背景定位實機驗收（iOS 半邊）**：司機上線 → 鎖屏 10 分鐘 →
      確認後台地圖座標仍持續更新、狀態列有藍色定位指示
      （`showBackgroundLocationIndicator: true` 的效果）。
      這項模擬器測不出來，是本階段最主要的產出。
- [ ] **5-5 順帶實測 WS 降級邊界**（決定階段 6 的急迫性，見下）：
      iOS 司機端鎖屏／切到別的 App 時，WebSocket 派單還收不收得到。

### 免費帳號的三個硬限制（直接影響開發節奏）

1. **描述檔 7 天到期**：免費 Personal Team 簽的 App 約 7 天後就無法啟動，必須重新
   `flutter run` 重簽。跨週的長時間放置測試要留意這點，別把「App 打不開」誤判成 App bug。
2. **同時安裝數與 App ID 配額有上限**：driver + customer 兩個 flavor 佔 2 個名額，還算夠用；
   但別反覆亂改 bundle id，每 7 天的 App ID 註冊配額會被吃掉。
3. **不能用 TestFlight、不能上架**，也拿不到需付費才有的 capability（見階段 6）。

> 上述限制以執行當下 Xcode 實際回報的錯誤訊息為準；配額數字若有出入以 Apple 官方文件為準。

---

## 階段 6 — FCM 推播（司機端 A2 的 iOS 半邊）🔒 目前被帳號層級擋住

**阻塞原因：APNs 的 `aps-environment` entitlement 只開放給付費 Apple Developer Program（$99/年）。**
免費 Personal Team 在 Xcode 勾 Push Notifications capability 會被直接拒絕
（訊息類似 *Personal development teams do not support the Push Notifications capability*）。
這不是設定繞得過的問題，是帳號層級限制——**買帳號之前這階段完全動不了**。

### 在此之前 iOS 司機端能不能用？能，但降級

App 既有的 **WebSocket 派單路徑（`ride.assigned`）不依賴 APNs**，前景時接單完全正常。
司機上線時因為有背景定位 background mode，App 在背景**可能**維持存活、WS 不斷線——
**但這條推論尚未在 iOS 實機驗證**（所以列為 5-5）。App 被系統回收或使用者手動殺掉後一定收不到，
那正是推播存在的理由。

→ 5-5 的實測結果決定「iOS 司機端在買帳號前能不能小規模試用」，也決定買帳號的優先順序。

以下項目**待購買付費帳號後**執行：

- [ ] **6-1 Firebase Console 新增 iOS App**，bundle id `dev.linefleet.line_fleet_app.driver`，
      下載 `GoogleService-Info.plist` 放進 `ios/Runner/`（**加進 `.gitignore`**，比照
      `google-services.json` 的作法，repo 只留 `.example`）。
- [ ] **6-2 產生 APNs Auth Key（.p8）** 上傳到 Firebase Console → Cloud Messaging。
- [ ] **6-3 Xcode Capabilities**：Push Notifications + Background Modes
      （勾 Remote notifications、Location updates）。
- [ ] **6-4 `AppDelegate.swift`** 確認有 `FirebaseApp.configure()` 之前不會早於 Flutter 註冊；
      對照現有踩坑卡 `pitfall-firebase-instance-in-constructor`——Dart 端已修成
      initializeApp 之後才取 instance，iOS 端別再引入同型別問題。
- [ ] **6-5 真機驗收**：App 被殺 → 後端派單 → 收到推播 → 點擊可接單。
      推播 data 全是字串（`pitfall-fcm-data-all-strings`），已有回歸測試守著。
- [ ] **6-6 模擬器退路**：iOS 16+ 模擬器可用 `xcrun simctl push` 灌假推播測 UI，
      但**拿不到真 token**，只能驗畫面不能驗全鏈路。

---

## 階段 7 — 收尾

- [~] **7-1 CI 加 iOS job** —— **已寫好但推不上去（2026-07-21）**：
      `git push` 被 GitHub 擋下（`refusing to allow an OAuth App to create or update workflow
      ... without workflow scope`），改動留在本機工作區未提交。
      要納入請先 `gh auth refresh -h github.com -s workflow` 再提交，或把下面這段自己貼進檔案。
      內容：`.github/workflows/flutter-ci.yml` 新增
      `build-ios`（`macos-latest`），跑
      `flutter build ios --no-codesign --flavor customer -t lib/main_customer.dart`。
      只跑一個 flavor 控 macOS runner 時間——兩個 flavor 共用同一個 Runner target，
      會壞的東西（Podfile／xcconfig／Info.plist）一個就測得出來。
      **同一條指令已在本機跑過**：`✓ Built build/ios/iphoneos/Runner.app (20.4MB)`，
      且產物 Info.plist 是 `dev.linefleet.line_fleet_app.customer`／「乘客端」
      → 連 **Release-customer** configuration 都驗到了，不只 Debug。
- [x] **7-2 README 補 iOS 段** ✅ 2026-07-21：環境需求改寫（Xcode 26＋模擬器 runtime＋CocoaPods）、
      新增「iOS」章節（兩個 flavor 指令、bundle id、顯示名機制、ATS、`--flavor` 配對 `-t` 的坑、
      `GoogleService-Info.plist` 為何還沒導入）、以及 `API_BASE` 平台預設值對照表。
- [x] **7-3 回填 `docs/TODO.md` A5** ✅ 2026-07-21（A5 改 `[~]`，寫入階段 1–4 的實跑證據）。

---

## 風險與待決事項

1. **Apple 帳號只有免費 Personal Team（2026-07-20 確認）**：階段 1–5 全部不受影響，
   **只有階段 6（FCM 推播）動不了**。要不要買 $99/年，建議等 5-5 的 WS 降級實測結果再決定：
   若鎖屏／切換 App 時 WS 仍收得到派單，iOS 司機端可以先小規模試用；若收不到，推播就是上線前提，
   帳號要優先買。上架／TestFlight 同樣需要付費帳號。
2. **實機測試裝置：已有 ✅**。背景定位鎖屏長跑（A1 待驗項）現在做得了，是階段 5 的主要產出。
   免費簽名的 7 天到期限制會影響長時間放置測試，見階段 5。
3. **deployment target 拉到 15.0** 可能連帶影響其他套件版本，階段 2 若卡住優先看這裡。
4. **本規劃全部未實跑驗證**——階段 0 的環境現況是實測的，階段 1 之後的預期踩坑是依套件文件與
   既有 Android 設定推論，實際執行時以當下錯誤訊息為準。
