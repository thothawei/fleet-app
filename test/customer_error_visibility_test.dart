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

  // 反面：**背景輪詢**（15 秒一次，使用者沒按任何東西）失敗不該彈 SnackBar。
  // 會彈就是每 15 秒蓋住 sheet 上的按鈕一次，而且使用者沒有辦法讓它停。
  group('背景輪詢失敗不該打擾使用者', () {
    late CustomerController pollCtrl;
    late _FlakyAfterFirstApi flaky;

    Widget pollApp() => ChangeNotifierProvider.value(
          value: pollCtrl,
          child: MaterialApp(
            theme: appLightTheme,
            home: const CustomerMapHomeScreen(),
          ),
        );

    setUp(() {
      flaky = _FlakyAfterFirstApi();
      pollCtrl = CustomerController(api: flaky);
      pollCtrl.setSessionForTest(
        const CustomerSession(customerId: 1, token: 'tok', name: '測試乘客'),
      );
    });

    // 輪詢是 Timer.periodic，測試結束時一定還掛著；dispose 會停掉它，
    // 否則 testWidgets 會以 "Pending timers" 失敗。
    testWidgets('輪詢期間後端斷線：不彈 SnackBar、不寫全域 error', (tester) async {
      await tester.pumpWidget(pollApp());
      await tester.pump();

      // 第一次成功 → 拿到進行中行程並啟動輪詢
      await pollCtrl.refreshActive();
      await tester.pump();
      expect(pollCtrl.activeRide?.rideId, 77);

      // 之後後端斷線；跳過一個輪詢週期（15 秒）
      await tester.pump(const Duration(seconds: 16));
      await tester.pump();

      expect(flaky.calls, greaterThan(1), reason: '輪詢確實跑了，否則這個測試沒驗到東西');
      expect(pollCtrl.error, isNull,
          reason: '背景輪詢失敗是暫時性的，不該變成使用者要處理的錯誤');
      expect(find.text('無法連線到伺服器，請檢查網路'), findsNothing);

      pollCtrl.dispose();
    });

    testWidgets('同樣斷線，使用者自己觸發的刷新仍要說出來', (tester) async {
      await tester.pumpWidget(pollApp());
      await tester.pump();

      await pollCtrl.refreshActive(); // 第一次成功
      await tester.pump();

      await pollCtrl.refreshActive(); // 使用者主動觸發，這次失敗
      await tester.pump();
      await tester.pump();

      expect(find.text('無法連線到伺服器，請檢查網路'), findsOneWidget,
          reason: '使用者自己按的動作失敗，一定要有回饋');

      pollCtrl.dispose();
    });
  });
}

/// 模擬 token 失效的後端：任何查詢都回 401。
class _FailingApi extends CustomerApiClient {
  _FailingApi() : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  @override
  Future<CustomerRide?> activeRide() async =>
      throw ApiException('token 無效或已過期', statusCode: 401);
}

/// 第一次查詢成功（回一筆進行中行程並啟動輪詢），之後一律斷線。
class _FlakyAfterFirstApi extends CustomerApiClient {
  _FlakyAfterFirstApi()
      : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  int calls = 0;

  @override
  Future<CustomerRide?> activeRide() async {
    calls++;
    if (calls == 1) {
      return const CustomerRide(rideId: 77, status: RideStatus.accepted);
    }
    // 斷線＝沒有 HTTP 回應，statusCode 為 null
    throw ApiException('無法連線到伺服器，請檢查網路');
  }
}
