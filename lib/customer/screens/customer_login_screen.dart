import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../customer_controller.dart';

class CustomerLoginScreen extends StatefulWidget {
  const CustomerLoginScreen({super.key});

  @override
  State<CustomerLoginScreen> createState() => _CustomerLoginScreenState();
}

class _CustomerLoginScreenState extends State<CustomerLoginScreen> {
  final _lineUserId = TextEditingController(text: 'sim-customer-001');
  final _name = TextEditingController(text: '測試乘客');
  final _password = TextEditingController(text: 'password123');
  bool _isRegister = false;

  @override
  void dispose() {
    _lineUserId.dispose();
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CustomerController>();

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              Icon(
                Icons.person_pin_circle,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Fleet 乘客端',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '後端：${AppConfig.apiBase}',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _lineUserId,
                decoration: const InputDecoration(
                  labelText: 'LINE User ID',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_isRegister) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: '姓名',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '密碼',
                  border: OutlineInputBorder(),
                ),
              ),
              if (ctrl.error != null) ...[
                const SizedBox(height: 12),
                Text(
                  ctrl.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: ctrl.loading ? null : _submit,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(ctrl.loading
                      ? '處理中…'
                      : (_isRegister ? '註冊並登入' : '登入')),
                ),
              ),
              TextButton(
                onPressed: ctrl.loading
                    ? null
                    : () => setState(() => _isRegister = !_isRegister),
                child: Text(_isRegister ? '已有帳號？登入' : '新乘客？註冊'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final ctrl = context.read<CustomerController>();
    if (_isRegister) {
      await ctrl.register(
        lineUserId: _lineUserId.text.trim(),
        name: _name.text.trim(),
        password: _password.text,
      );
    } else {
      await ctrl.login(
        lineUserId: _lineUserId.text.trim(),
        password: _password.text,
      );
    }
  }
}
