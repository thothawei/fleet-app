import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/fleet_api_client.dart';
import 'package:line_fleet_app/core/config/app_config.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/storage/token_storage.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/driver/driver_controller.dart';

/// 後端 Hub 是 `map[*Client]bool`，**同一個 driver id 的每一條連線都會收到事件**
/// （不覆蓋、不互踢——這點是讀 `internal/events/hub.go` 查證的）。
/// 所以同一位司機的第二台裝置、或 LINE 那條路徑的動作，都會以事件形式送到這台來；
/// 這組測試釘住「別處做的事，這台也要跟上」。
void main() {
  late _MultiDeviceApi api;
  late DriverController ctrl;

  setUp(() {
    api = _MultiDeviceApi();
    ctrl = DriverController(
      storage: MemoryDriverAuthStore(),
      api: api,
      wsFactory: FleetWsClient.silent,
    );
  });

  tearDown(() => ctrl.dispose());

  Future<void> loginWithOffer(int rideId) async {
    await ctrl.init();
    await ctrl.login(lineUserId: 'U', password: 'pw');
    ctrl.handleWsEventForTest(FleetWsEvent(
      type: FleetEventTypes.rideAssigned,
      rideId: rideId,
      payload: const {'address': '台北車站'},
    ));
    expect(ctrl.pendingOffer?.rideId, rideId, reason: '前提：這台亮著接單卡');
  }

  test('別台裝置接走同一張單 → 這台的接單卡收掉，並補出行程卡', () async {
    await loginWithOffer(31);
    // ride.accepted 的收件人就是「接單的那個司機」＝ 自己，只是動作發生在別處。
    api.restoreRide = ActiveRide.fromBackendJson(const {
      'id': 31,
      'status': RideStatus.accepted,
      'pickup_address': '台北車站',
    });

    ctrl.handleWsEventForTest(FleetWsEvent(
      type: FleetEventTypes.rideAccepted,
      rideId: 31,
      payload: const {'dropoff_address': '松山機場'},
    ));
    await Future<void>.delayed(Duration.zero); // 重讀 active 是背景鏈

    expect(ctrl.pendingOffer, isNull, reason: '已經接到了，接單卡不該還留著');
    expect(ctrl.activeRide?.rideId, 31, reason: '行程卡要自己出現，不必等司機按什麼');
  });

  test('自己這台接的單照舊：以事件預載目的地，不重打 active', () async {
    await loginWithOffer(32);
    await ctrl.acceptOffer();
    final callsAfterAccept = api.activeCalls;

    ctrl.handleWsEventForTest(FleetWsEvent(
      type: FleetEventTypes.rideAccepted,
      rideId: 32,
      payload: const {
        'dropoff_address': '松山機場',
        'dropoff_lat': 25.06,
        'dropoff_lng': 121.55,
      },
    ));
    await Future<void>.delayed(Duration.zero);

    expect(ctrl.activeRide?.dropoffAddress, '松山機場');
    expect(api.activeCalls, callsAfterAccept, reason: '同一張單的事件不必再問一次後端');
  });

  test('別處標記了停靠點 → 這台重讀 active 跟上進度', () async {
    await loginWithOffer(33);
    await ctrl.acceptOffer();

    // 後端那邊第一站已經到達了（另一台裝置按的）。
    api.restoreRide = ActiveRide.fromBackendJson(const {
      'id': 33,
      'status': RideStatus.accepted,
      'pickup_address': '台北車站',
      'stops': [
        {
          'id': 1,
          'seq': 1,
          'kind': 'pickup',
          'lat': 25.033,
          'lng': 121.565,
          'passenger_label': 'A',
          'arrived_at': '2026-07-28T10:00:00Z',
        },
        {
          'id': 2,
          'seq': 2,
          'kind': 'dropoff',
          'lat': 25.04,
          'lng': 121.51,
          'passenger_label': 'A',
        },
      ],
    });

    ctrl.handleWsEventForTest(FleetWsEvent(
      type: FleetEventTypes.rideStopUpdated,
      rideId: 33,
      payload: const {},
    ));
    await Future<void>.delayed(Duration.zero);

    expect(ctrl.activeRide?.stops.length, 2);
    expect(ctrl.activeRide?.nextStop?.id, 2,
        reason: '第一站已到達，下一站要前移——這台若不跟上，兩台會對不同的站給操作');
  });

  test('不是這張單的 stop_updated 不動（不同行程互不干擾）', () async {
    await loginWithOffer(34);
    await ctrl.acceptOffer();
    final before = api.activeCalls;

    ctrl.handleWsEventForTest(FleetWsEvent(
      type: FleetEventTypes.rideStopUpdated,
      rideId: 999,
      payload: const {},
    ));
    await Future<void>.delayed(Duration.zero);

    expect(api.activeCalls, before);
  });
}

class _MultiDeviceApi extends FleetApiClient {
  _MultiDeviceApi()
      : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  ActiveRide? restoreRide;
  int activeCalls = 0;

  @override
  void setToken(String? token) {}

  @override
  Future<LoginResult> login({
    required String lineUserId,
    required String password,
  }) async =>
      const LoginResult(driverId: 7, token: 'tok', name: '阿明');

  @override
  Future<ActiveRide?> activeRide() async {
    activeCalls++;
    return restoreRide;
  }

  @override
  Future<String> acceptRide(int rideId) async {
    // 比照真後端：接單成功後 active 立即查得到（見 driver_controller_test 的說明）。
    restoreRide ??= ActiveRide(
      rideId: rideId,
      address: '台北車站',
      phase: DriverRidePhase.enRouteToPickup,
    );
    return '接單成功';
  }

  @override
  Future<DriverVehicle> fetchVehicle() async => const DriverVehicle(
        vehicleType: 'sedan',
        plateNumber: 'ABC-1234',
        hasVehicle: true,
        reviewStatus: VehicleReviewStatus.approved,
        canAccept: true,
      );

  @override
  Future<List<LostItemRequest>> fetchLostItems() async => const [];
}
