import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/customer_api_client.dart';
import 'package:line_fleet_app/core/config/app_config.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/customer/customer_controller.dart';

/// 同一個乘客帳號登入兩台裝置。
///
/// 後端的 WS Hub 依 **(角色, id)** 扇出，所以同一個帳號的**每一條**連線都收得到
/// 這位乘客的行程事件——司機端早就靠這個特性處理過「另一台裝置接走了這張單」
/// （見 `DriverController._handleWsEvent` 的 `rideAccepted` 註解，已對真後端實測）。
/// 乘客端從來沒有做過同一件事。
class _TwoDeviceApi extends CustomerApiClient {
  _TwoDeviceApi()
    : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  /// 後端當下的「這位乘客的進行中訂單」。null ＝ 沒有。
  CustomerRide? backendActive;
  int activeCalls = 0;

  @override
  Future<CustomerRide?> activeRide() async {
    activeCalls++;
    return backendActive;
  }

  @override
  Future<List<SavedPlace>> fetchSavedPlaces() async => const [];

  @override
  Future<ScheduledRidesResult> fetchScheduledRides({
    bool upcomingOnly = false,
  }) async => const ScheduledRidesResult(rides: [], leadMinutes: 15);

  @override
  Future<List<LostItemRequest>> fetchLostItems() async => const [];
}

CustomerController _deviceB(_TwoDeviceApi api) {
  final ctrl = CustomerController(api: api);
  ctrl.setSessionForTest(
    const CustomerSession(customerId: 1, token: 'tok', name: '小美'),
  );
  return ctrl;
}

void main() {
  group('同一帳號的第二台裝置', () {
    test('B 台閒置時 A 台叫車：B 台收到事件要去跟後端對一次帳', () async {
      final api = _TwoDeviceApi();
      final ctrl = _deviceB(api);
      addTearDown(ctrl.dispose);

      // B 台開著、停在叫車表單：後端此刻沒有進行中訂單。
      await ctrl.refreshActive();
      expect(ctrl.activeRide, isNull, reason: '前置條件：B 台手上什麼都沒有');
      final callsBefore = api.activeCalls;

      // A 台叫車、司機接單 → 後端有訂單了，而且把 ride.accepted 扇出給
      // 這個帳號的每一條連線，包含 B 台。
      api.backendActive = const CustomerRide(
        rideId: 42,
        status: RideStatus.accepted,
        dropoffAddress: '台北車站',
      );
      ctrl.handleWsEventForTest(
        FleetWsEvent(
          type: FleetEventTypes.rideAccepted,
          rideId: 42,
          payload: {'driver_name': '阿明'},
        ),
      );
      await Future<void>.delayed(Duration.zero);

      // 修改前：`if (active == null || event.rideId != active.rideId) return;`
      // 把事件直接丟掉，而且輪詢在「沒有進行中訂單」時是停著的
      // ——B 台會**永遠**停在叫車表單，按下叫車只會拿到「已有進行中訂單」。
      expect(
        api.activeCalls,
        greaterThan(callsBefore),
        reason: '收到不認得的行程事件時要去問後端，不能直接丟掉',
      );
      expect(ctrl.activeRide?.rideId, 42, reason: 'B 台要跟上：畫面上得看得到這趟正在進行的行程');
    });

    test('事件屬於自己已知的那張單時，不多打一次 API', () async {
      final api = _TwoDeviceApi();
      final ctrl = _deviceB(api);
      addTearDown(ctrl.dispose);

      api.backendActive = const CustomerRide(
        rideId: 42,
        status: RideStatus.accepted,
      );
      await ctrl.refreshActive();
      expect(ctrl.activeRide?.rideId, 42, reason: '前置條件：B 台已經有這張單');
      final callsBefore = api.activeCalls;

      ctrl.handleWsEventForTest(
        FleetWsEvent(
          type: FleetEventTypes.rideAccepted,
          rideId: 42,
          payload: {'driver_name': '阿明'},
        ),
      );
      await Future<void>.delayed(Duration.zero);

      // 認得的單走既有路徑：payload 就地套用，而 `rideAccepted` **原本就會**再
      // `refreshActive` 一次補齊完整資料（本輪沒有動它）。
      // 這一案守的是「沒有把已知單的路徑改壞」——尤其不能變成兩次補讀。
      expect(ctrl.driverName, '阿明');
      expect(ctrl.activeRide?.rideId, 42);
      expect(
        api.activeCalls,
        callsBefore + 1,
        reason: 'rideAccepted 既有的那一次補讀還在，且沒有被本輪的對帳加成兩次',
      );
    });

    test('已經有一張單、事件卻是別的 rideId：照舊忽略，不對帳', () async {
      final api = _TwoDeviceApi();
      final ctrl = _deviceB(api);
      addTearDown(ctrl.dispose);

      api.backendActive = const CustomerRide(
        rideId: 42,
        status: RideStatus.accepted,
      );
      await ctrl.refreshActive();
      final callsBefore = api.activeCalls;

      // 乘客一次只會有一張進行中訂單，所以「別的 rideId」＝ 舊單的落隊事件。
      // 對它做對帳沒有意義，還會打破既有的
      // 「別的行程的取消事件不該影響這一趟」那條防線
      // （`customer_cancel_notice_test` 有一案專門守它）。
      ctrl.handleWsEventForTest(
        FleetWsEvent(type: FleetEventTypes.rideCancelled, rideId: 7),
      );
      await Future<void>.delayed(Duration.zero);

      expect(api.activeCalls, callsBefore);
      expect(ctrl.activeRide?.rideId, 42, reason: '這一趟不該被別的單的事件動到');
    });

    test('位置串流與無 rideId 的事件不觸發對帳（避免連續打點）', () async {
      final api = _TwoDeviceApi();
      final ctrl = _deviceB(api);
      addTearDown(ctrl.dispose);

      await ctrl.refreshActive();
      final callsBefore = api.activeCalls;

      // 帶 rideId 的 driver.location：每幾秒一則。若它也觸發對帳，
      // 一台閒置的裝置會在別台跑車期間每幾秒打一次 REST。
      ctrl.handleWsEventForTest(
        FleetWsEvent(type: FleetEventTypes.driverLocation, rideId: 42),
      );
      // 沒有 rideId 的事件同樣不該觸發（沒有東西可以對帳）。
      ctrl.handleWsEventForTest(
        FleetWsEvent(type: FleetEventTypes.driverArrived),
      );
      await Future<void>.delayed(Duration.zero);

      expect(api.activeCalls, callsBefore);
    });
  });
}
