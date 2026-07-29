import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/fleet_api_client.dart';
import 'package:line_fleet_app/core/config/app_config.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/storage/token_storage.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/driver/driver_controller.dart';

/// 乘客（或客服）取消已接的訂單時，司機端的行程卡要消失**並說明原因**。
///
/// 後端先前只推 LINE，App 司機一則事件都收不到（dispatch 的 `cancelActiveRide`
/// 只有 `line.PushText`）——司機端**沒有輪詢**，行程卡會一直留著，
/// 他會開去接一個已經取消的乘客。後端補推 `ride.cancelled` 給司機後，
/// App 這側要把「卡片消失」講清楚，否則畫面突然少一張卡只會讓他以為 App 壞了。
void main() {
  group('司機端收到 ride.cancelled', () {
    test('進行中的行程被取消 → 收掉行程卡並說明原因', () async {
      final api = _Api()..restoreRide = _ride(11);
      final ctrl = await _loggedIn(api);
      addTearDown(ctrl.dispose);
      expect(ctrl.activeRide?.rideId, 11, reason: '前置：手上有一張已接的單');

      ctrl.handleWsEventForTest(
        FleetWsEvent(type: FleetEventTypes.rideCancelled, rideId: 11),
      );

      expect(ctrl.activeRide, isNull);
      expect(ctrl.error, '這筆訂單已被取消，不用再前往上車點');
    });

    test('完成不報訊息——那是司機自己按的', () async {
      final api = _Api()..restoreRide = _ride(12);
      final ctrl = await _loggedIn(api);
      addTearDown(ctrl.dispose);

      ctrl.handleWsEventForTest(
        FleetWsEvent(type: FleetEventTypes.rideCompleted, rideId: 12),
      );

      expect(ctrl.activeRide, isNull);
      expect(ctrl.error, isNull);
    });

    test('別張單的取消不動自己的行程卡', () async {
      final api = _Api()..restoreRide = _ride(13);
      final ctrl = await _loggedIn(api);
      addTearDown(ctrl.dispose);

      ctrl.handleWsEventForTest(
        FleetWsEvent(type: FleetEventTypes.rideCancelled, rideId: 99),
      );

      expect(ctrl.activeRide?.rideId, 13);
      expect(ctrl.error, isNull);
    });
  });
}

Future<DriverController> _loggedIn(_Api api) async {
  final ctrl = DriverController(
    storage: MemoryDriverAuthStore()
      ..save(const AuthSession(driverId: 7, token: 'tok')),
    api: api,
    wsFactory: FleetWsClient.silent,
  );
  await ctrl.init();
  return ctrl;
}

ActiveRide _ride(int id) => ActiveRide(
      rideId: id,
      address: '台北101',
      phase: DriverRidePhase.enRouteToPickup,
    );

class _Api extends FleetApiClient {
  _Api() : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  ActiveRide? restoreRide;

  @override
  void setToken(String? token) {}

  @override
  Future<ActiveRide?> activeRide() async => restoreRide;

  @override
  Future<List<LostItemRequest>> fetchLostItems() async => const [];

  @override
  Future<DriverVehicle> fetchVehicle() async => const DriverVehicle(
        vehicleType: 'sedan',
        plateNumber: 'ABC-1234',
        hasVehicle: true,
        reviewStatus: VehicleReviewStatus.approved,
        canAccept: true,
      );
}
