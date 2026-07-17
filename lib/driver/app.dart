import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/config/app_config.dart';
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
      // 沒填就進不了首頁。後端 O3 也會擋（API 可被直接呼叫），這裡只是提早給回饋。
      return const DriverVehicleScreen(mandatory: true);
    }
    return const DriverHomeScreen();
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
