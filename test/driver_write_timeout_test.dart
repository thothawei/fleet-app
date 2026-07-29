import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/fleet_api_client.dart';
import 'package:line_fleet_app/core/config/app_config.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/storage/token_storage.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/driver/driver_controller.dart';

/// 行程中的寫入請求逾時：**沒收到回應 ≠ 後端沒收到請求**。
///
/// 第六輪已經替接單（`_adoptRideIfAccepted`）與乘客建單（`_handleCreateFailure`）
/// 做過這件事，但「乘客已上車」「完成行程」「標記停靠點」三條沒有——
/// 逾時後畫面停在舊階段，司機再按一次會被後端 409 擋下，等於他自己擋自己。
/// 其中 `completeTrip` 最嚴重：後端車資已定格，他卻以為這趟沒結束。
///
/// 自癒路徑（WS 事件、回前景對帳）都存在，但**會讓請求逾時的網路通常連 WS 也不通**，
/// 而重連不補送漏掉的事件（見 docs/TODO.md 第四輪）。
void main() {
  group('完成行程逾時', () {
    test('後端其實已完成（active 回 null）→ 行程卡收掉、逾時訊息清掉', () async {
      final api = _TimeoutApi(active: _ride(41, RideStatus.pickedUp))
        ..failCompleteWith = ApiException('請求逾時，請稍後再試');
      final ctrl = await _driver(api);
      addTearDown(ctrl.dispose);
      expect(ctrl.activeRide?.rideId, 41);

      api.active = null; // 完成其實生效了，只是回應沒回來
      await ctrl.completeTrip();

      expect(ctrl.activeRide, isNull,
          reason: '行程卡留著＝司機以為沒完成，可能不敢載下一位；後端那邊車資早就定格了');
      expect(ctrl.error, isNull);
    });

    test('後端說這趟還在進行 → 行程卡留著、逾時訊息也留著', () async {
      final api = _TimeoutApi(active: _ride(41, RideStatus.pickedUp))
        ..failCompleteWith = ApiException('請求逾時，請稍後再試');
      final ctrl = await _driver(api);
      addTearDown(ctrl.dispose);

      await ctrl.completeTrip();

      expect(ctrl.activeRide?.rideId, 41);
      expect(ctrl.error, '請求逾時，請稍後再試', reason: '真的沒完成，就要讓他知道並自己重按');
    });

    test('對帳這一問也失敗 → 不知道就不亂改（畫面與訊息維持原狀）', () async {
      final api = _TimeoutApi(active: _ride(41, RideStatus.pickedUp))
        ..failCompleteWith = ApiException('請求逾時，請稍後再試')
        ..failActiveAfterWrite = ApiException('請求逾時，請稍後再試');
      final ctrl = await _driver(api);
      addTearDown(ctrl.dispose);

      await ctrl.completeTrip();

      expect(ctrl.activeRide?.rideId, 41);
      expect(ctrl.error, '請求逾時，請稍後再試');
    });

    test('後端明確拒絕（有狀態碼）不對帳——它本來就沒處理這個請求', () async {
      final api = _TimeoutApi(active: _ride(41, RideStatus.pickedUp))
        ..failCompleteWith =
            ApiException('此訂單目前無法完成', statusCode: 409);
      final ctrl = await _driver(api);
      addTearDown(ctrl.dispose);

      await ctrl.completeTrip();

      expect(api.activeCallsAfterWrite, 0, reason: '409 是後端的明確回答，不必再問一次');
      expect(ctrl.error, '此訂單目前無法完成');
      expect(ctrl.activeRide?.rideId, 41);
    });
  });

  group('乘客已上車逾時', () {
    test('後端其實已是行程中 → 階段跟著前進、逾時訊息清掉', () async {
      final api = _TimeoutApi(active: _ride(42, RideStatus.accepted))
        ..failPickUpWith = ApiException('請求逾時，請稍後再試');
      final ctrl = await _driver(api);
      addTearDown(ctrl.dispose);
      expect(ctrl.activeRide?.phase, DriverRidePhase.enRouteToPickup);

      api.active = _ride(42, RideStatus.pickedUp); // 上車其實標到了
      await ctrl.pickUpPassenger();

      expect(ctrl.activeRide?.phase, DriverRidePhase.onTrip);
      expect(ctrl.error, isNull);
    });

    test('後端說還沒上車 → 停在原階段並保留訊息', () async {
      final api = _TimeoutApi(active: _ride(42, RideStatus.accepted))
        ..failPickUpWith = ApiException('請求逾時，請稍後再試');
      final ctrl = await _driver(api);
      addTearDown(ctrl.dispose);

      await ctrl.pickUpPassenger();

      expect(ctrl.activeRide?.phase, DriverRidePhase.enRouteToPickup);
      expect(ctrl.error, '請求逾時，請稍後再試');
    });
  });

  group('標記停靠點逾時', () {
    test('後端其實已標到 → 下一站前移、訊息清掉、回報成功', () async {
      final api = _TimeoutApi(
        active: _ride(43, RideStatus.pickedUp, stops: _stops(arrivedFirst: false)),
      )..failStopWith = ApiException('請求逾時，請稍後再試');
      final ctrl = await _driver(api);
      addTearDown(ctrl.dispose);
      expect(ctrl.activeRide?.nextStop?.id, 71);

      api.active =
          _ride(43, RideStatus.pickedUp, stops: _stops(arrivedFirst: true));
      final ok = await ctrl.markStopArrived(71);

      expect(ok, isTrue);
      expect(ctrl.activeRide?.nextStop?.id, 72, reason: '下一站沒前移＝他會對著同一站再按一次');
      expect(ctrl.error, isNull);
    });

    test('後端說那一站還沒處理 → 維持原狀並保留訊息', () async {
      final api = _TimeoutApi(
        active: _ride(43, RideStatus.pickedUp, stops: _stops(arrivedFirst: false)),
      )..failStopWith = ApiException('請求逾時，請稍後再試');
      final ctrl = await _driver(api);
      addTearDown(ctrl.dispose);

      final ok = await ctrl.markStopArrived(71);

      expect(ok, isFalse);
      expect(ctrl.activeRide?.nextStop?.id, 71);
      expect(ctrl.error, '請求逾時，請稍後再試');
    });
  });
}

Future<DriverController> _driver(FleetApiClient api) async {
  final ctrl = DriverController(
    storage: MemoryDriverAuthStore()
      ..save(const AuthSession(driverId: 7, token: 'tok')),
    api: api,
    wsFactory: FleetWsClient.silent,
  );
  await ctrl.init();
  return ctrl;
}

Map<String, dynamic> _ride(
  int id,
  int status, {
  List<Map<String, dynamic>> stops = const [],
}) =>
    {
      'id': id,
      'status': status,
      'pickup_address': '台北車站',
      if (stops.isNotEmpty) 'stops': stops,
    };

List<Map<String, dynamic>> _stops({required bool arrivedFirst}) => [
      {
        'id': 71,
        'seq': 1,
        'kind': 'pickup',
        'lat': 25.03,
        'lng': 121.56,
        'passenger_label': 'A',
        if (arrivedFirst) 'arrived_at': '2026-07-29T10:00:00Z',
      },
      {
        'id': 72,
        'seq': 2,
        'kind': 'pickup',
        'lat': 25.04,
        'lng': 121.57,
        'passenger_label': 'B',
      },
    ];

/// 寫入請求逾時（`statusCode == null` ＝沒收到 HTTP 回應）的假後端。
///
/// [active] 是**後端當下的真實狀態**，測試在寫入之後改它，模擬
/// 「請求其實處理了、只是回應遺失」。
class _TimeoutApi extends FleetApiClient {
  _TimeoutApi({this.active})
      : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  Map<String, dynamic>? active;
  ApiException? failCompleteWith;
  ApiException? failPickUpWith;
  ApiException? failStopWith;

  /// 對帳那一問也失敗（弱網下很可能）。
  ApiException? failActiveAfterWrite;

  var _wrote = false;
  var activeCallsAfterWrite = 0;

  @override
  void setToken(String? token) {}

  @override
  Future<ActiveRide?> activeRide() async {
    if (_wrote) {
      activeCallsAfterWrite++;
      if (failActiveAfterWrite != null) throw failActiveAfterWrite!;
    }
    final a = active;
    return a == null ? null : ActiveRide.fromBackendJson(a);
  }

  @override
  Future<void> completeRide(int rideId) async {
    _wrote = true;
    throw failCompleteWith ?? ApiException('請求逾時，請稍後再試');
  }

  @override
  Future<DropoffInfo> pickUp(int rideId) async {
    _wrote = true;
    throw failPickUpWith ?? ApiException('請求逾時，請稍後再試');
  }

  @override
  Future<void> arriveStop(int rideId, int stopId) async {
    _wrote = true;
    throw failStopWith ?? ApiException('請求逾時，請稍後再試');
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
