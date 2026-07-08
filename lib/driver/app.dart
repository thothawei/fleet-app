import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/config/app_config.dart';
import '../core/push/driver_push_service.dart';
import 'driver_controller.dart';
import 'screens/driver_home_screen.dart';
import 'screens/driver_login_screen.dart';

class DriverApp extends StatelessWidget {
  const DriverApp({this.pushService, super.key});

  final DriverPushService? pushService;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DriverController(push: pushService)..init(),
      child: MaterialApp(
        title: 'Fleet 司機',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF00695C),
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
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
    return const DriverHomeScreen();
  }
}

/// 開發用：顯示 API 位址
String get debugApiHint => AppConfig.apiBase;
