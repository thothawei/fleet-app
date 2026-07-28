import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/customer_api_client.dart';
import 'package:line_fleet_app/core/config/app_config.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/theme/app_theme.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/customer/customer_controller.dart';
import 'package:line_fleet_app/customer/widgets/ride_phase_content.dart';
import 'package:provider/provider.dart';

/// 2026-07-28 跨端契約對帳抓到：司機放棄已接的訂單時，後端**只推 LINE**
/// （「司機取消了行程，正在為您重新派車」），對 App 乘客一則 WS 事件都沒有。
/// 結果是司機卡片停在畫面上，直到最多 15 秒後的輪詢才無聲退回「配對中」——
/// 期間乘客看到的車牌與撥號按鈕都是那位已經不來的司機。
///
/// 後端補送 `ride.redispatched`（本來就定義了，先前只用於 audit），App 這邊接住它。
void main() {
  late CustomerController ctrl;
  // 輪詢是 Timer.periodic：測試裡若讓它活著，testWidgets 會以 "Pending timers" 失敗。
  // dispose 會停掉它；已在測試內 dispose 過的就別再 dispose 一次。
  var disposed = false;

  setUp(() {
    disposed = false;
    ctrl = CustomerController(api: _StubApi());
    ctrl.setSessionForTest(
      const CustomerSession(customerId: 1, token: 'tok', name: '測試乘客'),
    );
    ctrl.setActiveRideForTest(
      const CustomerRide(rideId: 9, status: RideStatus.accepted),
      driverName: '阿明',
      liveEtaSec: 300,
    );
  });

  tearDown(() {
    if (!disposed) ctrl.dispose();
  });

  void redispatch() => ctrl.handleWsEventForTest(
        FleetWsEvent(type: FleetEventTypes.rideRedispatched, rideId: 9),
      );

  test('司機放棄 → 清掉上一位司機的所有痕跡並給說明', () {
    expect(ctrl.driverName, '阿明');

    redispatch();

    expect(ctrl.redispatchNotice, '司機取消了行程，正在為您重新派車');
    // 車牌／撥號按鈕若留著，乘客會打給一個已經不來的司機
    expect(ctrl.driverName, isNull);
    expect(ctrl.driverInfo, isNull);
    expect(ctrl.liveEtaSec, isNull, reason: '舊司機的 ETA 不能留在畫面上');
  });

  test('不是取消：訂單還在，不該顯示取消通知', () {
    redispatch();

    expect(ctrl.cancelNotice, isNull,
        reason: '行程只是回到派單中，顯示「已取消」會讓乘客以為要重新叫車');
  });

  test('新司機接單後通知消失', () {
    redispatch();
    expect(ctrl.redispatchNotice, isNotNull);

    ctrl.handleWsEventForTest(FleetWsEvent(
      type: FleetEventTypes.rideAccepted,
      rideId: 9,
      payload: {'driver_name': '阿華', 'driver_plate_number': 'NEW-0001'},
    ));

    expect(ctrl.redispatchNotice, isNull);
    expect(ctrl.driverName, '阿華');
  });

  test('重派也失敗真的取消時，通知換成取消訊息', () {
    redispatch();
    ctrl.handleWsEventForTest(FleetWsEvent(
      type: FleetEventTypes.rideCancelled,
      rideId: 9,
      payload: {'cancel_reason': 'no_driver_available'},
    ));

    expect(ctrl.redispatchNotice, isNull);
    expect(ctrl.cancelNotice, isNotNull);
  });

  testWidgets('配對中畫面要把這則說明顯示出來（不能設了沒人讀）', (tester) async {
    redispatch();

    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: ctrl,
      child: MaterialApp(
        theme: appLightTheme,
        home: Scaffold(body: SearchingContent(ctrl: ctrl)),
      ),
    ));
    await tester.pump();

    expect(find.text('司機取消了行程，正在為您重新派車'), findsOneWidget);
    expect(find.text('正在為您配對司機'), findsOneWidget);

    ctrl.dispose();
    disposed = true;
  });
}

class _StubApi extends CustomerApiClient {
  _StubApi() : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  @override
  Future<CustomerRide?> activeRide() async =>
      const CustomerRide(rideId: 9, status: RideStatus.requested);
}
