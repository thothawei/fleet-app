import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/theme/app_theme.dart';
import 'package:line_fleet_app/shared/widgets/auth_scaffold.dart';

void main() {
  // 記錄 callback 收到的參數，驗證表單真的把值傳出去。
  ({String lineUserId, String password})? loginArgs;
  ({String lineUserId, String name, String password})? registerArgs;

  Widget harness({
    bool loading = false,
    String? error,
    bool withDevPrefill = false,
  }) {
    loginArgs = null;
    registerArgs = null;
    return MaterialApp(
      theme: appLightTheme,
      home: AuthScaffold(
        icon: Icons.local_taxi,
        title: 'Fleet 司機端',
        registerToggleLabel: '新司機？註冊',
        loginToggleLabel: '已有帳號？登入',
        loading: loading,
        error: error,
        onLogin: ({required lineUserId, required password}) async {
          loginArgs = (lineUserId: lineUserId, password: password);
        },
        onRegister: ({required lineUserId, required name, required password}) async {
          registerArgs =
              (lineUserId: lineUserId, name: name, password: password);
        },
        devLineUserId: withDevPrefill ? 'sim-driver-001' : null,
        devName: withDevPrefill ? '測試司機' : null,
        devPassword: withDevPrefill ? 'password123' : null,
      ),
    );
  }

  testWidgets('空欄位按登入 → 擋下並顯示驗證訊息，不呼叫 onLogin', (tester) async {
    await tester.pumpWidget(harness());
    await tester.tap(find.widgetWithText(FilledButton, '登入'));
    await tester.pump();

    expect(find.text('請輸入 LINE User ID'), findsOneWidget);
    expect(find.text('請輸入密碼'), findsOneWidget);
    expect(loginArgs, isNull);
  });

  testWidgets('填齊帳密按登入 → 以 trim 後的值呼叫 onLogin', (tester) async {
    await tester.pumpWidget(harness());
    await tester.enterText(
        find.widgetWithText(TextFormField, 'LINE User ID'), '  alice  ');
    await tester.enterText(find.widgetWithText(TextFormField, '密碼'), 'pw123');
    await tester.tap(find.widgetWithText(FilledButton, '登入'));
    await tester.pump();

    expect(loginArgs, isNotNull);
    expect(loginArgs!.lineUserId, 'alice');
    expect(loginArgs!.password, 'pw123');
  });

  testWidgets('切到註冊 → 出現姓名欄，填齊呼叫 onRegister', (tester) async {
    await tester.pumpWidget(harness());
    expect(find.widgetWithText(TextFormField, '姓名'), findsNothing);

    await tester.tap(find.text('新司機？註冊'));
    await tester.pump();
    expect(find.widgetWithText(TextFormField, '姓名'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'LINE User ID'), 'bob');
    await tester.enterText(find.widgetWithText(TextFormField, '姓名'), '小明');
    await tester.enterText(find.widgetWithText(TextFormField, '密碼'), 'pw');
    await tester.tap(find.widgetWithText(FilledButton, '註冊並登入'));
    await tester.pump();

    expect(registerArgs, isNotNull);
    expect(registerArgs!.name, '小明');
  });

  testWidgets('密碼顯示切換 → obscureText 由 true 變 false', (tester) async {
    await tester.pumpWidget(harness());
    EditableText passwordField() => tester.widget<EditableText>(
          find.descendant(
            of: find.widgetWithText(TextFormField, '密碼'),
            matching: find.byType(EditableText),
          ),
        );
    expect(passwordField().obscureText, isTrue);

    await tester.tap(find.byTooltip('顯示密碼'));
    await tester.pump();
    expect(passwordField().obscureText, isFalse);
  });

  testWidgets('error 非 null → 顯示錯誤橫幅文字', (tester) async {
    await tester.pumpWidget(harness(error: '帳號或密碼錯誤'));
    await tester.pump();
    expect(find.text('帳號或密碼錯誤'), findsOneWidget);
  });

  testWidgets('loading → 送出鈕 disabled 並顯示 spinner', (tester) async {
    await tester.pumpWidget(harness(loading: true));
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(
      find.descendant(
        of: find.byType(FilledButton),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
  });

  testWidgets('debug prefill 帶入時 → 欄位預填測試帳號', (tester) async {
    await tester.pumpWidget(harness(withDevPrefill: true));
    // 測試環境 kDebugMode == true，故 devLineUserId 會預填。
    expect(find.text('sim-driver-001'), findsOneWidget);
  });
}
