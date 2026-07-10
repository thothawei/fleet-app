# App（司機端＋乘客端）UI/UX 翻新 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** line-fleet-app 兩個 flavor 套上 LINE 綠亮暗雙主題；司機端改為駕駛情境優化（hero 開關、全螢幕接單、大按鈕）；乘客端升級為地圖為底＋Bottom Sheet（無 Maps key 自動退回精修卡片版）。

**Architecture:** 純 presentation 層——`DriverController`／`CustomerController`、API、WS 完全不動。新增 `lib/core/theme/` 共用主題；乘客端把「階段內容」抽成共用 widget，卡片版與地圖版共用同一套狀態渲染邏輯。

**Tech Stack:** Flutter 3.44（Material 3）、provider、google_maps_flutter、`DraggableScrollableSheet`。

**Spec:** `docs/superpowers/specs/2026-07-10-fleet-ui-ux-redesign-design.md`

## Global Constraints

- 品牌主色 `#06C755`；深色模式 primary `#3DD675`；主行動按鈕最小高度 **56**；卡片圓角 **12**。
- 亮暗雙主題 `themeMode: ThemeMode.system`，司機、乘客兩 flavor 都套。
- 不動 controller／API／WS 邏輯；`test/driver_controller_test.dart` 等既有測試（34 項）必須維持通過，文案變動只改斷言字串、不刪 expect。
- 每個 task 結尾：`flutter analyze`（無 error）＋`flutter test` 全過才 commit。
- 工作目錄：本 worktree（分支 `claude/fleet-admin-app-ux-redesign-12cc74`）。

---

### Task 1: 共用主題（`lib/core/theme/`）＋兩 flavor 套用

**Files:**
- Create: `lib/core/theme/app_theme.dart`
- Create: `lib/core/theme/ride_status_colors.dart`
- Modify: `lib/driver/app.dart`、`lib/customer/app.dart`
- Test: `test/app_theme_test.dart`

**Interfaces:**
- Produces: `appLightTheme` / `appDarkTheme`（`ThemeData`）、`kBrandGreen`、`kPrimaryActionHeight = 56.0`、`rideStatusColor(BuildContext, RideStatus) → Color`、`driverPhaseColor(BuildContext, DriverRidePhase) → Color`。後續 task 的按鈕與狀態元件都引用這些。

- [ ] **Step 1: 寫失敗測試 `test/app_theme_test.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/theme/app_theme.dart';

void main() {
  test('亮暗主題以 LINE 綠為 seed、Material 3', () {
    expect(kBrandGreen, const Color(0xFF06C755));
    expect(appLightTheme.useMaterial3, isTrue);
    expect(appLightTheme.brightness, Brightness.light);
    expect(appDarkTheme.brightness, Brightness.dark);
    // 深色模式 primary 用提亮綠（spec §1.1）
    expect(appDarkTheme.colorScheme.primary, const Color(0xFF3DD675));
  });

  test('主行動按鈕高度 token 為 56', () {
    expect(kPrimaryActionHeight, 56.0);
  });
}
```

- [ ] **Step 2: 跑測試確認失敗**

Run: `flutter test test/app_theme_test.dart`
Expected: FAIL（找不到 `app_theme.dart`）

- [ ] **Step 3: 實作 `lib/core/theme/app_theme.dart`**

```dart
import 'package:flutter/material.dart';

/// LINE 綠品牌主色（spec §1.1，三端統一）
const kBrandGreen = Color(0xFF06C755);

/// 深色模式提亮綠——深底上維持對比
const kBrandGreenDark = Color(0xFF3DD675);

/// 主行動按鈕最小高度（駕駛情境大觸控目標，spec §3）
const kPrimaryActionHeight = 56.0;

/// 卡片統一圓角
const kCardRadius = 12.0;

ThemeData _base(Brightness brightness) {
  var scheme = ColorScheme.fromSeed(
    seedColor: kBrandGreen,
    brightness: brightness,
  );
  if (brightness == Brightness.dark) {
    scheme = scheme.copyWith(primary: kBrandGreenDark);
  }
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    cardTheme: CardThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kCardRadius),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kCardRadius),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kCardRadius),
        ),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
  );
}

final appLightTheme = _base(Brightness.light);
final appDarkTheme = _base(Brightness.dark);
```

（若 Flutter 版本仍要求 `CardTheme` 而非 `CardThemeData`，以 `flutter analyze` 結果為準調整型別，其餘不變。）

- [ ] **Step 4: 實作 `lib/core/theme/ride_status_colors.dart`**

```dart
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../../driver/driver_controller.dart';

/// 行程狀態 → 語意色（spec §1.1：等待=琥珀、進行=藍、完成=綠、取消=紅）
Color rideStatusColor(BuildContext context, RideStatus status) {
  final scheme = Theme.of(context).colorScheme;
  return switch (status) {
    RideStatus.requested || RideStatus.assigned => const Color(0xFFFAAD14),
    RideStatus.accepted || RideStatus.pickedUp => const Color(0xFF1677FF),
    RideStatus.completed => scheme.primary,
    RideStatus.cancelled => scheme.error,
    _ => scheme.outline,
  };
}

/// 司機端行程階段 → 語意色
Color driverPhaseColor(BuildContext context, DriverRidePhase phase) {
  final scheme = Theme.of(context).colorScheme;
  return switch (phase) {
    DriverRidePhase.enRouteToPickup || DriverRidePhase.onTrip =>
      const Color(0xFF1677FF),
    _ => scheme.outline,
  };
}
```

（`RideStatus`／`DriverRidePhase` 的實際 enum 值以 `lib/core/models/models.dart`、`lib/driver/driver_controller.dart` 現況為準；若名稱不同，對照修正 switch 分支，不新增 enum。）

- [ ] **Step 5: 兩 flavor 套用**

`lib/driver/app.dart` 與 `lib/customer/app.dart` 的 `MaterialApp` 改為：

```dart
theme: appLightTheme,
darkTheme: appDarkTheme,
themeMode: ThemeMode.system,
```

移除原本 inline `ThemeData(...)`（司機端 `0xFF00695C`、乘客端 `0xFF1565C0` 兩個舊 seed 淘汰），加 `import '../core/theme/app_theme.dart';`。

- [ ] **Step 6: 驗證 + commit**

Run: `flutter analyze && flutter test`
Expected: analyze 無 error；全部測試過。

```bash
git add lib/core/theme/ lib/driver/app.dart lib/customer/app.dart test/app_theme_test.dart
git commit -m "feat(theme): LINE 綠亮暗雙主題＋語意色 tokens（App UI/UX Task 1）"
```

---

### Task 2: 司機端——hero 上線開關＋診斷資訊收納

**Files:**
- Create: `lib/driver/widgets/online_hero_card.dart`
- Create: `lib/driver/widgets/connection_details_tile.dart`
- Modify: `lib/driver/screens/driver_home_screen.dart`
- Test: `test/driver_home_widget_test.dart`

**Interfaces:**
- Consumes: `DriverController`（`online`、`wsConnected`、`fcmAvailable`、`fcmTokenPrefix`、`lastPosition`、`loading`、`toggleOnline()`——全部既有）；`kBrandGreen`（Task 1）。
- Produces: `OnlineHeroCard(ctrl:)`、`ConnectionDetailsTile(ctrl:)` 兩個 widget，Task 3、4 改版後的 home screen 繼續使用。

- [ ] **Step 1: 寫失敗 widget 測試 `test/driver_home_widget_test.dart`**

依 `test/driver_controller_test.dart` 既有的 FakeApi／MemoryAuthStore／silent WS 注入模式建立已登入的 `DriverController`，pump `DriverHomeScreen`：

```dart
testWidgets('離線時 hero 顯示「離線」且診斷資訊預設收合', (tester) async {
  await tester.pumpWidget(buildTestApp()); // 沿用 controller 測試的注入 helper
  expect(find.text('離線'), findsOneWidget);
  expect(find.text('目前不會收到派單'), findsOneWidget);
  // 收合狀態下不直接顯示 API base
  expect(find.textContaining('http'), findsNothing);
  // 展開「連線狀態」後才看得到
  await tester.tap(find.text('連線狀態'));
  await tester.pumpAndSettle();
  expect(find.textContaining('http'), findsOneWidget);
});
```

Run: `flutter test test/driver_home_widget_test.dart` → Expected: FAIL（尚無「目前不會收到派單」／「連線狀態」）。

- [ ] **Step 2: 實作 `lib/driver/widgets/online_hero_card.dart`**

```dart
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../driver_controller.dart';

/// 主畫面頂部大開關：一眼可讀上線狀態、一鍵切換（spec §3）
class OnlineHeroCard extends StatelessWidget {
  const OnlineHeroCard({required this.ctrl, super.key});

  final DriverController ctrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final online = ctrl.online;
    return Card(
      color: online ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(
              online ? Icons.local_taxi : Icons.power_settings_new,
              size: 40,
              color: online ? scheme.primary : scheme.outline,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    online ? '上線中' : '離線',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    online ? '等待派單中' : '目前不會收到派單',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            Transform.scale(
              scale: 1.3,
              child: Switch(
                value: online,
                onChanged: ctrl.loading ? null : (_) => ctrl.toggleOnline(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: 實作 `lib/driver/widgets/connection_details_tile.dart`**

```dart
import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../driver_controller.dart';

/// 診斷資訊收納：WS/FCM/API/GPS 移入可展開區塊，預設收合（spec §3）
class ConnectionDetailsTile extends StatelessWidget {
  const ConnectionDetailsTile({required this.ctrl, super.key});

  final DriverController ctrl;

  @override
  Widget build(BuildContext context) {
    final pos = ctrl.lastPosition;
    final healthy = ctrl.wsConnected;
    return Card(
      child: ExpansionTile(
        leading: Icon(
          Icons.circle,
          size: 12,
          color: healthy ? Theme.of(context).colorScheme.primary : Colors.grey,
        ),
        title: const Text('連線狀態'),
        subtitle: Text(healthy ? '即時連線正常' : '未連線，派單可能延遲'),
        shape: const Border(),
        children: [
          _row(context, 'WebSocket', ctrl.wsConnected ? '已連線' : '未連線'),
          _row(
            context,
            'FCM 推播',
            ctrl.fcmAvailable
                ? (ctrl.fcmTokenPrefix != null
                    ? '已註冊 ${ctrl.fcmTokenPrefix}'
                    : '已啟用（待 token）')
                : '未設定 Firebase',
          ),
          _row(context, 'API', AppConfig.apiBase),
          if (pos != null)
            _row(
              context,
              'GPS',
              '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}',
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: `driver_home_screen.dart` 換裝**

body 的 `ListView` children 改為：

```dart
children: [
  OnlineHeroCard(ctrl: ctrl),
  const SizedBox(height: 12),
  if (ctrl.error != null) _ErrorBanner(message: ctrl.error!),
  if (ctrl.activeRide != null) _ActiveRideCard(ctrl: ctrl),
  if (ctrl.activeRide == null && ctrl.pendingOffer == null) _IdleHint(),
  const SizedBox(height: 12),
  ConnectionDetailsTile(ctrl: ctrl),
],
```

- 刪除 `_StatusCard`／`_InfoRow`（診斷已移入 tile；`_ErrorBanner` 為錯誤文字獨立小 widget，用 `scheme.errorContainer` 底色卡片包 `ctrl.error!`）。
- `_OfferCard` 這一步先保留原樣（Task 3 改全螢幕）。
- `_IdleHint` 文案改精簡：「上線後將自動回報位置並接收派單。」（GPS 細節說明移進 ConnectionDetailsTile 不需要，直接刪）。

- [ ] **Step 5: 驗證 + commit**

Run: `flutter analyze && flutter test`
Expected: 全過（新 widget 測試含在內）。

```bash
git add lib/driver/widgets/ lib/driver/screens/driver_home_screen.dart test/driver_home_widget_test.dart
git commit -m "feat(driver): hero 上線開關＋診斷資訊收納（Task 2）"
```

---

### Task 3: 司機端——全螢幕接單卡

**Files:**
- Create: `lib/driver/widgets/offer_overlay.dart`
- Modify: `lib/driver/screens/driver_home_screen.dart`
- Test: `test/driver_home_widget_test.dart`（追加案例）

**Interfaces:**
- Consumes: `ctrl.pendingOffer`（`rideId`、`address`、`dropoffAddress`、`distM`、`etaLabel`）、`ctrl.acceptOffer()`、`ctrl.dismissOffer()`、`kPrimaryActionHeight`。
- Produces: `OfferOverlay(ctrl:)`——`pendingOffer != null` 時蓋滿全螢幕。

- [ ] **Step 1: 追加失敗測試**

```dart
testWidgets('收到派單顯示全螢幕接單卡，接單鈕高度 >= 56', (tester) async {
  await tester.pumpWidget(buildTestApp(withPendingOffer: true));
  await tester.pump();
  expect(find.text('新派單'), findsOneWidget);
  expect(find.text('接單'), findsOneWidget);
  final size = tester.getSize(find.widgetWithText(FilledButton, '接單'));
  expect(size.height, greaterThanOrEqualTo(56));
});
```

Run: `flutter test test/driver_home_widget_test.dart` → Expected: FAIL。

- [ ] **Step 2: 實作 `lib/driver/widgets/offer_overlay.dart`**

```dart
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../driver_controller.dart';

/// 新派單全螢幕接單卡：大字資訊＋大觸控目標（spec §3）
class OfferOverlay extends StatelessWidget {
  const OfferOverlay({required this.ctrl, super.key});

  final DriverController ctrl;

  @override
  Widget build(BuildContext context) {
    final offer = ctrl.pendingOffer!;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      color: scheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Text('新派單', style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
              Text('#${offer.rideId}', style: text.titleMedium?.copyWith(color: scheme.outline)),
              const SizedBox(height: 24),
              _InfoBlock(icon: Icons.my_location, label: '上車點', value: offer.address),
              if (offer.dropoffAddress != null && offer.dropoffAddress!.isNotEmpty) ...[
                const SizedBox(height: 16),
                _InfoBlock(icon: Icons.place, label: '目的地', value: offer.dropoffAddress!),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  if (offer.distM != null) Chip(label: Text('距離約 ${offer.distM} 公尺')),
                  if (offer.etaLabel.isNotEmpty) Chip(label: Text('ETA ${offer.etaLabel}')),
                ],
              ),
              const Spacer(),
              FilledButton(
                onPressed: ctrl.loading ? null : ctrl.acceptOffer,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(kPrimaryActionHeight),
                  textStyle: text.titleLarge,
                ),
                child: const Text('接單'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: ctrl.loading ? null : ctrl.dismissOffer,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(kPrimaryActionHeight),
                ),
                child: const Text('略過'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: text.bodySmall),
              Text(value, style: text.titleLarge),
            ],
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 3: home screen 以 Stack 蓋 overlay**

`DriverHomeScreen.build` 回傳改為：

```dart
return Stack(
  children: [
    Scaffold(/* 原本內容，ListView 中移除 _OfferCard 分支 */),
    if (ctrl.pendingOffer != null) OfferOverlay(ctrl: ctrl),
  ],
);
```

並刪除 `_OfferCard` class。

- [ ] **Step 4: 驗證 + commit**

Run: `flutter analyze && flutter test` → Expected: 全過。

```bash
git add lib/driver/widgets/offer_overlay.dart lib/driver/screens/driver_home_screen.dart test/driver_home_widget_test.dart
git commit -m "feat(driver): 全螢幕接單卡（Task 3）"
```

---

### Task 4: 司機端——行程階段大按鈕＋放棄二次確認

**Files:**
- Modify: `lib/driver/screens/driver_home_screen.dart`（`_ActiveRideCard`）
- Test: `test/driver_home_widget_test.dart`（追加案例）

**Interfaces:**
- Consumes: `ctrl.activeRide`（`phase`、`address`、`dropoffAddress`）、`ctrl.pickUpPassenger()`、`ctrl.completeTrip()`、`ctrl.abandonTrip()`、`openMapsNavigation()`、`kPrimaryActionHeight`、`driverPhaseColor`。

- [ ] **Step 1: 追加失敗測試**

```dart
testWidgets('放棄此單需二次確認', (tester) async {
  await tester.pumpWidget(buildTestApp(withActiveRide: true));
  await tester.pump();
  await tester.tap(find.text('放棄此單'));
  await tester.pumpAndSettle();
  expect(find.text('確定放棄這筆訂單？'), findsOneWidget); // AlertDialog
  await tester.tap(find.text('返回'));
  await tester.pumpAndSettle();
  expect(find.text('確定放棄這筆訂單？'), findsNothing);
});
```

Run: `flutter test test/driver_home_widget_test.dart` → Expected: FAIL。

- [ ] **Step 2: `_ActiveRideCard` 改版**

- 標題列加階段色 chip：`Chip(label: Text(phaseLabel), backgroundColor: driverPhaseColor(context, ride.phase).withValues(alpha: 0.15))`。
- 主行動按鈕統一 `minimumSize: const Size.fromHeight(kPrimaryActionHeight)`、`textStyle: titleMedium`：
  - `enRouteToPickup`：主鈕「乘客已上車」；導航為 `OutlinedButton.icon`（次要）。
  - `onTrip`：主鈕「完成行程」；導航去目的地為次要。
- 「放棄此單」改為：

```dart
TextButton(
  style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
  onPressed: ctrl.loading
      ? null
      : () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogCtx) => AlertDialog(
              title: const Text('確定放棄這筆訂單？'),
              content: const Text('放棄後這筆訂單會回到派單池。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(false),
                  child: const Text('返回'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(true),
                  child: const Text('確定放棄'),
                ),
              ],
            ),
          );
          if (confirmed == true) await ctrl.abandonTrip();
        },
  child: const Text('放棄此單'),
),
```

- [ ] **Step 3: 驗證 + commit**

Run: `flutter analyze && flutter test` → Expected: 全過。

```bash
git add lib/driver/screens/driver_home_screen.dart test/driver_home_widget_test.dart
git commit -m "feat(driver): 行程大按鈕＋放棄二次確認（Task 4）"
```

---

### Task 5: 乘客端——階段內容抽共用＋卡片版精修

**Files:**
- Create: `lib/customer/widgets/ride_phase_content.dart`
- Modify: `lib/customer/screens/customer_home_screen.dart`
- Test: `test/customer_home_widget_test.dart`

**Interfaces:**
- Consumes: `CustomerController`（`activeRide`、`completedSummary`、`driverName`、`driverArrived`、`liveDistM`、`liveEtaSec`、`wsConnected`、`busy`、`cancelOrder()`、`refreshActive()`、`dismissCompleted()`——全部既有）。
- Produces（Task 6 地圖版直接複用）:
  - `SearchingContent(ctrl:)`——配對中：進度動畫＋「取消叫車」。
  - `DriverEnRouteContent(ctrl:)`——司機途中／已抵達：司機名、ETA/距離 chip、取消。
  - `OnTripContent(ctrl:)`——行程中：目的地、司機。
  - `CompletedContent(ctrl:)`——完成卡＋評分／費用 disabled＋「再叫一輛」。
  - 現有 `_approachText`／`_phaseHint` 邏輯搬進這些 widget（邏輯不變，位置改變）。

- [ ] **Step 1: 寫失敗 widget 測試**

`test/customer_home_widget_test.dart`：以注入 fake controller 的方式 pump `CustomerHomeScreen`（比照 driver 測試模式；`CustomerController` 若無注入建構子，加最小可測建構子參數是允許的 presentation 配套）：

```dart
testWidgets('配對中顯示搜尋動畫與取消，且沒有「更新狀態」按鈕', (tester) async {
  await tester.pumpWidget(buildCustomerTestApp(phase: TestPhase.searching));
  expect(find.text('正在為您配對司機'), findsOneWidget);
  expect(find.text('取消叫車'), findsOneWidget);
  expect(find.text('更新狀態'), findsNothing);
});

testWidgets('完成態顯示評分佔位與再叫一輛', (tester) async {
  await tester.pumpWidget(buildCustomerTestApp(phase: TestPhase.completed));
  expect(find.text('行程已完成'), findsOneWidget);
  expect(find.text('再叫一輛'), findsOneWidget);
});
```

Run: `flutter test test/customer_home_widget_test.dart` → Expected: FAIL。

- [ ] **Step 2: 實作 `ride_phase_content.dart`**

四個 widget 都是純呈現（吃 ctrl 讀值＋呼叫既有方法）。`SearchingContent` 核心：

```dart
class SearchingContent extends StatelessWidget {
  const SearchingContent({required this.ctrl, super.key});

  final CustomerController ctrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 16),
        Center(
          child: Text('正在為您配對司機',
              style: Theme.of(context).textTheme.titleMedium),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text('通常在 1 分鐘內完成',
              style: Theme.of(context).textTheme.bodySmall),
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: ctrl.busy ? null : () => ctrl.cancelOrder(),
          child: const Text('取消叫車'),
        ),
      ],
    );
  }
}
```

`DriverEnRouteContent`：司機名列＋`Wrap` chips（`距您約 X 公尺`／`約 X 分鐘抵達`，邏輯搬自 `_approachText`）＋已抵達時改「請與司機會合」提示＋可取消時「取消叫車」。`OnTripContent`：階段標題「行程進行中」＋目的地＋司機名。`CompletedContent`：搬 `_CompletedRideCard` 內容（按鈕維持 disabled 佔位）。

- [ ] **Step 3: `customer_home_screen.dart` 改用共用元件**

- `_ActiveRideCard`／`_CompletedRideCard` 改為薄殼：Card 內依 `ride.status` 切換 `SearchingContent`／`DriverEnRouteContent`／`OnTripContent`／`CompletedContent`；小地圖 `CustomerTrackingMap` 維持現有條件顯示（地圖版在 Task 6 才接手）。
- **移除「更新狀態」按鈕**；`ListView` 外包 `RefreshIndicator(onRefresh: () => ctrl.refreshActive())`。
- 錯誤顯示改：`ctrl.error` 不再置頂文字，改在 build 後以 `ScaffoldMessenger.showSnackBar` 呈現（用 `WidgetsBinding.instance.addPostFrameCallback` 防重複，僅在 error 值變化時彈）。

- [ ] **Step 4: 驗證 + commit**

Run: `flutter analyze && flutter test` → Expected: 全過。

```bash
git add lib/customer/widgets/ride_phase_content.dart lib/customer/screens/customer_home_screen.dart test/customer_home_widget_test.dart
git commit -m "feat(customer): 階段元件抽共用＋卡片版精修（Task 5）"
```

---

### Task 6: 乘客端——地圖為底＋Bottom Sheet

**Files:**
- Create: `lib/customer/screens/customer_map_home_screen.dart`
- Modify: `lib/customer/screens/customer_home_screen.dart`（只留卡片版，改名內容不動）
- Modify: `lib/customer/app.dart`（依 `AppConfig.mapsConfigured` 選版面）
- Test: `test/customer_home_widget_test.dart`（追加降級路徑案例）

**Interfaces:**
- Consumes: Task 5 的四個 phase widget、`AppConfig.mapsConfigured`、`ctrl.lastPosition`、`ctrl.liveDriverLat/Lng`、`ride.pickupLat/Lng`、`MapPickerScreen`（既有）。
- Produces: `CustomerMapHomeScreen`——全螢幕 `GoogleMap` ＋ `DraggableScrollableSheet`。

- [ ] **Step 1: 追加降級路徑測試**

```dart
testWidgets('未設 Maps key 時走卡片版（有 AppBar）', (tester) async {
  // 測試環境 GOOGLE_MAPS_API_KEY 為空 → mapsConfigured=false
  await tester.pumpWidget(buildCustomerTestApp(phase: TestPhase.idle));
  expect(find.byType(AppBar), findsOneWidget);
  expect(find.text('叫車'), findsWidgets);
});
```

Run: `flutter test test/customer_home_widget_test.dart` → Expected: 先 PASS（守住降級路徑基準線，之後改版不得破壞）。

- [ ] **Step 2: 實作 `customer_map_home_screen.dart`**

結構（完整骨架，phase widget 直接複用 Task 5 產出）：

```dart
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/models/models.dart';
import '../customer_controller.dart';
import '../widgets/ride_phase_content.dart';
import 'map_picker_screen.dart';

/// 地圖為底＋Bottom Sheet 主畫面（spec §2.1）；
/// 僅在 AppConfig.mapsConfigured 時使用，否則走 CustomerHomeScreen 卡片版。
class CustomerMapHomeScreen extends StatefulWidget {
  const CustomerMapHomeScreen({super.key});

  @override
  State<CustomerMapHomeScreen> createState() => _CustomerMapHomeScreenState();
}

class _CustomerMapHomeScreenState extends State<CustomerMapHomeScreen> {
  GoogleMapController? _map;

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CustomerController>();
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _initialTarget(ctrl),
              zoom: 15,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            onMapCreated: (c) => _map = c,
            markers: _markers(ctrl),
          ),
          // 右上浮動登出鈕（spec §2.3）
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 16,
            child: FloatingActionButton.small(
              heroTag: 'logout',
              onPressed: ctrl.loading ? null : () => ctrl.logout(),
              child: const Icon(Icons.logout),
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.42,
            minChildSize: 0.25,
            maxChildSize: 0.85,
            builder: (context, scrollCtrl) => DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: const [
                  BoxShadow(blurRadius: 12, color: Colors.black26),
                ],
              ),
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _sheetContent(ctrl),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sheetContent(CustomerController ctrl) {
    if (ctrl.completedSummary != null) return CompletedContent(ctrl: ctrl);
    final ride = ctrl.activeRide;
    if (ride == null) return OrderFormContent(ctrl: ctrl); // 叫車表單（見 Step 3）
    return switch (ride.status) {
      RideStatus.requested || RideStatus.assigned => SearchingContent(ctrl: ctrl),
      RideStatus.accepted => DriverEnRouteContent(ctrl: ctrl),
      RideStatus.pickedUp => OnTripContent(ctrl: ctrl),
      _ => OrderFormContent(ctrl: ctrl),
    };
  }

  LatLng _initialTarget(CustomerController ctrl) {
    final pos = ctrl.lastPosition;
    if (pos != null) return LatLng(pos.latitude, pos.longitude);
    return const LatLng(25.0330, 121.5654); // 台北市中心 fallback
  }

  Set<Marker> _markers(CustomerController ctrl) {
    final markers = <Marker>{};
    final ride = ctrl.activeRide;
    final pickupLat = ride?.pickupLat ?? ctrl.lastPosition?.latitude;
    final pickupLng = ride?.pickupLng ?? ctrl.lastPosition?.longitude;
    if (ride != null && pickupLat != null && pickupLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('pickup'),
        position: LatLng(pickupLat, pickupLng),
      ));
    }
    if (ctrl.liveDriverLat != null && ctrl.liveDriverLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('driver'),
        position: LatLng(ctrl.liveDriverLat!, ctrl.liveDriverLng!),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ));
    }
    return markers;
  }
}
```

司機 marker 移動時鏡頭跟隨：在 `build` 中比較上次 driver 座標，變化即 `_map?.animateCamera(CameraUpdate.newLatLng(...))`（保留 `_lastDriverLat/Lng` state 欄位）。

- [ ] **Step 3: 叫車表單抽成 `OrderFormContent`**

把 `customer_home_screen.dart` 的 `_OrderForm`（含 `_pickOnMap`／`_submit`／地圖選點座標失效邏輯，**一行不改**）搬到 `ride_phase_content.dart` 改名 `OrderFormContent` 公開，卡片版與地圖版共用；標題文案改「要去哪裡？」、目的地欄位放最上（目的地優先，spec §2.1）。

- [ ] **Step 4: `customer/app.dart` 選版面**

```dart
home: AppConfig.mapsConfigured
    ? const CustomerMapHomeScreen()
    : const CustomerHomeScreen(),
```

（放在 `_CustomerRoot` 的已登入分支。）

- [ ] **Step 5: 驗證 + commit**

Run: `flutter analyze && flutter test`
Expected: 全過（測試環境無 Maps key，widget 測試全部走卡片版路徑——地圖版由 Task 7 模擬器實測驗收）。

```bash
git add lib/customer/ test/customer_home_widget_test.dart
git commit -m "feat(customer): 地圖為底＋Bottom Sheet 主畫面（Task 6）"
```

---

### Task 7: 整體驗收（模擬器實跑）＋文件收尾

**Files:**
- Modify: `README.md`（結構段補 `core/theme/`、雙主題說明）、`docs/TODO.md`（回填本次翻新）

- [ ] **Step 1: 靜態全量驗證**

```bash
flutter analyze   # 無 error
flutter test      # 全過（原 34 項＋新增 widget 測試）
```

- [ ] **Step 2: 模擬器實跑主鏈路（spec §5）**

後端 `line-fleet-dispatch` docker 起好後：

```bash
flutter run -t lib/main_driver.dart --flavor driver     # 司機端
flutter run -t lib/main_customer.dart --flavor customer # 乘客端（無 key → 卡片版）
flutter run -t lib/main_customer.dart --flavor customer \
  --dart-define=GOOGLE_MAPS_API_KEY=$KEY                # 乘客端地圖版
```

驗收清單：
- 司機端：hero 開關切上線 → 亮暗模式各看一次 → 收派單出現全螢幕接單卡 → 接單 → 大按鈕逐階段 → 放棄有二次確認。
- 乘客端卡片版：叫車 → 配對中 → 司機途中（chips 有 ETA）→ 完成卡 → 再叫一輛；無「更新狀態」鈕、下拉可重整。
- 乘客端地圖版：地圖為底、sheet 可拖、司機 marker 隨 WS 移動、浮動登出鈕可用。
- 完整主鏈路：乘客叫車 → 司機接單 → 上車 → 完成 → 乘客收到完成卡。
- 驗完關掉模擬器與後端（session cleanup）。

- [ ] **Step 3: 文件收尾 + commit**

```bash
git add README.md docs/TODO.md
git commit -m "docs: App UI/UX 翻新收尾——README 與 TODO 回填"
```

分支合回 main 由 finishing-a-development-branch 流程處理（worktree 分支 → main）。

---

## Self-Review 紀錄

- Spec 覆蓋：§1.2（Task 1）、§3 全項（Task 2/3/4）、§2.1（Task 6）、§2.2（Task 5+6 降級路徑）、§2.3（Task 5 移除更新鈕/SnackBar、Task 6 浮動登出）、§5（Task 7）——齊。
- 型別一致：`kPrimaryActionHeight`／phase widget 名稱（`SearchingContent` 等）在 Task 5、6 引用一致；`OrderFormContent` 於 Task 6 Step 3 定義並在 `_sheetContent` 使用。
- 已知風險標註在步驟內：`CardThemeData` 型別名、`Statistic` testid、enum 實名以現況為準——皆給了驗證手段（analyze／測試），不是佔位。
