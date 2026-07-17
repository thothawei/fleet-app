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
    // 先看 vehicleChecked：查完之前不能判斷「沒填」，否則登入後會閃一下設定頁再跳回首頁。
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

/// 開發用：顯示 API 位址
String get debugApiHint => AppConfig.apiBase;
