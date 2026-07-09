# Fleet 三端 UI/UX 全面翻新 — 設計規格

> 建立：2026-07-10。範圍：`line-fleet-app`（司機端＋乘客端 Flutter）與 `line-fleet-admin`（React 後台）。
> 本文件為 canonical 版本（放在 line-fleet-app repo）；line-fleet-admin repo 的
> `docs/superpowers/specs/` 有同步副本。
>
> 已確認決策：**視覺＋體驗全面翻新**／**LINE 系綠色品牌**／**乘客端地圖為底＋Bottom Sheet**／
> **亮暗雙主題跟隨系統**／**後台新增 Dashboard 首頁**。

## 0. 目標與非目標

**目標**

- 三端（乘客、司機、後台）共用一套設計語言：LINE 綠品牌色＋統一狀態語意色。
- 乘客端從「表單卡片流」升級為「地圖為底＋Bottom Sheet」的現代叫車體驗。
- 司機端以駕駛情境優化：大觸控目標、一眼可讀狀態、暗色模式。
- 後台品牌化並新增營運總覽 Dashboard。

**非目標（本次不做）**

- 不動任何 API／WebSocket 接線邏輯與後端契約（純 presentation 層重構）。
- 不實作評分／付款真功能（維持佔位，等後端 Phase C）。
- 不做 iOS build 驗收（沿用 TODO A5 延後）。

## 1. 共用設計系統

規格同源、兩 repo 各自落地一份實作。

### 1.1 色彩 tokens

| Token | Light | Dark | 用途 |
|---|---|---|---|
| `primary` | `#06C755` | `#3DD675` | 品牌主色、主行動按鈕 |
| `status.waiting` | 琥珀 `#FAAD14` 系 | 同系提亮 | 等待配對／待接單 |
| `status.active` | 藍 `#1677FF` 系 | 同系提亮 | 進行中（前往、行程中） |
| `status.done` | 綠（primary 系） | 同 | 已完成 |
| `status.danger` | 紅 `#F5222D` 系 | 同系提亮 | 取消、錯誤、放棄 |
| `status.offline` | 灰 | 灰 | 離線、未連線 |

狀態語意色三端一致：後台訂單 tag、司機端狀態、乘客端行程階段用同一套對照。

### 1.2 Flutter（line-fleet-app）

- 新增 `lib/core/theme/app_theme.dart`：
  - Material 3，`ColorScheme.fromSeed(seedColor: Color(0xFF06C755))`。
  - `lightTheme` / `darkTheme` 各一，`MaterialApp` 設 `themeMode: ThemeMode.system`。
  - 統一 tokens：卡片圓角 12、主行動按鈕最小高度 56、輸入框 `OutlineInputBorder` 統一。
  - 司機端與乘客端共用此檔（兩個 flavor 都套）。
- 新增 `lib/core/theme/ride_status_colors.dart`：行程／司機狀態 → 語意色對照。

### 1.3 React 後台（line-fleet-admin）

- 新增 `src/theme/tokens.ts`：AntD v5 `ConfigProvider` theme 物件
  （`colorPrimary: '#06C755'`、`borderRadius: 8`、字級），於 `App.tsx` 掛入，一處改全站生效。
- `src/constants.ts` 的狀態對照補上與 1.1 一致的 tag 色。

## 2. 乘客端（工程最大）

### 2.1 主畫面架構：地圖為底＋Bottom Sheet

`CustomerHomeScreen` 重構為：

- 全螢幕 `GoogleMap` 做背景（鏡頭跟隨目前定位／行程狀態）。
- `DraggableScrollableSheet` 底部抽層，依行程階段切換內容：

| 階段 | Sheet 內容 | 地圖行為 |
|---|---|---|
| 未叫車 | 「要去哪裡？」目的地優先輸入 → 地圖選點 → 確認叫車 | 置中目前定位 |
| 配對中（requested/assigned） | 搜尋動畫＋取消按鈕 | 置中上車點 |
| 司機途中（accepted） | 司機資訊卡＋ETA／距離 chip | 顯示司機 marker＋上車點，自動 fit bounds |
| 司機已抵達 | 「請與司機會合」提示卡 | 同上 |
| 行程中（picked_up） | 行程進行卡（目的地、司機） | 跟隨司機位置 |
| 完成 | 完成卡＋評分／費用佔位（disabled）＋「再叫一輛」 | 靜止 |

- 司機位置改為**直接畫在背景地圖上**（吃現有 WS `driver.location` 資料流），
  取代現在塞在卡片內的 `CustomerTrackingMap` 小地圖。

### 2.2 降級路徑（未設 Google Maps API key）

`AppConfig.mapsConfigured == false` 時自動退回**卡片版**（保留並精修現有卡片流），
功能不減：文字叫車、ETA 文字追蹤、狀態流全部可用。階段狀態元件抽成共用 widget，
兩種版面共用，避免雙份邏輯。

### 2.3 互動修正

- 移除手動「更新狀態」按鈕（WS 已即時）；卡片版保留下拉重整。
- AppBar 取消；登出／使用者改為地圖上浮動圓鈕（卡片版維持 AppBar）。
- 錯誤訊息改 SnackBar／sheet 內 inline 提示，不再頂在列表最上方。

## 3. 司機端

- **上線／離線 hero 區塊**：主畫面頂部大開關＋大字狀態（上線中＝primary 底、離線＝灰底），
  一眼可讀、一鍵切換。
- **除錯資訊收納**：WS／FCM／API base／GPS 座標移入可展開的「連線狀態」`ExpansionTile`，
  預設收合；主畫面只留一顆連線健康小圓點（綠=WS 通、灰=斷線）。
- **新派單全螢幕接單卡**：`pendingOffer` 出現時以全螢幕 overlay 呈現——上車點、目的地、
  距離、ETA 大字排版；「接單」`FilledButton` 高度 ≥ 56、「略過」為次要樣式。不做倒數計時
  （後端無 offer timeout 契約）。
- **行程進行中**：每階段唯一主行動大按鈕（導航→已上車→完成行程），56px 高置底；
  「放棄此單」降為文字按鈕並加 `AlertDialog` 二次確認。
- 暗色主題隨系統（§1.2），夜間駕駛不刺眼。

## 4. 後台（line-fleet-admin）

### 4.1 新增 Dashboard 首頁 `/`

- KPI 卡列：今日訂單數、完成／取消數、在線司機數、進行中行程數。
- 迷你車隊地圖（複用 FleetPage 地圖邏輯，唯讀縮小版）＋最近訂單表（前 10 筆）。
- **全部以既有 API 組合**（`/fleet`、`/rides`、`/drivers`、`/reports/daily`），不需後端新端點。
- 即時車隊完整地圖移到 `/fleet`，側欄選單同步調整（Dashboard 置頂）。

### 4.2 品牌與版面

- 掛 `ConfigProvider` LINE 綠主題（§1.3）；側欄改亮色＋品牌 logo 區；登入頁品牌化
  （置中卡片＋品牌色、去掉素面感）。

### 4.3 各頁精修

- 訂單／司機狀態 tag 對齊 §1.1 語意色。
- 統一頁面標題列（標題＋操作區）與麵包屑。
- 表格空狀態（`Empty` 客製文案）與載入骨架屏（`Skeleton`）。

## 5. 驗收與品質門檻

- **零功能回歸**：API／WS 接線邏輯不動；既有測試全數通過——
  `flutter analyze`＋`flutter test`（34 項，UI 文案改動同步更新斷言）、
  admin `vitest`＋`tsc -b`（build 過）。
- **視覺驗收**：admin 以瀏覽器實際載入逐頁檢查（含暗色系統設定下的表現）；
  app 以 Android 模擬器實跑主鏈路（乘客叫車→司機接單→上車→完成→乘客收到完成卡）。
- 乘客端需分別驗證「有 Maps key（地圖版）」與「無 key（卡片版）」兩條路徑。

## 6. 執行順序

1. **Admin**：tokens → Dashboard → 版面品牌化 → 各頁精修（瀏覽器立即驗收，先定調品牌）。
2. **司機端**：theme 落地 → hero 開關＋資訊收納 → 全螢幕接單卡 → 行程大按鈕。
3. **乘客端**：theme 套用 → 階段元件抽共用 → 卡片版精修（降級路徑先通）→ 地圖為底＋Bottom Sheet。

每階段完成即跑該 repo 測試並 commit；乘客端地圖版為最後一塊。
