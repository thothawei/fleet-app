import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/config/app_config.dart';
import '../core/models/models.dart';
import '../core/push/driver_push_service.dart';
import '../core/theme/app_theme.dart';
import 'driver_controller.dart';
import 'screens/driver_home_screen.dart';
import 'screens/driver_login_screen.dart';
import 'screens/driver_vehicle_screen.dart';

class DriverApp extends StatelessWidget {
  const DriverApp({this.pushService, super.key});

  final DriverPushService? pushService;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DriverController(push: pushService)..init(),
      child: MaterialApp(
        title: 'Fleet 司機',
        theme: appLightTheme,
        darkTheme: appDarkTheme,
        themeMode: ThemeMode.system,
        home: const _DriverRoot(),
      ),
    );
  }
}

class _DriverRoot extends StatelessWidget {
  const _DriverRoot();

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DriverController>();
    if (!ctrl.isLoggedIn) {
      return const DriverLoginScreen();
    }
    // O3 gate 的 App 端引導（拍板：強制填寫、不設寬限期）。
    //
    // **查失敗要有出路**：token 過期／後端不可達時若只是繼續轉圈，司機會卡在無限
    // spinner，連登出都按不到（模擬器實跑抓到的真 bug——舊 session 對新後端無效）。
    // 「不把錯誤誤判成沒填」不等於「什麼都不說」。
    if (ctrl.vehicleLoadFailed) {
      return _VehicleLoadErrorScreen(ctrl: ctrl);
    }
    // 查完之前不能判斷「沒填」，否則登入後會閃一下設定頁再跳回首頁。
    // 查詢中顯示 spinner——這是「還不知道」的誠實呈現，不是第三種業務狀態。
    if (!ctrl.vehicleChecked) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!ctrl.hasVehicle) {
      // 沒填就進不了首頁。後端 O5 也會擋（API 可被直接呼叫），這裡只是提早給回饋。
      return const DriverVehicleScreen(mandatory: true);
    }
    // O5 四態：填了之後看審核。以後端 can_accept 為 gate，App 不自行推導。
    // pending → 審核中等待頁；rejected → 已退回（原因＋重填）；approved → 首頁。
    switch (ctrl.vehicleReviewStatus) {
      case VehicleReviewStatus.pending:
        return _VehicleReviewPendingScreen(ctrl: ctrl);
      case VehicleReviewStatus.rejected:
        return _VehicleReviewRejectedScreen(ctrl: ctrl);
      case VehicleReviewStatus.approved:
      case VehicleReviewStatus.none:
        // approved → 首頁；none（舊後端無審核欄位）→ 靠 can_accept 決定，退回首頁。
        return const DriverHomeScreen();
    }
  }
}

/// 待審核等待畫面（O5）：司機填完了卻還不能接單，要明確說明「在等審核」，
/// 不能讓他以為壞掉。給重新整理（審核結果由 admin 端決定，這裡輪詢/手動刷新）與登出。
class _VehicleReviewPendingScreen extends StatelessWidget {
  const _VehicleReviewPendingScreen({required this.ctrl});

  final DriverController ctrl;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('車輛審核中'),
        actions: [
          IconButton(
            tooltip: '登出',
            onPressed: ctrl.loading ? null : () => ctrl.logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.hourglass_top, size: 56),
                const SizedBox(height: 16),
                Text('車輛資料審核中', style: text.titleLarge),
                const SizedBox(height: 8),
                Text(
                  '已收到你的車種與車牌，審核通過後就能開始接單。\n通常很快，稍後可下拉重新整理。',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: ctrl.loading ? null : () => ctrl.refreshVehicle(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新整理審核狀態'),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const DriverVehicleScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('修改車輛資料'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 已退回畫面（O5）：顯示 admin 給的原因，讓司機知道哪裡不對、可重填再送審。
class _VehicleReviewRejectedScreen extends StatelessWidget {
  const _VehicleReviewRejectedScreen({required this.ctrl});

  final DriverController ctrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = ctrl.vehicleReviewNote;
    return Scaffold(
      appBar: AppBar(
        title: const Text('車輛審核未通過'),
        actions: [
          IconButton(
            tooltip: '登出',
            onPressed: ctrl.loading ? null : () => ctrl.logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 56, color: theme.colorScheme.error),
                const SizedBox(height: 16),
                Text('車輛審核未通過', style: theme.textTheme.titleLarge),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Card(
                    color: theme.colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        '原因：$note',
                        style: TextStyle(color: theme.colorScheme.onErrorContainer),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  '請依原因修改車種或車牌後重新送審。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const DriverVehicleScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('修改車輛並重新送審'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 車輛資訊查詢失敗：給錯誤與**出路**（重試／登出），不要讓司機卡在轉圈。
class _VehicleLoadErrorScreen extends StatelessWidget {
  const _VehicleLoadErrorScreen({required this.ctrl});

  final DriverController ctrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 48),
                const SizedBox(height: 16),
                Text(
                  '無法載入車輛資訊',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  ctrl.error ?? '請檢查網路後重試',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => ctrl.refreshVehicle(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重試'),
                ),
                const SizedBox(height: 8),
                // 登入資訊過期時，重試永遠不會成功——一定要留這條路。
                TextButton(
                  onPressed: () => ctrl.logout(),
                  child: const Text('重新登入'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 開發用：顯示 API 位址
String get debugApiHint => AppConfig.apiBase;
