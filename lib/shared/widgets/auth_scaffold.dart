import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';

/// 司機端／乘客端共用的登入／註冊畫面骨架。
///
/// 兩端流程一致（LINE User ID ＋ 密碼；註冊多一個姓名），差別只在品牌圖示、
/// 標題與少數文案，因此抽成一個 controller-agnostic 的元件：登入邏輯由呼叫端
/// 以 [onLogin]／[onRegister] callback 注入，本元件只負責表單與呈現。
class AuthScaffold extends StatefulWidget {
  const AuthScaffold({
    super.key,
    required this.icon,
    required this.title,
    required this.registerToggleLabel,
    required this.loginToggleLabel,
    required this.loading,
    required this.error,
    required this.onLogin,
    required this.onRegister,
    this.devLineUserId,
    this.devName,
    this.devPassword,
  });

  /// 品牌圖示（司機＝計程車、乘客＝定位人形）。
  final IconData icon;

  /// 主標題（例如「Fleet 司機端」）。
  final String title;

  /// 切換到註冊模式的提示（例如「新司機？註冊」）。
  final String registerToggleLabel;

  /// 切換回登入模式的提示（例如「已有帳號？登入」）。
  final String loginToggleLabel;

  final bool loading;
  final String? error;

  final Future<void> Function({
    required String lineUserId,
    required String password,
  }) onLogin;

  final Future<void> Function({
    required String lineUserId,
    required String name,
    required String password,
  }) onRegister;

  /// 以下三個僅在 debug build 預填，方便模擬器 E2E；release build 一律留空。
  final String? devLineUserId;
  final String? devName;
  final String? devPassword;

  @override
  State<AuthScaffold> createState() => _AuthScaffoldState();
}

class _AuthScaffoldState extends State<AuthScaffold> {
  late final TextEditingController _lineUserId;
  late final TextEditingController _name;
  late final TextEditingController _password;
  final _formKey = GlobalKey<FormState>();
  bool _isRegister = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    // 開發便利：只有 debug build 才預填測試帳密，正式 build 保持空白。
    _lineUserId =
        TextEditingController(text: kDebugMode ? (widget.devLineUserId ?? '') : '');
    _name = TextEditingController(text: kDebugMode ? (widget.devName ?? '') : '');
    _password =
        TextEditingController(text: kDebugMode ? (widget.devPassword ?? '') : '');
  }

  @override
  void dispose() {
    _lineUserId.dispose();
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    _BrandHeader(icon: widget.icon, title: widget.title),
                    const SizedBox(height: 32),
                    TextFormField(
                      controller: _lineUserId,
                      textInputAction: _isRegister
                          ? TextInputAction.next
                          : TextInputAction.done,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'LINE User ID',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? '請輸入 LINE User ID'
                          : null,
                    ),
                    if (_isRegister) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _name,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: '姓名',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? '請輸入姓名'
                            : null,
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: '密碼',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          tooltip: _obscurePassword ? '顯示密碼' : '隱藏密碼',
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? '請輸入密碼' : null,
                    ),
                    if (widget.error != null) ...[
                      const SizedBox(height: 16),
                      _ErrorBanner(message: widget.error!),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: widget.loading ? null : _submit,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: widget.loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(_isRegister ? '註冊並登入' : '登入'),
                      ),
                    ),
                    TextButton(
                      onPressed: widget.loading
                          ? null
                          : () => setState(() => _isRegister = !_isRegister),
                      child: Text(_isRegister
                          ? widget.loginToggleLabel
                          : widget.registerToggleLabel),
                    ),
                    if (kDebugMode) ...[
                      const SizedBox(height: 8),
                      Text(
                        '後端：${AppConfig.apiBase}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.outline),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_isRegister) {
      await widget.onRegister(
        lineUserId: _lineUserId.text.trim(),
        name: _name.text.trim(),
        password: _password.text,
      );
    } else {
      await widget.onLogin(
        lineUserId: _lineUserId.text.trim(),
        password: _password.text,
      );
    }
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 48, color: scheme.onPrimaryContainer),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          style: theme.textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w600),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 20, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
