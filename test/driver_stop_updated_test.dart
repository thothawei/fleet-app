import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/fleet_api_client.dart';
import 'package:line_fleet_app/core/config/app_config.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/storage/token_storage.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/driver/driver_controller.dart';

/// 停靠點在**別處**被標記（同一司機的第二台裝置、或 LINE 那條路徑）時，這台要跟上。
///
/// 後端 `ride.stop_updated` 原本只推給乘客（dispatch#53 已補推給司機），
/// 而司機端連收到也不處理——兩台裝置會停在不同的「下一站」，
/// 那正是司機端唯一給操作按鈕的那一站。
void main() {
  group('司機端 ride.stop_updated（多裝置／跨管道）', () {
    test('同一張單 → 向後端重讀 active，清單跟著前進', () async {
      final api = _StopsApi()
        ..restoreRide = _ride(stops: [_stop(1, arrived: false)])
        ..laterRide = _ride(stops: [_stop(1, arrived: true)]);
      final ctrl = await _loggedIn(api);
      addTearDown(ctrl.dispose);

      expect(ctrl.activeRide?.stops.first.arrived, isFalse, reason: '前置：第一站還沒處理');
      final callsBefore = api.activeCallCount;

      ctrl.handleWsEventForTest(
        FleetWsEvent(type: FleetEventTypes.rideStopUpdated, rideId: 11),
      );
      await Future<void>.delayed(Duration.zero);

      expect(api.activeCallCount, callsBefore + 1, reason: '要以後端為準重讀，不在本地猜');
      expect(
        ctrl.activeRide?.stops.first.arrived,
        isTrue,
        reason: '別台標記了到達，這台的下一站必須跟著前移',
      );
    });

    test('別張單的事件 → 不重讀（別趟的進度不能動到自己這趟）', () async {
      final api = _StopsApi()..restoreRide = _ride(stops: [_stop(1)]);
      final ctrl = await _loggedIn(api);
      addTearDown(ctrl.dispose);
      final callsBefore = api.activeCallCount;

      ctrl.handleWsEventForTest(
        FleetWsEvent(type: FleetEventTypes.rideStopUpdated, rideId: 99),
      );
      await Future<void>.delayed(Duration.zero);

      expect(api.activeCallCount, callsBefore);
    });

    test('重讀失敗 → 靜默，不在司機畫面上跳錯誤', () async {
      final api = _StopsApi()
        ..restoreRide = _ride(stops: [_stop(1)])
        ..activeError = ApiException('無法連線到伺服器，請檢查網路');
      final ctrl = await _loggedIn(api);
      addTearDown(ctrl.dispose);

      ctrl.handleWsEventForTest(
        FleetWsEvent(type: FleetEventTypes.rideStopUpdated, rideId: 11),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        ctrl.error,
        isNull,
        reason: '這不是司機按出來的動作，跳錯誤橫幅只會在他開車時干擾他',
      );
    });
  });
}

Future<DriverController> _loggedIn(_StopsApi api) async {
  final ctrl = DriverController(
    storage: MemoryDriverAuthStore()
      ..save(const AuthSession(driverId: 7, token: 'tok')),
    api: api,
    wsFactory: FleetWsClient.silent,
  );
  // init() 會用掉第一次 activeRide()（還原進行中行程）。
  await ctrl.init();
  return ctrl;
}

ActiveRide _ride({required List<RideStop> stops}) => ActiveRide(
      rideId: 11,
      address: '台北市信義區市府路1號',
      phase: DriverRidePhase.enRouteToPickup,
      stops: stops,
    );

RideStop _stop(int seq, {bool arrived = false}) => RideStop(
      id: seq,
      seq: seq,
      kind: StopKind.pickup,
      lat: 25.033,
      lng: 121.5654,
      passengerLabel: 'A',
      arrivedAt: arrived ? DateTime(2026, 7, 29, 10) : null,
    );

class _StopsApi extends FleetApiClient {
  _StopsApi() : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  /// init() 還原時回的行程；之後的重讀改回 [laterRide]。
  ActiveRide? restoreRide;
  ActiveRide? laterRide;
  ApiException? activeError;
  int activeCallCount = 0;

  @override
  void setToken(String? token) {}

  @override
  Future<ActiveRide?> activeRide() async {
    final first = activeCallCount == 0;
    activeCallCount++;
    if (!first && activeError != null) throw activeError!;
    return first ? restoreRide : (laterRide ?? restoreRide);
  }

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
