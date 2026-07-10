import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/config/app_config.dart';
import '../core/theme/app_theme.dart';
import 'customer_controller.dart';
import 'screens/customer_home_screen.dart';
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
    if (!ctrl.isLoggedIn) {
      return const CustomerLoginScreen();
    }
    return AppConfig.mapsConfigured
        ? const CustomerMapHomeScreen()
        : const CustomerHomeScreen();
  }
}
