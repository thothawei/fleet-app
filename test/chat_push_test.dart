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

(DriverController, _FakePush) _driver() {
  final push = _FakePush();
  final ctrl = DriverController(
    storage: MemoryDriverAuthStore(), // 未登入：init() 不會打任何 API
    api: _DriverApi(),
    wsFactory: FleetWsClient.silent,
    push: push,
  );
  return (ctrl, push);
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
}

class _CustomerApi extends CustomerApiClient {
  _CustomerApi()
      : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  int activeCalls = 0;

  @override
  Future<CustomerRide?> activeRide() async {
    activeCalls++;
    return null;
  }

  @override
  Future<List<LostItemRequest>> fetchLostItems() async => const [];

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
