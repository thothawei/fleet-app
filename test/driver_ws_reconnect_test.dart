import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/fleet_api_client.dart';
import 'package:line_fleet_app/core/config/app_config.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/storage/token_storage.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/driver/driver_controller.dart';

/// 司機端**沒有任何行程輪詢**（只有定位健康度那支 timer），而 WS 重連
/// **不會補送**斷線期間的事件（見 TODO 第四輪）。所以斷線視窗裡發生的每一件事
/// 都要靠某個人主動去對帳——本檔釘的就是「重連之後有沒有人去問」。
///
/// 乘客端的輪詢**只在有進行中訂單時**才跑，所以它也有同一個洞的一半（本輪一併補）。
class _DriverApi extends FleetApiClient {
  _DriverApi()
    : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  /// 後端當下的「這位司機的進行中訂單」。null ＝ 沒有（例如乘客取消了）。
  ActiveRide? backendActive;
  int activeCalls = 0;

  @override
  Future<ActiveRide?> activeRide() async {
    activeCalls++;
    return backendActive;
  }

  @override
  Future<List<LostItemRequest>> fetchLostItems() async => const [];

  @override
  Future<DriverVehicle> fetchVehicle() async => const DriverVehicle(
    vehicleType: 'sedan',
    plateNumber: 'TEST-01',
    hasVehicle: true,
    canAccept: true,
    reviewStatus: VehicleReviewStatus.approved,
  );
}

/// 讓測試自己驅動連線狀態的假 WS。
class _CapturingWs extends FleetWsClient {
  _CapturingWs({required super.onEvent, super.onConnectionChanged});

  @override
  Future<void> connect(String url, {String? token}) async {}

  @override
  void ensureConnected() {}

  @override
  Future<void> disconnect() async {}

  /// 模擬連線狀態變化（真 client 由 socket 事件觸發同一支 callback）。
  void setConnected(bool connected) => onConnectionChanged?.call(connected);
}

void main() {
  group('司機端 WS 重連後的對帳', () {
    late _CapturingWs ws;

    Future<DriverController> driver(_DriverApi api) async {
      final ctrl = DriverController(
        storage: MemoryDriverAuthStore()
          ..save(const AuthSession(driverId: 7, token: 'tok')),
        api: api,
        wsFactory: ({required onEvent, onConnectionChanged}) {
          ws = _CapturingWs(
            onEvent: onEvent,
            onConnectionChanged: onConnectionChanged,
          );
          return ws;
        },
      );
      await ctrl.init();
      return ctrl;
    }

    test('斷線期間乘客取消了：重連後司機要知道，不能繼續開往上車點', () async {
      final api = _DriverApi()
        ..backendActive = ActiveRide(
          rideId: 42,
          address: '台北車站',
          phase: DriverRidePhase.enRouteToPickup,
        );
      final ctrl = await driver(api);
      addTearDown(ctrl.dispose);
      expect(ctrl.activeRide?.rideId, 42, reason: '前置條件：司機手上有這趟');

      // 第一次連上（production 一定會走到這一步：上線時 WS 才接起來）。
      ws.setConnected(true);

      // 斷線。這段期間乘客取消 → 後端已無進行中訂單，
      // 而 `ride.cancelled` 這則事件**送不到**（WS 重連不補送）。
      ws.setConnected(false);
      api.backendActive = null;
      final callsBefore = api.activeCalls;

      // 重連。
      ws.setConnected(true);
      await Future<void>.delayed(Duration.zero);

      // 修改前：`onConnectionChanged` 只記旗標、notifyListeners，沒有人去問後端；
      // 而司機端沒有輪詢、`onAppResumed` 又要 App 真的進過背景——
      // 一個全程開在前景的司機（開車時的常態）會**繼續開往一個已經取消的上車點**。
      expect(
        api.activeCalls,
        greaterThan(callsBefore),
        reason: '重連後要跟後端對一次帳，斷線期間漏掉的事件只能靠這個補',
      );
      expect(ctrl.activeRide, isNull, reason: '那趟已經沒了，行程卡不該還留著');
    });

    test('第一次連上不重複對帳（init 剛問過）', () async {
      final api = _DriverApi();
      final ctrl = await driver(api);
      addTearDown(ctrl.dispose);
      final callsAfterInit = api.activeCalls;

      // 冷啟動時 WS 第一次連上：init() 才剛 `_restoreActiveRide` 過，
      // 這裡再問一次只是多打一支 API。
      ws.setConnected(true);
      await Future<void>.delayed(Duration.zero);

      expect(api.activeCalls, callsAfterInit);
    });

    test('斷線本身不觸發對帳（問了也問不到）', () async {
      final api = _DriverApi();
      final ctrl = await driver(api);
      addTearDown(ctrl.dispose);
      final callsBefore = api.activeCalls;

      ws.setConnected(false);
      await Future<void>.delayed(Duration.zero);

      expect(api.activeCalls, callsBefore);
    });
  });
}
