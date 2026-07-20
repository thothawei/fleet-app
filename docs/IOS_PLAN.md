# iOS 開發規劃（A5 展開）

> 建立：2026-07-20。對應 [`docs/TODO.md`](TODO.md) 的 **A5. iOS build**。
> 本檔只做規劃，**尚未動任何 iOS 設定**。下次 session 依「階段」順序執行，每階段跑完驗收才往下。

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
- [ ] **1-4 安裝 CocoaPods**
      建議 `brew install cocoapods`（避開系統 Ruby 2.6）。
      驗收：`pod --version` 有輸出。
- [ ] **1-5 `flutter doctor -v`**
      驗收：Xcode 與 CocoaPods 兩列都是 ✓，無 `!`。

> ⚠️ 1-1 / 1-2 需要 sudo 密碼，Claude 無法代打。下次 session 開場請使用者自己跑這兩行，或允許互動輸入。

---

## 階段 2 — 首次 build 起來（先不管 flavor / 推播）

- [ ] **2-1 `flutter build ios --no-codesign -t lib/main_customer.dart`**
      這步會自動生成 `ios/Podfile` 並跑 `pod install`。
      預期踩坑：`firebase_*` 要求 iOS deployment target ≥ 15.0，Flutter 模板預設可能較低
      → 要同時改 `ios/Podfile` 的 `platform :ios, '15.0'` 與 Xcode target 的
      `IPHONEOS_DEPLOYMENT_TARGET`。
      驗收：build 成功產出 `.app`。
- [ ] **2-2 模擬器實跑乘客端**
      `open -a Simulator` → `flutter run -t lib/main_customer.dart --dart-define=API_BASE=http://127.0.0.1:8080`
      驗收：登入畫面出得來、地圖圖磚載得到。
- [ ] **2-3 `ios/Podfile` + `ios/Podfile.lock` 進版控**，`.gitignore` 確認沒把它們排除。

---

## 階段 3 — App 端 iOS 專屬缺口（實際要改的程式碼／設定）

以下都是掃過現有程式碼確認的**真實缺口**，不是通用清單：

- [ ] **3-1 `AppConfig.apiBase` 的 iOS 預設值**
      現況 [`lib/core/config/app_config.dart`](../lib/core/config/app_config.dart) 硬寫
      `http://10.0.2.2:8080`——那是 **Android 模擬器**專用位址，iOS 模擬器要用
      `http://127.0.0.1:8080`。
      作法：依 `Platform.isIOS` 分流預設值（`--dart-define` 仍優先）。
      驗收：iOS 模擬器不帶 `--dart-define` 也連得到本機後端。
- [ ] **3-2 ATS（App Transport Security）擋 http/ws**
      後端開發環境是 `http://` + `ws://`，iOS 預設全擋。
      作法：`ios/Runner/Info.plist` 加 `NSAppTransportSecurity` →
      `NSAllowsLocalNetworking = true`（只放行區網，不要用 `NSAllowsArbitraryLoads`）。
      驗收：模擬器能打 API 且 WebSocket 連得上（司機 marker 會動）。
- [ ] **3-3 區網權限說明（真機連電腦 IP 才會遇到）**
      iOS 14+ 存取區網要 `NSLocalNetworkUsageDescription`。
      驗收：真機第一次連 `192.168.x.x:8080` 時出現權限詢問並可連線。
- [ ] **3-4 背景定位 Info.plist 補齊**
      現況已有 `UIBackgroundModes: location` + 兩則位置用途說明 ✅；
      推播還需要補 `remote-notification` 到同一個 array。
      程式面 [`driver_location_settings.dart`](../lib/core/location/driver_location_settings.dart)
      的 `AppleSettings` 已寫好（`automotiveNavigation` + 不自動暫停），這塊不用改。
- [ ] **3-5 `permission_handler` 的 Podfile 巨集**
      這個套件在 iOS 要在 `Podfile` 的 `post_install` 明確開啟用到的權限巨集
      （`PERMISSION_NOTIFICATIONS` / `PERMISSION_LOCATION`），沒開的話 request 直接回 denied。
      對照現有用法：[`driver_location_permissions.dart`](../lib/core/location/driver_location_permissions.dart)
      用了 `Permission.notification` 與 `Permission.locationAlways`。
      驗收：司機端上線時 iOS 跳出通知與定位權限詢問。
- [ ] **3-6 `url_launcher` 開外部地圖**
      [`lib/core/util/maps.dart`](../lib/core/util/maps.dart) 開 Google Maps deep link；
      iOS 若要用 `comgooglemaps://` 需在 Info.plist 宣告 `LSApplicationQueriesSchemes`，
      否則 `canLaunchUrl` 回 false。退路：一律用 `https://maps.google.com/...`（免宣告，會開 Safari 或轉 App）。
      決策：**先走 https 退路**，真機驗完再決定要不要加 scheme。
- [ ] **3-7 `flutter_secure_storage` Keychain**
      iOS 走 Keychain，模擬器通常免設定；若出現 `-34018` 錯誤才需要加
      Keychain Sharing entitlement。列為觀察項，不預先加。

---

## 階段 4 — 雙 flavor（driver / customer）

Android 已用 `productFlavors` 分 `.driver` / `.customer`
（見 `android/app/build.gradle.kts`），iOS 目前**只有一個 Runner scheme**，要補對等設定。

- [ ] **4-1 建立兩組 Xcode scheme**：`driver`、`customer`。
- [ ] **4-2 建立對應 build configuration**
      （`Debug-driver` / `Release-driver` / `Profile-driver`，customer 同理），
      各自指向 `ios/Flutter/Debug.xcconfig` 等，並設定
      `PRODUCT_BUNDLE_IDENTIFIER = dev.linefleet.line_fleet_app.driver` / `.customer`
      —— 與 Android 的 `applicationIdSuffix` 對齊，否則 Firebase 認不出來。
- [ ] **4-3 顯示名稱分流**：`CFBundleDisplayName` 分別為「司機端」「乘客端」。
- [ ] **4-4 驗收**：
      `flutter run -t lib/main_driver.dart --flavor driver` 與
      `flutter run -t lib/main_customer.dart --flavor customer` 都能裝上模擬器且**不互相覆蓋**
      （兩個 icon 並存）。
      ⚠️ 已知坑（見記憶卡 `pitfall-flutter-flavor-needs-target`）：`--flavor` 一定要配對 `-t`，
      漏了會裝出錯的那一端。

---

## 階段 5 — FCM 推播（司機端 A2 的 iOS 半邊）

**前置條件：需要付費的 Apple Developer Program（$99/年）**——APNs key 沒有免費方案。
沒有帳號前，階段 1–4 全部可做，只有這階段卡住。

- [ ] **5-1 Firebase Console 新增 iOS App**，bundle id `dev.linefleet.line_fleet_app.driver`，
      下載 `GoogleService-Info.plist` 放進 `ios/Runner/`（**加進 `.gitignore`**，比照
      `google-services.json` 的作法，repo 只留 `.example`）。
- [ ] **5-2 產生 APNs Auth Key（.p8）** 上傳到 Firebase Console → Cloud Messaging。
- [ ] **5-3 Xcode Capabilities**：Push Notifications + Background Modes
      （勾 Remote notifications、Location updates）。
- [ ] **5-4 `AppDelegate.swift`** 確認有 `FirebaseApp.configure()` 之前不會早於 Flutter 註冊；
      對照現有踩坑卡 `pitfall-firebase-instance-in-constructor`——Dart 端已修成
      initializeApp 之後才取 instance，iOS 端別再引入同型別問題。
- [ ] **5-5 真機驗收**：App 被殺 → 後端派單 → 收到推播 → 點擊可接單。
      推播 data 全是字串（`pitfall-fcm-data-all-strings`），已有回歸測試守著。
- [ ] **5-6 模擬器退路**：iOS 16+ 模擬器可用 `xcrun simctl push` 灌假推播測 UI，
      但**拿不到真 token**，只能驗畫面不能驗全鏈路。

---

## 階段 6 — 收尾

- [ ] **6-1 CI 加 iOS job**：`.github/workflows/flutter-ci.yml` 補
      `macos-latest` 上的 `flutter build ios --no-codesign`（先只跑 customer flavor 控時間）。
- [ ] **6-2 README 補 iOS 段**：環境需求（Xcode 26 / CocoaPods）、兩個 flavor 的 run 指令、
      `API_BASE` 在 iOS 的差異、`GoogleService-Info.plist` 放置說明。
- [ ] **6-3 回填 `docs/TODO.md` A5**，把本檔各階段的實跑證據寫進去。

---

## 風險與待決事項

1. **Apple Developer 帳號**：階段 5 的硬前置。要先確認是否已有／要不要買——這決定 iOS 推播能不能做，
   也決定 TestFlight／上架的時程。
2. **實機測試裝置**：背景定位鎖屏長跑（A1 待驗項）與推播都必須真機，模擬器測不出來。
3. **deployment target 拉到 15.0** 可能連帶影響其他套件版本，階段 2 若卡住優先看這裡。
4. **本規劃全部未實跑驗證**——階段 0 的環境現況是實測的，階段 1 之後的預期踩坑是依套件文件與
   既有 Android 設定推論，實際執行時以當下錯誤訊息為準。
