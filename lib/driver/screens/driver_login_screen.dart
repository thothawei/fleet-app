import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../shared/widgets/auth_scaffold.dart';
import '../driver_controller.dart';

class DriverLoginScreen extends StatelessWidget {
  const DriverLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DriverController>();
    return AuthScaffold(
      icon: Icons.local_taxi,
      title: 'Fleet 司機端',
      registerToggleLabel: '新司機？註冊',
      loginToggleLabel: '已有帳號？登入',
      loading: ctrl.loading,
      error: ctrl.error,
      onLogin: ctrl.login,
      onRegister: ctrl.register,
      devLineUserId: 'sim-driver-001',
      devName: '測試司機',
      devPassword: 'password123',
    );
  }
}
