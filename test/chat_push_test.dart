import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/customer_api_client.dart';
import 'package:line_fleet_app/core/api/fleet_api_client.dart';
import 'package:line_fleet_app/core/config/app_config.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/push/fleet_push_service.dart';
import 'package:line_fleet_app/core/push/push_payload.dart';
import 'package:line_fleet_app/core/storage/customer_token_storage.dart';
import 'package:line_fleet_app/core/storage/token_storage.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/customer/customer_controller.dart';
import 'package:line_fleet_app/driver/driver_controller.dart';

/// 對話訊息的推播（後端 dispatch 同批補上送出路徑）。
///
/// 先前對話**只走 WS**：對方 App 一離開前景 WS 就斷了，訊息只會躺在伺服器上，
/// 要等他自己再打開 App 才看得到——這對「司機到了要聯絡乘客」「乘客回報遺失物」
/// 都是致命的。
///
/// App 這端要做兩件事：把 `chat.message` 放進兩端的推播白名單、
/// 收到時**只點亮未讀角標**（內容等聊天室自己以 REST 補齊——推播 data 只有
/// `type` 與 `ride_id`，餵給 `RideMessage.fromJson` 只會解析失敗被丟掉）。
void main() {
  group('哪些推播收得下來', () {
    FleetWsEvent ev(String type) =>
        FleetWsEvent(type: type, rideId: 1, payload: const {});

    test('chat.message 兩端都收', () {
      expect(isChatPush(ev(FleetEventTypes.chatMessage)), isTrue);
      expect(isDriverPush(ev(FleetEventTypes.chatMessage)), isTrue);
      expect(isCustomerPush(ev(FleetEventTypes.chatMessage)), isTrue);
    });

    test('協尋單兩端也收', () {
      for (final t in [
        FleetEventTypes.lostItemCreated,
        FleetEventTypes.lostItemUpdated,
      ]) {
        expect(isLostItemPush(ev(t)), isTrue, reason: t);
        expect(isDriverPush(ev(t)), isTrue, reason: t);
        expect(isCustomerPush(ev(t)), isTrue, reason: t);
      }
    });

    test('原本的白名單沒有被放寬', () {
      // 司機端仍只要派單邀請（＋對話）。
      expect(isDriverPush(ev(FleetEventTypes.rideAssigned)), isTrue);
      expect(isDriverPush(ev(FleetEventTypes.rideCompleted)), isFalse);
      expect(isDriverPush(ev(FleetEventTypes.driverLocation)), isFalse);

      // 乘客端仍是行程狀態五種（＋對話）。
      expect(isCustomerPush(ev(FleetEventTypes.rideAccepted)), isTrue);
      expect(isCustomerPush(ev(FleetEventTypes.rideAssigned)), isFalse,
          reason: '派單邀請是司機端的');
      expect(isCustomerPush(ev(FleetEventTypes.driverLocation)), isFalse,
          reason: '每 8 秒一則位置，拿它當推播只會把電池與額度燒光');
    });
  });

  group('司機端', () {
    test('收到對話推播 → 未讀角標 +1', () async {
      final ctrl = _driver();
      addTearDown(ctrl.$1.dispose);
      await ctrl.$1.init();
      expect(ctrl.$1.unreadChat, 0);

      ctrl.$2.emit(FleetWsEvent(
        type: FleetEventTypes.chatMessage,
        rideId: 9,
        payload: const {},
      ));
      await Future<void>.delayed(Duration.zero);

      expect(ctrl.$1.unreadChat, 1);
    });

    test('聊天室開著時忽略——同一則 WS 已經送到並顯示了', () async {
      final ctrl = _driver();
      addTearDown(ctrl.$1.dispose);
      await ctrl.$1.init();
      ctrl.$1.setChatVisible(true);

      ctrl.$2.emit(FleetWsEvent(
        type: FleetEventTypes.chatMessage,
        rideId: 9,
        payload: const {},
      ));
      await Future<void>.delayed(Duration.zero);

      expect(ctrl.$1.unreadChat, 0);
    });

    test('協尋推播 → 重讀協尋清單（推播 data 沒有協尋單本體）', () async {
      final ctrl = _driver(loggedIn: true);
      addTearDown(ctrl.$1.dispose);
      await ctrl.$1.init();
      final before = ctrl.$3.lostItemCalls;

      ctrl.$2.emit(FleetWsEvent(
        type: FleetEventTypes.lostItemCreated,
        rideId: 9,
        payload: const {},
      ));
      await Future<void>.delayed(Duration.zero);

      expect(ctrl.$3.lostItemCalls, greaterThan(before),
          reason: '推播 data 沒有協尋單本體，只能靠重讀清單');
    });

    test('派單推播照樣開接單卡（多一層分流不能把原路徑弄斷）', () async {
      final ctrl = _driver();
      addTearDown(ctrl.$1.dispose);
      await ctrl.$1.init();

      ctrl.$2.emit(FleetWsEvent(
        type: FleetEventTypes.rideAssigned,
        rideId: 21,
        payload: const {'address': '台北車站', 'eta_sec': 300, 'dist_m': 1200},
      ));
      await Future<void>.delayed(Duration.zero);

      expect(ctrl.$1.pendingOffer?.rideId, 21);
      expect(ctrl.$1.pendingOffer?.address, '台北車站');
    });
  });

  group('乘客端', () {
    test('收到對話推播 → 未讀角標 +1，且不必重讀行程', () async {
      final api = _CustomerApi();
      final push = _FakePush();
      final ctrl = await _customer(api, push);
      addTearDown(ctrl.dispose);
      final activeCallsBefore = api.activeCalls;

      push.emit(FleetWsEvent(
        type: FleetEventTypes.chatMessage,
        rideId: 9,
        payload: const {},
      ));
      await Future<void>.delayed(Duration.zero);

      expect(ctrl.unreadChat, 1);
      expect(api.activeCalls, activeCallsBefore,
          reason: '對話訊息不影響行程狀態，多打 API 只是浪費');
    });

    test('聊天室開著時忽略', () async {
      final api = _CustomerApi();
      final push = _FakePush();
      final ctrl = await _customer(api, push);
      addTearDown(ctrl.dispose);
      ctrl.setChatVisible(true);

      push.emit(FleetWsEvent(
        type: FleetEventTypes.chatMessage,
        rideId: 9,
        payload: const {},
      ));
      await Future<void>.delayed(Duration.zero);

      expect(ctrl.unreadChat, 0);
    });

    test('協尋推播 → 只重讀協尋清單，不重讀行程', () async {
      final api = _CustomerApi();
      final push = _FakePush();
      final ctrl = await _customer(api, push);
      addTearDown(ctrl.dispose);
      final activeBefore = api.activeCalls;
      final lostBefore = api.lostItemCalls;

      push.emit(FleetWsEvent(
        type: FleetEventTypes.lostItemUpdated,
        rideId: 9,
        payload: const {},
      ));
      await Future<void>.delayed(Duration.zero);

      expect(api.lostItemCalls, greaterThan(lostBefore));
      expect(api.activeCalls, activeBefore,
          reason: '協尋單變了不代表行程變了');
    });

    test('行程狀態推播仍走對帳（沒被對話那條分流吃掉）', () async {
      final api = _CustomerApi();
      final push = _FakePush();
      final ctrl = await _customer(api, push);
      addTearDown(ctrl.dispose);
      final before = api.activeCalls;

      push.emit(FleetWsEvent(
        type: FleetEventTypes.driverArrived,
        rideId: 9,
        payload: const {},
      ));
      await Future<void>.delayed(Duration.zero);

      expect(api.activeCalls, greaterThan(before));
    });
  });
}

(DriverController, _FakePush, _DriverApi) _driver({bool loggedIn = false}) {
  final push = _FakePush();
  final api = _DriverApi();
  final storage = MemoryDriverAuthStore();
  if (loggedIn) {
    storage.save(const AuthSession(driverId: 7, token: 'tok', name: '阿明'));
  }
  final ctrl = DriverController(
    storage: storage,
    api: api,
    wsFactory: FleetWsClient.silent,
    push: push,
  );
  return (ctrl, push, api);
}

Future<CustomerController> _customer(_CustomerApi api, _FakePush push) async {
  final storage = _MemoryCustomerStorage();
  await storage.save(const CustomerSession(customerId: 3, token: 'tok'));
  final ctrl = CustomerController(
    storage: storage,
    api: api,
    wsFactory: FleetWsClient.silent,
    push: push,
  );
  await ctrl.init();
  return ctrl;
}

class _DriverApi extends FleetApiClient {
  _DriverApi() : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  int lostItemCalls = 0;

  @override
  Future<ActiveRide?> activeRide() async => null;

  @override
  Future<DriverVehicle> fetchVehicle() async => const DriverVehicle(
        vehicleType: 'sedan',
        plateNumber: 'ABC-1234',
        hasVehicle: true,
      );

  @override
  Future<List<LostItemRequest>> fetchLostItems() async {
    lostItemCalls++;
    return const [];
  }

  @override
  Future<void> registerDeviceToken({
    required String platform,
    required String token,
  }) async {}
}

class _CustomerApi extends CustomerApiClient {
  // 預約／常用地點：controller.init() 會載這兩份。沒覆寫的話會走真實 Dio 打網路，
  // 在測試裡變成不確定的非同步延遲，把不相干的測試拖成 flaky（實測會讓
  // customer_location_exits 的預估 notifyListeners 落在 dispose 之後）。
  @override
  Future<List<SavedPlace>> fetchSavedPlaces() async => const [];

  @override
  Future<ScheduledRidesResult> fetchScheduledRides({bool upcomingOnly = false}) async =>
      const ScheduledRidesResult(rides: [], leadMinutes: 15);

  _CustomerApi()
      : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  int activeCalls = 0;
  int lostItemCalls = 0;

  @override
  Future<CustomerRide?> activeRide() async {
    activeCalls++;
    return null;
  }

  @override
  Future<List<LostItemRequest>> fetchLostItems() async {
    lostItemCalls++;
    return const [];
  }

  @override
  Future<void> registerDeviceToken({
    required String platform,
    required String token,
  }) async {}

  @override
  Future<void> unregisterDeviceToken({required String token}) async {}
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

class _FakePush implements FleetPushService {
  final _controller = StreamController<FleetWsEvent>.broadcast();
  final _tokenRefresh = StreamController<String>.broadcast();

  void emit(FleetWsEvent event) => _controller.add(event);

  @override
  Future<bool> initialize() async => true;

  @override
  bool get isAvailable => true;

  @override
  Future<String?> getToken() async => 'fcm-tok';

  @override
  Stream<FleetWsEvent> get rideEvents => _controller.stream;

  @override
  Stream<String> get tokenRefresh => _tokenRefresh.stream;

  @override
  Future<void> dispose() async {
    await _tokenRefresh.close();
    await _controller.close();
  }
}
