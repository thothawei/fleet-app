import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/push/fleet_push_service.dart';
import '../core/theme/app_theme.dart';
import '../shared/widgets/app_lifecycle_reactor.dart';
import 'customer_controller.dart';
import 'screens/customer_login_screen.dart';
import 'screens/customer_map_home_screen.dart';

class CustomerApp extends StatelessWidget {
  const CustomerApp({this.pushService, super.key});

  final FleetPushService? pushService;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => CustomerController(push: pushService)..init(),
      // Builder：拿到 provider 底下的 context，回前景才叫得到 controller。
      child: Builder(
        builder: (context) => AppLifecycleReactor(
          onResumed: () => context.read<CustomerController>().onAppResumed(),
          child: MaterialApp(
            title: 'Fleet 乘客',
            theme: appLightTheme,
            darkTheme: appDarkTheme,
            themeMode: ThemeMode.system,
            home: const _CustomerRoot(),
          ),
        ),
      ),
    );
  }
}

class _CustomerRoot extends StatelessWidget {
  const _CustomerRoot();

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CustomerController>();
    if (!ctrl.isLoggedIn) {
      return const CustomerLoginScreen();
    }
    return const CustomerMapHomeScreen();
  }
}
