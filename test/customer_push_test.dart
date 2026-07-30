import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/api_error.dart' show sessionExpiredMessage;
import 'package:line_fleet_app/core/api/customer_api_client.dart';
import 'package:line_fleet_app/core/api/fleet_api_client.dart' show ApiException;
import 'package:line_fleet_app/core/config/app_config.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/push/fleet_push_service.dart';
import 'package:line_fleet_app/core/push/push_payload.dart';
import 'package:line_fleet_app/core/storage/customer_token_storage.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/customer/customer_controller.dart';

/// 乘客端推播接線（第九輪候選 1 的前半）。
///
/// 後端的 `POST/DELETE /api/customer/device-token` 早就在路由上，App 卻從沒呼叫過——
/// 乘客 App 被系統殺掉後就沒有任何管道叫得動他（WS 沒了、15 秒輪詢也停了）。
/// **憑證那半（google-services.json）仍缺**，所以這裡驗的是接線：
/// 有 token 就註冊、登出要註銷、session 失效**不可**去註銷、收到推播要跟後端對帳。
void main() {
  group('device token 註冊／註銷', () {
    test('登入後自動註冊；登出時註銷', () async {
      final api = _FakeApi();
      final push = _FakePush(token: 'tok-abc');
      final ctrl = await _customer(api, push, loggedIn: false);
      addTearDown(ctrl.dispose);

      await ctrl.login(lineUserId: 'c1', password: 'pw');
      expect(api.registered, [('fcm', 'tok-abc')]);

      await ctrl.logout();
      expect(api.unregistered, ['tok-abc']);
    });

    test('session 失效（401）不可去註銷——那支 API 只會再回一次 401', () async {
      final api = _FakeApi();
      final push = _FakePush(token: 'tok-abc');
      final ctrl = await _customer(api, push);
      addTearDown(ctrl.dispose);
      expect(api.registered.length, 1, reason: '還原 session 時就註冊了');

      // 任何一支帶 token 的請求收到 401 → api client 呼叫 onUnauthorized。
      api.failActiveWith = ApiException(sessionExpiredMessage, statusCode: 401);
      api.triggerUnauthorized();
      await Future<void>.delayed(Duration.zero);

      expect(api.unregistered, isEmpty,
          reason: 'token 已失效，再打一次只是多一次 401（也會再觸發一次清理）');
      expect(ctrl.isLoggedIn, isFalse);
      expect(ctrl.error, sessionExpiredMessage);
    });

    test('推播不可用（沒有 Firebase 設定）時不打那支 API', () async {
      final api = _FakeApi();
      final ctrl = await _customer(api, NoOpFleetPushService());
      addTearDown(ctrl.dispose);

      expect(api.registered, isEmpty);

      await ctrl.logout();
      expect(api.unregistered, isEmpty, reason: '沒註冊過就沒有東西要註銷');
    });

    test('註冊失敗要靜默——乘客沒按任何東西，不能讓他以為叫不到車', () async {
      final api = _FakeApi()
        ..failRegisterWith = ApiException('無法連線到伺服器，請檢查網路');
      final ctrl = await _customer(api, _FakePush(token: 'tok-abc'));
      addTearDown(ctrl.dispose);

      expect(ctrl.error, isNull);
      expect(ctrl.isLoggedIn, isTrue, reason: '推播只是輔助管道，註冊失敗不影響登入');
    });

    test('FCM token 輪替 → 用新 token 重新註冊', () async {
      final api = _FakeApi();
      final push = _FakePush(token: 'tok-abc');
      final ctrl = await _customer(api, push);
      addTearDown(ctrl.dispose);

      push.token = 'tok-new';
      push.tokenRefreshController.add('tok-new');
      await Future<void>.delayed(Duration.zero);

      expect(api.registered.last, ('fcm', 'tok-new'));

      await ctrl.logout();
      expect(api.unregistered, ['tok-new'], reason: '註銷的要是目前這一支');
    });
  });

  group('收到推播 → 跟後端對帳（不直接套 payload）', () {
    test('推播只帶 type，畫面資料仍由 REST 補齊', () async {
      final api = _FakeApi()
        ..active = CustomerRide.fromJson(const {
          'id': 55,
          'status': RideStatus.accepted,
          'pickup_address': '台北車站',
          'driver_name': '王司機',
        });
      final push = _FakePush(token: 'tok-abc');
      final ctrl = await _customer(api, push);
      addTearDown(ctrl.dispose);
      final before = api.activeCalls;

      // FCM data 值全是字串、欄位又稀疏——真實推播就長這樣。
      push.emit(const {'type': FleetEventTypes.rideAccepted, 'ride_id': '55'});
      await Future<void>.delayed(Duration.zero);

      expect(api.activeCalls, greaterThan(before));
      expect(ctrl.activeRide?.rideId, 55);
      expect(ctrl.driverName, '王司機',
          reason: '直接套稀疏的 payload 會把司機姓名洗成空的；REST 才是完整的');
    });

    test('對帳失敗要靜默——乘客可能只是點了通知', () async {
      final api = _FakeApi();
      final push = _FakePush(token: 'tok-abc');
      final ctrl = await _customer(api, push);
      addTearDown(ctrl.dispose);
      // 後端在 init 之後才斷線——這樣錯誤只可能來自推播那條路徑。
      api.failActiveWith = ApiException('無法連線到伺服器，請檢查網路');
      expect(ctrl.error, isNull);

      push.emit(const {'type': FleetEventTypes.rideCompleted, 'ride_id': '55'});
      await Future<void>.delayed(Duration.zero);

      expect(ctrl.error, isNull);
    });

    test('未登入時不打 API', () async {
      final api = _FakeApi();
      final push = _FakePush(token: 'tok-abc');
      final ctrl = await _customer(api, push, loggedIn: false);
      addTearDown(ctrl.dispose);
      final before = api.activeCalls;

      push.emit(const {'type': FleetEventTypes.rideAccepted, 'ride_id': '55'});
      await Future<void>.delayed(Duration.zero);

      expect(api.activeCalls, before);
    });
  });

  group('哪些推播算乘客端的', () {
    test('行程狀態變化算，司機位置不算', () {
      FleetWsEvent ev(String type) =>
          FleetWsEvent(type: type, rideId: 1, payload: const {});

      for (final t in [
        FleetEventTypes.rideAccepted,
        FleetEventTypes.driverArrived,
        FleetEventTypes.rideCompleted,
        FleetEventTypes.rideCancelled,
        FleetEventTypes.rideRedispatched,
      ]) {
        expect(isCustomerRidePush(ev(t)), isTrue, reason: t);
      }

      expect(isCustomerRidePush(ev(FleetEventTypes.driverLocation)), isFalse,
          reason: '每 8 秒一則位置，拿它當推播只會把電池與額度燒光');
      expect(isCustomerRidePush(ev(FleetEventTypes.rideAssigned)), isFalse,
          reason: '派單邀請是司機端的');
      expect(isCustomerRidePush(null), isFalse);
    });
  });
}

Future<CustomerController> _customer(
  _FakeApi api,
  FleetPushService push, {
  bool loggedIn = true,
}) async {
  final storage = _MemoryCustomerStorage();
  if (loggedIn) {
    await storage.save(const CustomerSession(customerId: 3, token: 'tok'));
  }
  final ctrl = CustomerController(
    storage: storage,
    api: api,
    wsFactory: FleetWsClient.silent,
    push: push,
  );
  await ctrl.init();
  return ctrl;
}

class _FakeApi extends CustomerApiClient {
  // 預約／常用地點：controller.init() 會載這兩份。沒覆寫的話會走真實 Dio 打網路，
  // 在測試裡變成不確定的非同步延遲，把不相干的測試拖成 flaky（實測會讓
  // customer_location_exits 的預估 notifyListeners 落在 dispose 之後）。
  @override
  Future<List<SavedPlace>> fetchSavedPlaces() async => const [];

  @override
  Future<ScheduledRidesResult> fetchScheduledRides({bool upcomingOnly = false}) async =>
      const ScheduledRidesResult(rides: [], leadMinutes: 15);

  _FakeApi() : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  final registered = <(String, String)>[];
  final unregistered = <String>[];
  CustomerRide? active;
  int activeCalls = 0;
  ApiException? failRegisterWith;
  ApiException? failActiveWith;

  /// 模擬「帶 token 的請求收到 401」——正式路徑由 `_wrap` 呼叫同一個回呼。
  void triggerUnauthorized() => onUnauthorized?.call();

  @override
  void setToken(String? token) {}

  @override
  Future<void> registerDeviceToken({
    required String platform,
    required String token,
  }) async {
    if (failRegisterWith != null) throw failRegisterWith!;
    registered.add((platform, token));
  }

  @override
  Future<void> unregisterDeviceToken({required String token}) async {
    unregistered.add(token);
  }

  @override
  Future<CustomerRide?> activeRide() async {
    activeCalls++;
    if (failActiveWith != null) throw failActiveWith!;
    return active;
  }

  @override
  Future<List<LostItemRequest>> fetchLostItems() async => const [];

  @override
  Future<CustomerLoginResult> login({
    required String lineUserId,
    required String password,
  }) async =>
      const CustomerLoginResult(customerId: 3, token: 'tok', name: '測試乘客');
}

/// 假推播服務：可控 token、可主動送出一則推播 data。
class _FakePush implements FleetPushService {
  _FakePush({required this.token});

  String? token;
  final events = StreamController<FleetWsEvent>.broadcast();
  final tokenRefreshController = StreamController<String>.broadcast();

  /// 依真實 FCM 的樣子送：值全是字串，經 `fleetEventFromPushData` 解析。
  void emit(Map<String, dynamic> data) {
    final event = fleetEventFromPushData(data);
    if (event != null && isCustomerRidePush(event)) events.add(event);
  }

  @override
  Future<bool> initialize() async => true;

  @override
  bool get isAvailable => true;

  @override
  Future<String?> getToken() async => token;

  @override
  Stream<FleetWsEvent> get rideEvents => events.stream;

  @override
  Stream<String> get tokenRefresh => tokenRefreshController.stream;

  @override
  Future<void> dispose() async {
    await events.close();
    await tokenRefreshController.close();
  }
}

class _MemoryCustomerStorage extends CustomerTokenStorage {
  CustomerSession? _saved;

  @override
  Future<CustomerSession?> read() async => _saved;

  @override
  Future<void> save(CustomerSession session) async => _saved = session;

  @override
  Future<void> clear() async => _saved = null;
}
