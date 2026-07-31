import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/customer_api_client.dart';
import 'package:line_fleet_app/core/config/app_config.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/theme/app_theme.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/customer/customer_controller.dart';
import 'package:line_fleet_app/customer/screens/customer_map_home_screen.dart';
import 'package:provider/provider.dart';

/// 2026-07-28 遺失物協尋鏈路對帳抓到：**production 首頁（地圖版）沒有任何協尋入口**。
///
/// 持久性的「進行中協尋」banner 只寫在**卡片版**首頁，換成地圖版當 production 後就掉了。
/// 唯一剩下的入口是完成卡上的「物品遺失？聯絡司機」，而完成卡在按「再叫一輛」、
/// 開始新行程或重開 App 後就消失。
///
/// 後果：乘客建了協尋單、司機標記「已尋獲」後，**乘客必須付處理費才能拿回東西，
/// 卻沒有任何畫面可以進去付**。WS `lost_item.updated` 有進 controller，但沒人讀。
///
/// （2026-07-15 那次 E2E 之所以「驗過」，是因為當時本機無 Maps key 走的是卡片版。）
void main() {
  late CustomerController ctrl;
  var disposed = false;

  setUp(() {
    disposed = false;
    ctrl = CustomerController(api: _StubApi());
    ctrl.setSessionForTest(
      const CustomerSession(customerId: 1, token: 'tok', name: '測試乘客'),
    );
  });

  tearDown(() {
    if (!disposed) ctrl.dispose();
  });

  Widget app() => ChangeNotifierProvider.value(
        value: ctrl,
        child: MaterialApp(
          theme: appLightTheme,
          home: const CustomerMapHomeScreen(),
        ),
      );

  Map<String, dynamic> payload(String status) => {
        'id': 5,
        'ride_id': 42,
        'customer_id': 1,
        'driver_id': 7,
        'description': '黑色皮夾',
        'fee_cents': 2100,
        'status': status,
        'paid_at': null,
      };

  testWidgets('司機標記已尋獲後，production 首頁要有進得去的入口', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();

    // 沒有協尋單時不該佔版面
    expect(find.textContaining('遺失物協尋'), findsNothing);

    // 真實路徑：WS 事件進 controller
    ctrl.handleWsEventForTest(FleetWsEvent(
      type: FleetEventTypes.lostItemCreated,
      rideId: 42,
      payload: payload(LostItemStatus.found),
    ));
    await tester.pump();

    expect(find.text('遺失物協尋：黑色皮夾'), findsOneWidget);
    // 狀態要說清楚現在輪到誰做什麼——「已尋獲」代表等乘客付款
    expect(find.text(LostItemStatus.label(LostItemStatus.found)), findsOneWidget);
  });

  testWidgets('結案後入口消失（不留一張永遠點不完的卡）', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();

    ctrl.handleWsEventForTest(FleetWsEvent(
      type: FleetEventTypes.lostItemCreated,
      rideId: 42,
      payload: payload(LostItemStatus.open),
    ));
    await tester.pump();
    expect(find.text('遺失物協尋：黑色皮夾'), findsOneWidget);

    ctrl.handleWsEventForTest(FleetWsEvent(
      type: FleetEventTypes.lostItemUpdated,
      rideId: 42,
      payload: payload(LostItemStatus.returned),
    ));
    await tester.pump();

    expect(find.textContaining('遺失物協尋'), findsNothing);
  });

  testWidgets('叫車中也看得到——協尋掛在上一趟，不該被新行程蓋掉', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();

    ctrl.handleWsEventForTest(FleetWsEvent(
      type: FleetEventTypes.lostItemCreated,
      rideId: 42,
      payload: payload(LostItemStatus.found),
    ));
    ctrl.setActiveRideForTest(
      const CustomerRide(rideId: 43, status: RideStatus.requested),
    );
    await tester.pump();

    expect(find.text('遺失物協尋：黑色皮夾'), findsOneWidget);
    expect(find.text('正在為您配對司機'), findsOneWidget);

    ctrl.dispose();
    disposed = true;
  });
}

class _StubApi extends CustomerApiClient {
  // 預約／常用地點：controller.init() 會載這兩份。沒覆寫的話會走真實 Dio 打網路，
  // 在測試裡變成不確定的非同步延遲，把不相干的測試拖成 flaky（實測會讓
  // customer_location_exits 的預估 notifyListeners 落在 dispose 之後）。
  @override
  Future<List<SavedPlace>> fetchSavedPlaces() async => const [];

  @override
  Future<ScheduledRidesResult> fetchScheduledRides({bool upcomingOnly = false}) async =>
      const ScheduledRidesResult(rides: [], leadMinutes: 15);

  _StubApi() : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  @override
  Future<CustomerRide?> activeRide() async => null;
}
