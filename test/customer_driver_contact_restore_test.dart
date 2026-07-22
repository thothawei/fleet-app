import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/customer_api_client.dart';
import 'package:line_fleet_app/core/config/app_config.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/customer/customer_controller.dart';

/// O7 撥號鏈路的還原路徑（2026-07-22 模擬器實跑抓到）：
/// `ride.accepted` 只送一次，app 在背景被接單／WS 重連／重開 app 都收不到它。
/// 修正前司機資訊只由該事件填入，錯過就再也拿不到 → 撥號按鈕永遠不出現，
/// 即使後端 `GET /customer/rides/active` 一直都帶著電話。
void main() {
  group('乘客端司機聯絡資訊的 REST 還原', () {
    test('後端 active 帶司機資訊時，錯過 WS 事件仍能還原出電話與車牌', () async {
      final ctrl = CustomerController(api: _AcceptedActiveApi());
      addTearDown(ctrl.dispose);
      ctrl.setSessionForTest(
        const CustomerSession(customerId: 1, token: 'tok', name: '小美'),
      );

      // 沒有任何 WS 事件，只做一次 GET active（＝回前景／重連時的還原路徑）。
      await ctrl.refreshActive();

      expect(ctrl.driverName, '測試司機');
      expect(ctrl.driverInfo, isNotNull, reason: '錯過 WS 事件時要由 REST 補上');
      expect(ctrl.driverInfo!.phone, '0912345678');
      expect(ctrl.driverInfo!.plateNumber, 'SIM-7788');
      expect(ctrl.driverInfo!.hasPhone, isTrue, reason: '撥號按鈕的顯示條件');
    });

    test('WS 已帶司機資訊時，輪詢還原不覆蓋即時值', () async {
      final ctrl = CustomerController(api: _AcceptedActiveApi());
      addTearDown(ctrl.dispose);
      ctrl.setSessionForTest(
        const CustomerSession(customerId: 1, token: 'tok', name: '小美'),
      );
      ctrl.setActiveRideForTest(
        const CustomerRide(rideId: 18, status: RideStatus.assigned),
      );
      ctrl.handleWsEventForTest(
        FleetWsEvent(
          type: FleetEventTypes.rideAccepted,
          rideId: 18,
          payload: const {
            'driver_name': '即時司機',
            'driver_phone': '0987654321',
            'driver_plate_number': 'WS-0001',
            'driver_vehicle_type': 'suv',
          },
        ),
      );

      await ctrl.refreshActive();

      expect(ctrl.driverName, '即時司機');
      expect(ctrl.driverInfo!.phone, '0987654321', reason: 'WS 是最即時的來源');
    });

    test('未接單的訂單不產生空的司機資訊卡', () async {
      final ctrl = CustomerController(api: _AssignedActiveApi());
      addTearDown(ctrl.dispose);
      ctrl.setSessionForTest(
        const CustomerSession(customerId: 1, token: 'tok', name: '小美'),
      );

      await ctrl.refreshActive();

      expect(ctrl.driverInfo, isNull);
      expect(ctrl.driverName, isNull);
    });

    test('CustomerRide.fromJson 解析後端 active 的司機欄位', () {
      final ride = CustomerRide.fromJson(_acceptedRideJson);
      expect(ride.driver, isNotNull);
      expect(ride.driver!.phone, '0912345678');
      expect(ride.driver!.hasVehicle, isTrue);
    });

    test('CustomerRide.fromJson 對沒有司機的訂單回 null，不留空物件', () {
      final ride = CustomerRide.fromJson(const {
        'id': 18,
        'status': RideStatus.assigned,
        'dropoff_address': '台北車站',
      });
      expect(ride.driver, isNull);
    });
  });
}

/// 後端 `GET /api/customer/rides/active` 對已接單訂單的實際回應形狀
/// （2026-07-22 對 docker compose live 後端實測抄回）。
const Map<String, dynamic> _acceptedRideJson = {
  'id': 18,
  'status': RideStatus.accepted,
  'dropoff_address': 'Taipei-Main-Station',
  'eta_pickup_sec': 0,
  'driver_vehicle_type': 'sedan',
  'driver_plate_number': 'SIM-7788',
  'driver_name': '測試司機',
  'driver_phone': '0912345678',
};

class _AcceptedActiveApi extends CustomerApiClient {
  _AcceptedActiveApi()
      : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  @override
  Future<CustomerRide?> activeRide() async =>
      CustomerRide.fromJson(_acceptedRideJson);
}

/// 已派單但司機還沒接：後端不帶任何 driver_* 鍵。
class _AssignedActiveApi extends CustomerApiClient {
  _AssignedActiveApi()
      : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  @override
  Future<CustomerRide?> activeRide() async => CustomerRide.fromJson(const {
        'id': 18,
        'status': RideStatus.assigned,
        'dropoff_address': 'Taipei-Main-Station',
      });
}
