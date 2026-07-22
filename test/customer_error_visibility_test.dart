import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/customer_api_client.dart';
import 'package:line_fleet_app/core/api/fleet_api_client.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/theme/app_theme.dart';
import 'package:line_fleet_app/customer/customer_controller.dart';
import 'package:line_fleet_app/customer/screens/customer_map_home_screen.dart';
import 'package:provider/provider.dart';

/// 2026-07-22 模擬器實跑抓到：production 首頁（地圖版）從不顯示 `ctrl.error`，
/// 導致叫車的每一種失敗——定位權限被拒、定位取不到、建單 API 失敗（token 失效／後端離線）
/// ——使用者按下去都只看到畫面轉一下又回到原樣，沒有任何說明。
/// 舊的卡片版首頁本來有 SnackBar，換成地圖版時掉了。
void main() {
  late CustomerController ctrl;

  setUp(() {
    ctrl = CustomerController(api: _FailingApi());
    ctrl.setSessionForTest(
      const CustomerSession(customerId: 1, token: 'tok', name: '測試乘客'),
    );
  });

  tearDown(() => ctrl.dispose());

  Widget app() => ChangeNotifierProvider.value(
        value: ctrl,
        child: MaterialApp(
          theme: appLightTheme,
          home: const CustomerMapHomeScreen(),
        ),
      );

  testWidgets('API 失敗時首頁要把錯誤說出來，不能靜默', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();

    await ctrl.refreshActive(); // 真實路徑：API 丟 ApiException → _error
    await tester.pump(); // build
    await tester.pump(); // postFrameCallback → SnackBar

    expect(find.text('token 無效或已過期'), findsOneWidget);
  });

  testWidgets('錯誤顯示後被清掉，同樣的失敗再發生一次仍會再提示', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();

    await ctrl.refreshActive();
    await tester.pump();
    await tester.pump();
    expect(find.text('token 無效或已過期'), findsOneWidget);
    expect(ctrl.error, isNull, reason: '顯示過就該清掉，否則第二次會被去重吃掉');

    // 讓第一則 SnackBar 收掉，再讓同樣的錯誤發生一次。
    ScaffoldMessenger.of(tester.element(find.byType(CustomerMapHomeScreen)))
        .clearSnackBars();
    await tester.pump();
    expect(find.text('token 無效或已過期'), findsNothing);

    await ctrl.refreshActive();
    await tester.pump();
    await tester.pump();
    expect(find.text('token 無效或已過期'), findsOneWidget,
        reason: '第二次同樣的失敗也必須有回饋');
  });
}

/// 模擬 token 失效的後端：任何查詢都回 401。
class _FailingApi extends CustomerApiClient {
  _FailingApi() : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  @override
  Future<CustomerRide?> activeRide() async =>
      throw ApiException('token 無效或已過期', statusCode: 401);
}
