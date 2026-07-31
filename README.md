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
- **iOS**：Xcode 26+（`xcode-select -p` 要指向 `/Applications/Xcode.app/Contents/Developer`，
  不是 CommandLineTools）、iOS 模擬器 runtime（`xcodebuild -downloadPlatform iOS`）、
  **CocoaPods**（建議 `brew install cocoapods`，避開系統 Ruby 2.6）。
  `flutter doctor` 的 Xcode 與 CocoaPods 兩列都要是 ✓。詳見 [`docs/IOS_PLAN.md`](docs/IOS_PLAN.md)。

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

**`API_BASE` 的平台預設值**（沒帶 `--dart-define` 時，見
[`lib/core/config/app_config.dart`](lib/core/config/app_config.dart)）：

| 平台 | 預設 | 原因 |
| --- | --- | --- |
| Android 模擬器 | `http://10.0.2.2:8080` | 模擬器對映到主機 loopback 的專用位址 |
| iOS／macOS 模擬器 | `http://127.0.0.1:8080` | iOS 模擬器與主機共用網路，`10.0.2.2` 連不到 |
| 任何真機 | 無預設可用 | 一律要帶 `--dart-define=API_BASE=http://<電腦區網 IP>:8080` |

## iOS

兩個 flavor 與 Android 對齊（`.driver` / `.customer`），scheme 與 build configuration 都已建好：

```bash
flutter run -t lib/main_driver.dart --flavor driver      # 顯示名「司機端」
flutter run -t lib/main_customer.dart --flavor customer  # 顯示名「乘客端」
```

- **bundle id**：`dev.linefleet.line_fleet_app.driver` / `.customer`（與 Android `applicationId` 一致）。
- **顯示名**：`Info.plist` 的 `CFBundleDisplayName` 吃 `$(APP_DISPLAY_NAME)`，值在
  `ios/Flutter/<Configuration>.xcconfig`。
- **開發環境是 `http://` + `ws://`**：`Info.plist` 已設 ATS `NSAllowsLocalNetworking`
  （只放行本機／區網，沒有用 `NSAllowsArbitraryLoads`）＋ `NSLocalNetworkUsageDescription`。
- **`--flavor` 一定要配對 `-t`**，漏了會裝出另一端的 UI。
- **`GoogleService-Info.plist`（iOS 推播）尚未導入**：APNs 需要付費 Apple Developer Program，
  免費 Personal Team 拿不到 `aps-environment` entitlement。進度與計畫見
  [`docs/IOS_PLAN.md`](docs/IOS_PLAN.md) 階段 6。

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

### 乘客端推播（App 端接線已完成，2026-07-29）

乘客 flavor 的套件名是 **`dev.linefleet.line_fleet_app.customer`**，同樣需要一份
`google-services.json`（Firebase Console 可在同一個專案下新增第二個 Android App）。
登入後會自動 `POST /api/customer/device-token`、登出時 `DELETE` 註銷。

**乘客端的推播只當「去跟後端對一次帳」的訊號**，payload 不直接套用到畫面：
收到 `ride.accepted`／`driver.arrived`／`ride.completed`／`ride.cancelled`／`ride.redispatched`
任一則，App 就重讀 `GET /api/customer/rides/active` 與協尋清單。
理由是 FCM data 的值全是字串且欄位稀疏，直接灌進事件處理會把司機姓名／車牌／ETA 洗成空的——
REST 一定完整，而推播要傳達的資訊只有「有事發生了」。
所以**這一側沒有額外的 payload 契約**，後端只要帶 `type`（＋ `ride_id`）即可。

✅ **後端送出路徑已補上**（dispatch [PR #61](https://github.com/thothawei/fleet-dispatch/pull/61)，
2026-07-30）：`Dispatcher.NotifyCustomerRideUpdate` ＋ 五個發送點，data 正好只帶
`type` 與 `ride_id`。~~先前只有 `NotifyDriverRideOffer`，乘客 token 只是「存起來備用」。~~
**整條鏈路現在只剩 Firebase 憑證**（同 A2）——憑證放進來就該直接會動，不需再改程式碼。

## 功能進度

詳見 [`docs/TODO.md`](docs/TODO.md)。

- **司機端**：登入→hero 上線→前景服務 GPS→全螢幕接單→大按鈕導航（座標優先）／上車／完成（放棄二次確認）
- **乘客端**：登入→叫車（目的地優先）→階段畫面／地圖 sheet→WS ETA→取消／完成卡
- **司機收入頁（E1）**：首頁「我的收入」入口，月切換顯示趟數／營業額／手續費／實得／月會費／應付總公司，
  串後端 `GET /api/driver/earnings`；金額用 `lib/core/util/money.dart`（分→NT$）。
- **乘客完成卡車資（E2）**：`ride.completed` 帶 `fare_amount_cents` 時顯示「車資 NT$…」，
  與後端 F 系列＋admin 三端對帳通過。
- **即時聊天（2026-07-13）**：乘客↔司機行程內對話——WS `chat.message` 即時遞送（非留言板），
  共用 `RideChatScreen`（氣泡、未讀角標、斷線以 `after` 增量補歷史）；乘客「聯絡司機」、
  司機「聯絡乘客」入口。
- **遺失物協尋（2026-07-13）**：乘客完成卡「物品遺失？聯絡司機」→ 回報→顯示處理費
  （該趟車資×%，建單快照）→ 與司機對話 → 司機尋獲後支付處理費 → 歸還結案；
  司機端 AppBar「遺失物協尋」工作清單（已找到／已歸還／未尋獲結案）。
  處理費% 由 admin 費率設定頁調整（後端 `lost_item_fee_bps`）。
- **我的行程歷史（2026-07-19）**：乘客首頁右上「我的行程」→ 列出過去行程
  （狀態／路線／時間／車資）；**有司機的行程可事後「聯絡司機」**開對話
  （沿用 `RideChatScreen`）。後端 `GET /customer/rides`（只回本人，LEFT JOIN 司機名）。
- **乘客端多停靠點行程進度（2026-07-21）**：多乘客訂單在地圖上依序畫出全程停靠點
  （乘客標籤 A/B…）＋「司機→下一站→之後待處理站」折線，sheet 內「行程進度 N／M 站」
  與全程清單。司機每標記一站，WS **`ride.stop_updated`**（payload 帶整趟 stops）即時更新，
  乘客不必重整。**唯讀**：乘客只看進度，不做標記。單點訂單畫面不變。
  依賴後端 dispatch N8（customer active／單筆查詢帶 stops）。
- **司機端概覽地圖（2026-07-16）**：接單後行程卡內嵌地圖（flutter_map + OSM，免 key）——
  自己（綠色計程車）＋目標（前往上車點＝紅釘／行程中＝藍旗）＋兩點連線，相機自動框住兩點。
  **只做「看位置」，不做導航**——turn-by-turn 仍由「導航」按鈕跳外部 Google Maps／Waze。
- **連線韌性（2026-07-16）**：WS 握手完成才回報已連線（不再樂觀說謊）、背景連線不擋登入、
  硬斷線時清理有逾時保護（否則重連鏈會卡死）；司機端「上線但連線中斷」會明確顯示
  「暫時收不到派單」而非假裝正常；API 錯誤一律轉中文（`lib/core/api/api_error.dart`）。
- **UI/UX 翻新（2026-07-10）**：三端 LINE 綠亮暗雙主題。
- **多乘客／多停靠點行程（N，2026-07-17）**：一張訂單最多 **5 位乘客各自上下車**
  （最多 10 個停靠點）。乘客端 `StopsEditor` 漸進展開編輯（預設單一目的地不變）；
  司機端行程卡 `RideStopsList` 依序列出全程、只有下一站給操作（已上車／已下車／跳過）；
  概覽地圖 `DriverRideMap` 畫出全程停靠點＋折線串「司機→下一站→後續」，
  下一站全彩、之後半透明、已到達灰色、已跳過不畫。
- **司機車輛資訊（O，2026-07-17）**：車種選單＋車牌設定頁；**沒填不得接單**
  （`_DriverRoot` 強制跳轉、後端 O3 gate 也擋）；乘客端 `DriverVehicleCard`
  顯示車種／放大車牌／明碼電話（`tel:` 撥號）。
- **司機聯絡電話（O7 補洞，2026-07-22）**：設定頁多一欄「聯絡電話」，寫入走
  `PUT /api/driver/profile`（與車輛端點分開，改電話不重置 O5 審核）。
  在此之前 `drivers.phone` **沒有任何寫入路徑**，撥號按鈕從未出現過。
  乘客端的司機電話有兩條來源：WS `ride.accepted`（即時）與 `GET /customer/rides/active`
  （還原用，鍵名相同）——**只靠事件會在 app 背景被接單／重連／重開後永遠拿不到號碼**。
  已於模擬器實跑全鏈路（司機填號 → 乘客撥號盤帶出正確號碼）。
- **乘客指定車種＋寵物車清潔費（P／O6，2026-07-17）**：叫車表單 `VehicleTypePicker`
  （預設不指定）；選寵物車**當場**顯示加價%（查 `GET /api/customer/fees`，
  失敗降級「上限 30%」不擋叫車）；完成卡與司機收入頁**分項**顯示清潔費。
- **取消原因呈現（P4，2026-07-17）**：以機器可讀 `cancel_reason` 判斷（不 parse 文案），
  叫車表單頂部通知卡；指定車種找不到時給「改用不指定車種」快捷。

- **車輛審核四態（O5，2026-07-19）**：司機填/改車輛後需 admin 核准才能接單。
  `_DriverRoot` 四態——未填→強制設定頁、**待審核**→等待頁、**已退回**→顯示原因＋重送審、
  已核准→首頁；能不能接單以後端 `can_accept` 為準（App 不自行推導）。
  admin 端在司機管理頁核准／退回（退回須附原因）。

- **建單前車資預估（懸而未決 #1，2026-07-23）**：叫車表單顯示**預估車資**，
  地圖選目的地（單點）或停靠點填完（多停靠點）時自動算、車種變更時重算。
  後端新開 `POST /api/customer/rides/estimate`（以全程規劃路線試算，與完成計費共用
  `FeeSettings.Quote`）。**是預估不是定價**——實際依行駛路線於行程結束時結算，卡片明確標示；
  失敗靜默不擋叫車。**已模擬器實跑對帳**：App 建單→完成，完成卡車資與預估完全一致
  （不繞路時實收＝預估）。詳見 [`docs/TODO.md`](docs/TODO.md)「💰 建單前車資預估」。

- **乘客評分司機（B5，2026-07-27）**：完成卡「留下評分」開 1–5 星＋評論（選填）；
  **一趟一評、不可重評**（後端唯一索引，重送回 409）。完成卡關掉後仍可從「我的行程」補評——
  未評的完成行程給「評分」、已評顯示星等。司機在「我的收入」看得到自己的
  **服務評價（平均分／則數）**。後端新開 `POST /api/customer/rides/:id/rating`，
  讀回走 `CustomerRideView.rating`／歷史列 `rating_score`／`GET /driver/me` 的 `rating_avg`。
  **付款仍屬 Phase C**（需真金流），完成卡在無車資時保留費用佔位。
  **已模擬器實跑 E2E**（雙 flavor）：完成卡評分 → DB 交叉驗證 → 歷史補評 → 司機端
  「服務評價 4.5 ／ 5.0（2 則）」三處一致；實跑抓到並修掉一個後端文案 bug
  （評分被拒時講的是遺失物協尋）。
  **admin 端同批補完可見性**（2026-07-27）：司機管理頁「評價」欄（可排序）、訂單詳情「乘客評分」卡——
  至此三端齊備：**乘客評 → 司機看得到自己的平均分 → 營運看得出誰評價低**。
  詳見 [`docs/TODO.md`](docs/TODO.md)「⭐ 乘客評分司機」。

**目前**：`flutter analyze` 無 issue、`flutter test` **414 passed**（54 個測試檔，2026-07-31 實跑）。
~~383 passed~~／~~377 passed~~／~~361 passed~~／~~356 passed~~／~~351 passed~~／~~339 passed~~ 是漏更新的舊數字——**這一行請跟著最後一次實跑一起改**。

**2026-07-30 弱網逾時對帳的實跑收尾**（詳見 [`docs/TODO.md`](docs/TODO.md) 第十四～十五輪）：
先做了一支「請求照送、回應吃掉」的代理 [`tool/lossy_proxy.py`](tool/lossy_proxy.py)——
`docker pause` 造不出「後端其實成功、只是回應遺失」的正向競態，這條分支先前只有單元測試證據。
把它套到兩端各跑一輪，抓到兩個測試層抓不到的 bug：
- **司機端**（第十四輪）：`_markStop` 逾時對帳把錯誤清掉了，畫面卻沒收到通知——
  `return future;` 讓 `try/finally` 裡唯一那次 `notifyListeners()` 排在對帳之前，
  螢幕上留著一張「請求逾時」的幽靈橫幅。修法是 `return await`。
- **乘客端**（第十五輪）：`cancelOrder` 根本沒有對帳，於是**取消成功卻報成「請求逾時」**；
  WS 斷線時連「行程已取消」都沒有，乘客同時看到「訂單不見了」與「請求逾時」兩個矛盾訊號。
  補上 `_reconcileAfterCancel`（逾時／409 都問一次後端）後，畫面改為顯示「行程已取消。」。
  同批也把**乘客端建單逾時對帳**搬到模擬器上驗完（先前只有測試層證據）。
- **協尋單的六個寫入**（第十六輪）：兩端各三條（回報／付款／取消、標尋獲／標歸還／結案）
  **都沒有逾時對帳**，例外原樣丟給畫面。其中 `payLostItem` 是**付款**——逾時後乘客不知道
  自己付了沒有。兩端各補一支 `_writeLostItem`（逾時或 409 就查一次那張單），
  並在模擬器上驗到：付款回應被吃掉、WS 被擋，畫面仍自己變成「已付款，等待歸還」，
  DB 只收了一次款。
- **評分送出**（第十七輪）：`submitRating` 逾時後不對帳，而後端「一趟一評」有唯一索引——
  乘客看到「評分失敗」，再按一次只會拿到 409，而他其實已經評過了。
  改成逾時／409 時查一次 `GET /customer/rides/:id` 的 `ride.rating.score`；
  模擬器實跑驗到表單自己關閉、那一列變成 ★★★★☆「已評分」。
  **至此 App 兩端的寫入路徑逾時對帳全部補完**。
- **聊天送出**（第十八輪，跨端）：這條沒有唯一狀態可查——「同內容再送一次」本來就合法，
  所以改由客戶端產生冪等鍵、後端據此去重（dispatch
  [#68](https://github.com/thothawei/fleet-dispatch/pull/68) 的 migration 000024）。
  App 端逾時後補讀並**用鍵比對**：找到＝上一次其實送出了（泡泡出現、輸入框清空、不報錯）；
  找不到就留著內容與**同一個鍵**讓他重試——重試因為冪等而不會多一則。
  模擬器實跑＋真後端 curl 都驗過：同鍵重送回既有那筆，不同鍵的同內容仍是兩則。

**2026-07-30 這一批**（詳見 [`docs/TODO.md`](docs/TODO.md) 第十二～十三輪）：
- **對話訊息也會推播**：先前對話只走 WS，對方 App 一離開前景就收不到，訊息躺在伺服器上
  等他自己再打開——「司機到了要聯絡乘客」「乘客回報遺失物」都因此斷線。
  後端推給收訊那一方（dispatch PR #62），App 兩端收到後**只點亮未讀角標**
  （推播 data 沒有訊息本體，內容由聊天室以 REST 補齊）。
- **協尋單每一步也會推播**：建單／尋獲／付款／歸還都推給對方（dispatch PR #63），
  App 兩端收到後只重讀協尋清單。協尋是小時級的流程，雙方幾乎都不在前景。
- **後端側整條推播路徑已實跑驗證**（不需 Firebase 憑證，走 LogPusher stub）：
  一輪跑完 **10 則推播收件人全部正確**，且 data 一如 App 端假設只有 `type`＋`ride_id`；
  取消那三條另驗到「乘客自己取消完全沒有推播」。**只剩憑證**——手機真的響還沒驗過。
- **點推播喚醒的事件不再被丟掉**：`getInitialMessage()`（App 被殺後點通知的唯一管道）
  在 `runApp` 之前就把事件送進廣播串流，而 controller 要到 `init()` 才訂閱——
  廣播串流不緩衝，事件當場消失。**司機端「被殺 → 點推播 → 接單卡」與乘客端
  「點推播 → 對帳」兩條都是死路徑**。改成沒人訂閱時留著最後一則、第一個訂閱者上來補送。
- **後端補上乘客端推播的送出路徑**（dispatch PR #61）：先前 `notify.Dispatcher` 只有
  司機派單那一條，乘客註冊的 token 沒有任何用途。至此整條鏈路**只剩 Firebase 憑證**。

**2026-07-29 這一批**（詳見 [`docs/TODO.md`](docs/TODO.md) 第四～六輪 debug ＋「🧾 PR 佇列稽核」）：
- **回到前景會對帳**：背景期間 OS 凍結 timer、WS 可能被關掉，回前景時**立刻重連 WS**
  並向後端重新確認進行中行程（司機端沒有輪詢，漏掉的事件沒有第二條路補回來）。
- **搶輸的單不再給假行程卡**：後端當時對「這單已被其他司機接走」回的是 **HTTP 200＋文案**
  （**2026-07-30 後端已改為 409**，dispatch PR #64；App 這條防線留著仍無害），
  App 原本只看有沒有丟例外，於是沒搶到的司機會拿到一張完整但假的行程卡。
  現在接單與放棄的成敗**一律以後端的 `rides/active` 為準**。
- **弱網（連得上但通不了）**：位置回報一次只放一筆在路上、hero 在「已不在派單池」時
  誠實顯示紅底降級、接單／建單逾時後跟後端對帳。
- **WS 客戶端心跳**：半開連線（對端沒了但收不到 FIN）不會觸發 onDone／onError，
  重連鏈根本不會啟動——`pingInterval` 是唯一偵測得到的手段。
- **建單 409 不再是死路**：後端說「已有進行中的訂單」而畫面上一張都沒有時，
  改為向後端接手那張單。
- **司機端跨裝置的停靠點同步**：`ride.stop_updated` 原本只推給乘客（後端 dispatch#53 已補），
  司機端也不處理——兩台裝置會停在不同的「下一站」。

**2026-07-28 修掉的 4 個 bug**（每個都先寫測試看它 FAIL 才修，詳見
[`docs/TODO.md`](docs/TODO.md)「🐞 2026-07-28 debug」）：司機端 8 秒一次的定位探針會把
**業務錯誤**（如完成行程被 409 擋下）一起洗掉；乘客端 15 秒一次的背景輪詢失敗會不停彈
SnackBar；FCM token 輪替失敗會冒出司機看不懂也無事可做的紅色橫幅；
**司機放棄訂單時 App 乘客收不到任何事件**（後端只推 LINE，跨端對帳抓到）；
**production 首頁沒有遺失物協尋入口**（banner 只寫在非 production 的卡片版首頁，乘客付不了處理費就拿不回東西）。
三個「畫面沒人讀」類的修正已於同日在 `m6_pixel` 模擬器上**逐一實機閉環驗證**。

**2026-07-30 定位出口（第二十一～二十二輪，詳見 [`docs/TODO.md`](docs/TODO.md)）**：
司機端定位串流死掉時 hero 會降級成「位置回報失敗，暫時收不到派單」（`onError` 不再吞，
權限被撤與定位服務被關**分開講**）；乘客端叫車的三種定位失敗也各自有話講——
其中「系統定位服務被關」原本是**完全靜默**的（例外穿出 `placeOrder`，畫面一句話都沒有）。
另外，**多停靠點行程不再需要裝置定位**：pickup／dropoff 由 stops 推導，後端本來就不看那組座標。
兩端都在 `m6_pixel` 上以 `settings put secure location_mode 0` 實跑驗過。
**第二十三輪**再補一個真裝置才會發生的洞：**App 被系統收掉（或司機自己滑掉）再開時，
行程會被還原，但定位回報整段消失**——乘客端的司機 marker 定格、抵達圍籬不觸發、
里程軌跡缺一段，而司機看到的只是 hero 上那句「離線」。冷啟動還原到進行中行程時會接回回報
（只在已有權限時、且不在回前景時做，那顆離線鈕要按得掉）。
同一台裝置、同一張行程跑過修改前後兩個版本：修好的版本重開 8 秒後恢復回報，修改前 40 秒零筆。

- **預約司機＋常用地點（2026-07-31）**：乘客可預約**未來**的用車，以及把住家／公司等
  常去的地點存起來，叫車與預約時一鍵帶入。
  - **預約**：首頁 AppBar「預約司機」→ 選時間（最早可預約時間由後端給，不寫死）
    ＋起訖點＋備註。後端在約定時間前 **15 分鐘**自動轉成真訂單進派單池，
    之後就走既有的派單／推播／地圖鏈路。清單分三區：即將到來／車已在路上／過往。
    **已轉單的不能取消**（那張真訂單已在派單池）——取消撞 409 時畫面直接切成
    「已為你派車」並指出要去行程頁取消該趟訂單，不是丟一句「請稍後再試」。
  - **常用地點**：住家／公司是「插槽」（每人各一筆、設定即覆蓋），其他為自訂地點。
    判斷是不是住家一律看 `kind` 不比對名稱——名稱是使用者可以改的。
    帶入時**連座標一起帶**，所以照樣算得出車資預估（手打地址算不出來）。
  - 後端：dispatch 的 `scheduled_rides`／`customer_saved_places`（migration 000025／000026）。
    假資料見 dispatch 的 `scripts/seed_demo_data.sh`。

## 規劃中（尚未實作）

> 完整規格與待拍板事項見 [`docs/TODO.md`](docs/TODO.md) 與後端
> [line-fleet-dispatch/docs/TODO.md](../line-fleet-dispatch/docs/TODO.md)。

- 完成後付款（B5 的另一半，需真金流）。
- 預約的多停靠點、預約專屬推播（「已轉為訂單」／「預約未能成立」）、admin 端的預約管理
  ——三者都寫明了要等什麼條件才做，見 TODO「🗓️ 預約司機＋常用地點」那章最後一節。
- 依賴外部資源／實機的項目（A2 真裝置推播、A5 iOS 實機部署與 iOS 推播）——見 TODO。
- **維護項已於 2026-07-28 全數清空**（清殘留 worktree／舊分支、清 dev DB 測試殘留）；
  只剩「評分的營運動作」等營運說得出要對低分司機做什麼再開。
  **剩下的每一項都需要使用者先提供外部資源或拍板**——沒有前置條件時不要硬找事做。
- **開工前先看 PR 佇列**（`gh pr list`）：2026-07-29 盤點時三個 repo 共有 8 支未合併的
  open PR，其中兩支是**同一個功能的兩份獨立實作**——平行 worktree 的 session 看不見彼此，
  題目又都取自 TODO 的同一份清單。已合併／去重的經過見 TODO「🧾 PR 佇列稽核」。

## 相關文件

- API key 取得與免費測試流程：[`docs/API_KEYS_SETUP.md`](docs/API_KEYS_SETUP.md)
- 總體進度：`line-fleet-dispatch/docs/STATUS.md`
- 設計規格：`line-fleet-dispatch/docs/superpowers/specs/2026-07-06-fleet-dual-client-design.md`
