import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../shared/widgets/auth_scaffold.dart';
import '../customer_controller.dart';

class CustomerLoginScreen extends StatelessWidget {
  const CustomerLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CustomerController>();
    return AuthScaffold(
      icon: Icons.person_pin_circle,
      title: 'Fleet 乘客端',
      registerToggleLabel: '新乘客？註冊',
      loginToggleLabel: '已有帳號？登入',
      loading: ctrl.loading,
      error: ctrl.error,
      onLogin: ctrl.login,
      onRegister: ctrl.register,
      devLineUserId: 'sim-customer-001',
      devName: '測試乘客',
      devPassword: 'password123',
    );
  }
}
