import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/customer_api_client.dart';
import 'package:line_fleet_app/core/api/fleet_api_client.dart';
import 'package:line_fleet_app/core/config/app_config.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/storage/customer_token_storage.dart';
import 'package:line_fleet_app/core/storage/token_storage.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/customer/customer_controller.dart';
import 'package:line_fleet_app/driver/driver_controller.dart';
import 'package:line_fleet_app/shared/widgets/app_lifecycle_reactor.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// App 在背景期間會與後端脫節：WS 可能斷線或變成半開、乘客端的輪詢 timer 不跑。
/// 這組測試釘住「回到前景的那一刻要把畫面校正回真實狀態」。
void main() {
  group('AppLifecycleReactor', () {
    testWidgets('resumed 才通知；inactive／paused 不通知', (tester) async {
      var resumed = 0;
      await tester.pumpWidget(
        AppLifecycleReactor(
          onResumed: () => resumed++,
          child: const MaterialApp(home: SizedBox.shrink()),
        ),
      );

      // 拉下通知欄之類的過場也會送 inactive／hidden——對它們反應會在使用者
      // 根本沒離開 App 時打一堆沒必要的請求。
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(resumed, 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(resumed, 1);
    });

    testWidgets('移除後不再收到通知（不會對已 dispose 的 controller 動手）', (tester) async {
      var resumed = 0;
      await tester.pumpWidget(
        AppLifecycleReactor(
          onResumed: () => resumed++,
          child: const MaterialApp(home: SizedBox.shrink()),
        ),
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(resumed, 0);
    });
  });

  group('司機端回前景：以後端為準重讀行程', () {
    late _ResumeFleetApi api;
    late MemoryDriverAuthStore storage;
    late DriverController ctrl;

    setUp(() {
      api = _ResumeFleetApi();
      storage = MemoryDriverAuthStore();
      ctrl = DriverController(
        storage: storage,
        api: api,
        wsFactory: FleetWsClient.silent,
      );
    });

    tearDown(() => ctrl.dispose());

    // 這是本批的核心案例：司機端沒有輪詢，行程狀態完全靠 WS。背景期間斷過線
    // （切網路、進隧道、系統凍結進程）就再也收不到 ride.cancelled——
    // 回前景後那張行程卡還掛在畫面上，司機會開去接一個已經取消的乘客。
    test('背景期間行程被取消 → 回前景後行程卡消失', () async {
      api.restoreRide = const ActiveRide(
        rideId: 12,
        address: '台北車站',
        phase: DriverRidePhase.enRouteToPickup,
      );
      await storage.save(const AuthSession(driverId: 7, token: 'tok'));
      await ctrl.init();
      expect(ctrl.activeRide?.rideId, 12);

      // 後端那邊已經沒有進行中行程了（乘客取消／逾時），而 App 沒收到那則事件。
      api.restoreRide = null;
      await ctrl.onAppResumed();

      expect(ctrl.activeRide, isNull, reason: '回前景要以後端為準，不能留著已取消的行程');
    });

    test('未登入時不打任何 API（登入頁也在 reactor 底下）', () async {
      await ctrl.init();
      final before = api.activeCalls;
      await ctrl.onAppResumed();
      expect(api.activeCalls, before);
    });
  });

  group('乘客端回前景：不等下一個輪詢週期', () {
    test('立刻對帳一次，且失敗不彈錯誤（不是使用者按出來的）', () async {
      final api = _ResumeCustomerApi();
      final ctrl = CustomerController(
        storage: _MemoryCustomerStorage(),
        api: api,
        wsFactory: FleetWsClient.silent,
      );
      addTearDown(ctrl.dispose);

      await ctrl.login(lineUserId: 'u', password: 'p');
      final before = api.activeCalls;

      api.failActive = true;
      await ctrl.onAppResumed();

      expect(api.activeCalls, before + 1);
      expect(ctrl.error, isNull, reason: '背景對帳的失敗不該蓋住畫面');
    });
  });

  group('FleetWsClient.ensureConnected', () {
    late HttpServer server;
    late Uri wsUri;
    late List<WebSocket> serverSockets;

    setUp(() async {
      serverSockets = [];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      wsUri = Uri.parse('ws://${server.address.host}:${server.port}/ws');
      server.transform(WebSocketTransformer()).listen((socket) {
        serverSockets.add(socket);
        socket.listen((_) {}, onError: (_) {}, cancelOnError: false);
      });
    });

    tearDown(() async {
      for (final s in serverSockets) {
        await s.close().catchError((_) => null);
      }
      await server.close(force: true);
    });

    test('斷線中呼叫 → 立刻重連，不等退避', () async {
      final states = StreamController<bool>.broadcast();
      var connectorCalls = 0;
      final client = FleetWsClient(
        onEvent: (_) {},
        onConnectionChanged: states.add,
        connector: (_) {
          connectorCalls++;
          return WebSocketChannel.connect(wsUri);
        },
      );
      addTearDown(states.close);
      addTearDown(client.disconnect);

      await client.connect('tok');
      expect(await states.stream.first.timeout(const Duration(seconds: 10)), isTrue);

      // 伺服器把連線踢掉 → 進入重連退避。
      final dropped = states.stream.firstWhere((v) => v == false);
      for (final s in serverSockets) {
        await s.close();
      }
      expect(await dropped.timeout(const Duration(seconds: 10)), isFalse);
      expect(client.isConnected, isFalse);

      final callsBefore = connectorCalls;
      final reconnected = states.stream.firstWhere((v) => v == true);
      client.ensureConnected();
      // 退避第一輪是 3 秒；ensureConnected 必須比它快，否則就沒有存在的意義。
      expect(
        await reconnected.timeout(const Duration(seconds: 2)),
        isTrue,
        reason: '回前景時要立刻重連，不能讓使用者再等一輪退避',
      );
      expect(connectorCalls, greaterThan(callsBefore));
      expect(client.reconnectAttempts, 0, reason: '連上後退避歸零');
    });

    test('已連線時不做任何事（不會把好好的連線重建一次）', () async {
      var connectorCalls = 0;
      final client = FleetWsClient(
        onEvent: (_) {},
        connector: (_) {
          connectorCalls++;
          return WebSocketChannel.connect(wsUri);
        },
      );
      addTearDown(client.disconnect);

      await client.connect('tok');
      await _until(() => client.isConnected);
      final calls = connectorCalls;

      client.ensureConnected();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(connectorCalls, calls);
      expect(client.isConnected, isTrue);
    });

    test('登出後呼叫不會偷偷連回去', () async {
      var connectorCalls = 0;
      final client = FleetWsClient(
        onEvent: (_) {},
        connector: (_) {
          connectorCalls++;
          return WebSocketChannel.connect(wsUri);
        },
      );

      await client.connect('tok');
      await _until(() => client.isConnected);
      await client.disconnect();
      final calls = connectorCalls;

      client.ensureConnected();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(connectorCalls, calls);
      expect(client.isConnected, isFalse);
    });
  });
}

Future<void> _until(bool Function() predicate) async {
  for (var i = 0; i < 100; i++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('條件在 5 秒內未成立');
}

class _ResumeFleetApi extends FleetApiClient {
  _ResumeFleetApi()
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

class _ResumeCustomerApi extends CustomerApiClient {
  _ResumeCustomerApi()
      : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  int activeCalls = 0;
  bool failActive = false;

  @override
  void setToken(String? token) {}

  @override
  Future<CustomerLoginResult> login({
    required String lineUserId,
    required String password,
  }) async =>
      const CustomerLoginResult(customerId: 3, token: 'tok', name: '小美');

  @override
  Future<CustomerRide?> activeRide() async {
    activeCalls++;
    if (failActive) throw ApiException('無法連線到伺服器，請檢查網路');
    return null;
  }

  @override
  Future<List<LostItemRequest>> fetchLostItems() async => const [];
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
