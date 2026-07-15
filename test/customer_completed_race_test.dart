import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/customer_api_client.dart';
import 'package:line_fleet_app/core/config/app_config.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/customer/customer_controller.dart';

void main() {
  group('乘客完成卡競態', () {
    late _NullActiveApi api;
    late CustomerController ctrl;

    setUp(() {
      api = _NullActiveApi();
      ctrl = CustomerController(api: api);
      ctrl.setSessionForTest(
        const CustomerSession(customerId: 1, token: 'tok', name: '小美'),
      );
    });

    tearDown(() => ctrl.dispose());

    test('輪詢先清空 active，稍後才到的 ride.completed 仍能設出完成卡摘要', () async {
      // 進行中訂單（行程中）
      ctrl.setActiveRideForTest(
        const CustomerRide(
          rideId: 5,
          status: RideStatus.pickedUp,
          dropoffAddress: '台北車站',
        ),
      );

      // 模擬輪詢對帳搶先一步：active API 對已完成行程回 null → _activeRide 被清成 null。
      await ctrl.refreshActive();
      expect(ctrl.activeRide, isNull, reason: '輪詢後進行中訂單應已清空');

      // 稍後才抵達的 WS 完成事件（帶車資）。修正前此時 _activeRide 已為 null 會早退，
      // 完成摘要設不出來；修正後應用 _lastActiveRide 補出摘要。
      ctrl.handleWsEventForTest(
        FleetWsEvent(
          type: FleetEventTypes.rideCompleted,
          rideId: 5,
          payload: const {'fare_amount_cents': 21000},
        ),
      );

      final summary = ctrl.completedSummary;
      expect(summary, isNotNull, reason: '即使 active 已被輪詢清空，完成卡摘要仍應顯示');
      expect(summary!.rideId, 5);
      expect(summary.fareAmountCents, 21000);
      expect(summary.dropoffAddress, '台北車站');
    });

    test('完成事件 rideId 與最近進行中訂單不符時不誤設摘要', () async {
      ctrl.setActiveRideForTest(
        const CustomerRide(rideId: 5, status: RideStatus.pickedUp),
      );
      await ctrl.refreshActive();

      ctrl.handleWsEventForTest(
        FleetWsEvent(
          type: FleetEventTypes.rideCompleted,
          rideId: 999, // 別的行程
          payload: const {'fare_amount_cents': 8500},
        ),
      );
      expect(ctrl.completedSummary, isNull);
    });
  });
}

/// active API 一律回 null（模擬「行程已完成不再屬 active」）。
class _NullActiveApi extends CustomerApiClient {
  _NullActiveApi()
      : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  @override
  Future<CustomerRide?> activeRide() async => null;
}
