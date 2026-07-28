import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../shared/widgets/app_lifecycle_reactor.dart';
import 'customer_controller.dart';
import 'screens/customer_login_screen.dart';
import 'screens/customer_map_home_screen.dart';

class CustomerApp extends StatelessWidget {
  const CustomerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => CustomerController()..init(),
      child: MaterialApp(
        title: 'Fleet 乘客',
        theme: appLightTheme,
        darkTheme: appDarkTheme,
        themeMode: ThemeMode.system,
        home: const _CustomerRoot(),
      ),
    );
  }
}

class _CustomerRoot extends StatelessWidget {
  const _CustomerRoot();

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CustomerController>();
    // 回前景就對帳一次：背景期間輪詢 timer 不跑，WS 也可能已經半開。
    return AppLifecycleReactor(
      onResumed: ctrl.onAppResumed,
      child: ctrl.isLoggedIn
          ? const CustomerMapHomeScreen()
          : const CustomerLoginScreen(),
    );
  }
}
