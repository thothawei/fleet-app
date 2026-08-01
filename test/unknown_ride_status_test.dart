import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/customer_api_client.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/theme/app_theme.dart';
import 'package:line_fleet_app/customer/customer_controller.dart';
import 'package:line_fleet_app/customer/screens/customer_map_home_screen.dart';
import 'package:line_fleet_app/customer/widgets/ride_phase_content.dart';
import 'package:provider/provider.dart';

/// 後端比 App 新時會送來的狀態碼。現行後端只有 0/1/2/3/4/9，
/// 但 `RideStatus.isTerminal` 是白名單——未知碼不算終態，
/// 所以 controller 會**繼續把它當成進行中的訂單**並持續輪詢。
/// 問題只在畫面拿它怎麼辦。
const _unknownStatus = 7;

class _QuietApi extends CustomerApiClient {
  _QuietApi()
    : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  @override
  Future<List<SavedPlace>> fetchSavedPlaces() async => const [];

  @override
  Future<ScheduledRidesResult> fetchScheduledRides({
    bool upcomingOnly = false,
  }) async => const ScheduledRidesResult(rides: [], leadMinutes: 15);

  @override
  Future<List<LostItemRequest>> fetchLostItems() async => const [];
}

CustomerController _withRide(int status) {
  final ctrl = CustomerController(api: _QuietApi());
  ctrl.setSessionForTest(
    const CustomerSession(customerId: 1, token: 'tok', name: '小美'),
  );
  ctrl.setActiveRideForTest(
    CustomerRide(rideId: 42, status: status, dropoffAddress: '台北車站'),
  );
  return ctrl;
}

void main() {
  group('未知的行程狀態碼', () {
    test('前提：未知碼既不算進行中也不算終態', () {
      // 這兩個白名單就是本題的來源——unknown 不是 terminal，
      // 所以 activeRide 不會被清掉；unknown 也不是 active，
      // 所以任何「照階段給操作」的畫面都沒有它的分支。
      expect(RideStatus.isTerminal(_unknownStatus), isFalse);
      expect(RideStatus.isActive(_unknownStatus), isFalse);
      expect(rideStatusLabel(_unknownStatus), '狀態 7');
    });

    testWidgets('地圖版首頁：未知狀態不可以退回叫車表單', (tester) async {
      final ctrl = _withRide(_unknownStatus);
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: appLightTheme,
          home: ChangeNotifierProvider<CustomerController>.value(
            value: ctrl,
            child: const CustomerMapHomeScreen(),
          ),
        ),
      );
      await tester.pump();

      // 修改前這裡是 OrderFormContent：手上有一張沒結束的訂單，畫面卻請乘客
      // 再叫一輛——而那一按必定被後端的「已有進行中訂單」擋掉，
      // 同時整張進行中的訂單在畫面上完全消失。
      expect(
        find.byType(OrderFormContent),
        findsNothing,
        reason: '有進行中訂單時不可以顯示叫車表單',
      );
      expect(find.byType(UnknownPhaseContent), findsOneWidget);
      expect(find.text('行程進行中'), findsOneWidget);
      // 據實把狀態碼說出來——客服問「畫面上寫什麼」時這是唯一能對帳的線索。
      expect(find.textContaining('狀態 7'), findsOneWidget);
      // 取消要留著：這是唯一的脫身出口。
      expect(find.widgetWithText(OutlinedButton, '取消行程'), findsOneWidget);
    });

    testWidgets('已知狀態不受影響（沒有把正常流程一起改壞）', (tester) async {
      final ctrl = _withRide(RideStatus.requested);
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: appLightTheme,
          home: ChangeNotifierProvider<CustomerController>.value(
            value: ctrl,
            child: const CustomerMapHomeScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(SearchingContent), findsOneWidget);
      expect(find.byType(UnknownPhaseContent), findsNothing);
    });
  });
}
