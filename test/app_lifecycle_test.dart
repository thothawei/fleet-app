import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/customer_api_client.dart';
import 'package:line_fleet_app/core/api/fleet_api_client.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/storage/customer_token_storage.dart';
import 'package:line_fleet_app/core/storage/token_storage.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/customer/customer_controller.dart';
import 'package:line_fleet_app/driver/driver_controller.dart';
import 'package:line_fleet_app/shared/widgets/app_lifecycle_reactor.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// App 生命週期：切到背景數分鐘再回前景。
///
/// 背景期間系統會關掉 WebSocket、凍結 timer（iOS 一定會）。回前景那一刻，
/// **司機端沒有任何輪詢**——漏掉的 `ride.assigned`／`ride.cancelled` 沒有第二條路
/// 補回來；乘客端的 15 秒輪詢也可能還要再等一輪。這組測試釘住「回前景要做什麼」。
void main() {
  group('WS：回前景立刻重連（不等退避）', () {
    late HttpServer server;
    late Uri wsUri;
    late List<WebSocket> serverSockets;

    Future<void> startServer([int port = 0]) async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      wsUri = Uri.parse('ws://${server.address.host}:${server.port}/ws');
      server.transform(WebSocketTransformer()).listen((socket) {
        serverSockets.add(socket);
        socket.listen((_) {}, onError: (_) {}, cancelOnError: false);
      });
    }

    setUp(() async {
      serverSockets = [];
      await startServer();
    });

    tearDown(() async {
      for (final s in serverSockets) {
        await s.close().catchError((_) => null);
      }
      await server.close(force: true);
    });

    test('斷線後 ensureConnected() 立刻重連，不必等 3 秒起跳的退避', () async {
      final states = StreamController<bool>.broadcast();
      final client = FleetWsClient(
        onEvent: (_) {},
        onConnectionChanged: states.add,
        connector: (_) => WebSocketChannel.connect(wsUri),
      );
      addTearDown(states.close);
      addTearDown(client.disconnect);

      final connected = states.stream.firstWhere((s) => s).timeout(
            const Duration(seconds: 10),
          );
      await client.connect('token-1');
      expect(await connected, isTrue);

      // 模擬「背景期間連線被系統關掉」：伺服器同一個埠斷線後立刻回來。
      final dropped = states.stream.firstWhere((s) => !s).timeout(
            const Duration(seconds: 10),
          );
      final port = server.port;
      for (final s in serverSockets) {
        await s.close();
      }
      serverSockets.clear();
      await server.close(force: true);
      expect(await dropped, isFalse);
      await startServer(port);

      final reconnected = states.stream.firstWhere((s) => s).timeout(
            const Duration(seconds: 10),
          );
      final sw = Stopwatch()..start();
      client.ensureConnected();
      expect(await reconnected, isTrue);
      sw.stop();

      // 退避的第一段就是 3 秒；回前景若還要等它，這段空窗司機收不到任何派單。
      expect(
        sw.elapsed,
        lessThan(const Duration(seconds: 2)),
        reason: 'ensureConnected() 必須立刻重連，不是等下一次退避 timer',
      );
    });

    test('已連上時 ensureConnected() 不動既有連線（不砍掉重開）', () async {
      final states = <bool>[];
      final client = FleetWsClient(
        onEvent: (_) {},
        onConnectionChanged: states.add,
        connector: (_) => WebSocketChannel.connect(wsUri),
      );
      addTearDown(client.disconnect);

      await client.connect('token-1');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(client.isConnected, isTrue);

      client.ensureConnected();
      client.ensureConnected();
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(states, isNot(contains(false)),
          reason: '好好連著的連線不可被回前景打斷');
      expect(client.isConnected, isTrue);
      expect(serverSockets, hasLength(1),
          reason: '重複呼叫不可疊出第二條連線（多的那條沒人管，事件會收兩份）');
    });
  });

  group('司機端：回前景要跟後端重新對帳', () {
    test('背景期間乘客取消了行程 → 回前景後行程卡消失（漏掉的事件由 REST 補回）', () async {
      final adapter = _CountingAdapter({
        '/driver/rides/active': {
          'ride': {
            'id': 42,
            'status': RideStatus.accepted,
            'pickup_address': '台北車站',
          },
        },
        '/driver/lost-items': const {'lost_items': <dynamic>[]},
        '/driver/vehicle': const {
          'vehicle_type': 'sedan',
          'plate_number': 'ABC-1234',
          'has_vehicle': true,
          'review_status': 'approved',
          'can_accept': true,
        },
      });
      late _RecordingWs ws;
      final ctrl = DriverController(
        storage: MemoryDriverAuthStore()
          ..save(const AuthSession(driverId: 7, token: 'tok')),
        api: FleetApiClient(dio: _dio(adapter)),
        wsFactory: ({required onEvent, onConnectionChanged}) =>
            ws = _RecordingWs(
                onEvent: onEvent, onConnectionChanged: onConnectionChanged),
      );
      addTearDown(ctrl.dispose);

      await ctrl.init();
      expect(ctrl.activeRide?.rideId, 42, reason: '前置：背景前手上有一張單');

      // 背景期間乘客取消：後端已經沒有進行中行程，但 WS 事件沒收到。
      adapter.routes['/driver/rides/active'] = const <String, dynamic>{};
      await ctrl.onAppResumed();

      expect(ctrl.activeRide, isNull,
          reason: '司機端沒有輪詢，不在回前景對帳的話畫面會一直停在已取消的行程上');
      expect(ws.ensureCalls, 1, reason: '回前景要立刻重連 WS，不等最長 30 秒的退避');
      expect(adapter.count('/driver/lost-items'), 2, reason: '協尋清單同樣要對帳');
      // 車輛查詢不重打：失敗會把整個畫面換成錯誤頁，等於網路一抖就把司機踢出首頁。
      expect(adapter.count('/driver/vehicle'), 1);
    });

    test('回前景對帳失敗是靜默的（使用者沒按任何東西，不該看到錯誤）', () async {
      final adapter = _CountingAdapter({
        '/driver/rides/active': const <String, dynamic>{},
        '/driver/lost-items': const {'lost_items': <dynamic>[]},
        '/driver/vehicle': const {
          'has_vehicle': true,
          'review_status': 'approved',
          'can_accept': true,
        },
      });
      final ctrl = DriverController(
        storage: MemoryDriverAuthStore()
          ..save(const AuthSession(driverId: 7, token: 'tok')),
        api: FleetApiClient(dio: _dio(adapter)),
        wsFactory: FleetWsClient.silent,
      );
      addTearDown(ctrl.dispose);

      await ctrl.init();
      expect(ctrl.error, isNull);

      adapter.failStatus = 503; // 後端暫時不可用
      await ctrl.onAppResumed();

      expect(ctrl.error, isNull,
          reason: '回前景是背景動作；失敗冒出錯誤橫幅就是 2026-07-28 修掉的那一類');
      expect(ctrl.isLoggedIn, isTrue, reason: '503 不是 session 失效，不可把司機登出');
    });

    test('未登入時回前景不打任何 API', () async {
      final adapter = _CountingAdapter(const {});
      final ctrl = DriverController(
        storage: MemoryDriverAuthStore(),
        api: FleetApiClient(dio: _dio(adapter)),
        wsFactory: FleetWsClient.silent,
      );
      addTearDown(ctrl.dispose);

      await ctrl.init();
      await ctrl.onAppResumed();

      expect(adapter.paths, isEmpty);
    });
  });

  group('乘客端：回前景不必等下一次 15 秒輪詢', () {
    test('立刻對帳一次進行中行程與協尋清單', () async {
      final api = _CountingCustomerApi();
      late _RecordingWs ws;
      final ctrl = CustomerController(
        storage: _MemoryCustomerStorage(),
        api: api,
        wsFactory: ({required onEvent, onConnectionChanged}) =>
            ws = _RecordingWs(
                onEvent: onEvent, onConnectionChanged: onConnectionChanged),
      );
      addTearDown(ctrl.dispose);

      await ctrl.init();
      await ctrl.login(lineUserId: 'u', password: 'p');
      final activeAfterLogin = api.activeCalls;
      final lostAfterLogin = api.lostItemCalls;

      await ctrl.onAppResumed();

      expect(api.activeCalls, activeAfterLogin + 1,
          reason: '背景期間司機可能早就接單了，畫面卻還停在「配對中」');
      expect(api.lostItemCalls, lostAfterLogin + 1);
      expect(ws.ensureCalls, 1);
    });

    test('對帳失敗不彈錯誤（與背景輪詢同一條規則）', () async {
      final api = _CountingCustomerApi();
      final ctrl = CustomerController(
        storage: _MemoryCustomerStorage(),
        api: api,
        wsFactory: FleetWsClient.silent,
      );
      addTearDown(ctrl.dispose);

      await ctrl.init();
      await ctrl.login(lineUserId: 'u', password: 'p');
      expect(ctrl.error, isNull);

      api.fail = true;
      await ctrl.onAppResumed();

      expect(ctrl.error, isNull);
    });

    test('未登入時回前景不打任何 API', () async {
      final api = _CountingCustomerApi();
      final ctrl = CustomerController(
        storage: _MemoryCustomerStorage(),
        api: api,
        wsFactory: FleetWsClient.silent,
      );
      addTearDown(ctrl.dispose);

      await ctrl.init();
      await ctrl.onAppResumed();

      expect(api.activeCalls, 0);
      expect(api.lostItemCalls, 0);
    });
  });

  group('AppLifecycleReactor', () {
    testWidgets('離開前景後回來才通知；inactive 的短暫失焦不算', (tester) async {
      var resumed = 0;
      await tester.pumpWidget(
        AppLifecycleReactor(
          onResumed: () => resumed++,
          child: const MaterialApp(home: SizedBox.shrink()),
        ),
      );

      // 通知列下拉、權限對話框：inactive → resumed，連線不會斷。
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(resumed, 0, reason: '每點一次通知就多打兩支 API 是白花的');

      // 真的切到背景再回來。
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(resumed, 1);

      // 回前景後又一次 inactive 抖動不該再觸發。
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(resumed, 1);
    });
  });
}

Dio _dio(HttpClientAdapter adapter) =>
    Dio(BaseOptions(baseUrl: 'http://test.invalid/api'))
      ..httpClientAdapter = adapter;

/// 依路徑回應並計次的假後端；[failStatus] 設了之後一律回該狀態碼。
class _CountingAdapter implements HttpClientAdapter {
  _CountingAdapter(Map<String, Map<String, dynamic>> routes)
      : routes = Map.of(routes);

  final Map<String, Map<String, dynamic>> routes;
  final paths = <String>[];
  int? failStatus;

  int count(String path) => paths.where((p) => p == path).length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    if (failStatus != null) {
      return ResponseBody.fromString(
        jsonEncode(const {'error': '服務暫時無法使用'}),
        failStatus!,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode(routes[options.path] ?? const <String, dynamic>{}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 記錄 `ensureConnected()` 被叫過幾次的 WS 替身（不開真連線）。
class _RecordingWs extends FleetWsClient {
  _RecordingWs({required super.onEvent, super.onConnectionChanged});

  int ensureCalls = 0;

  @override
  Future<void> connect(String token) async => onConnectionChanged?.call(true);

  @override
  void ensureConnected() => ensureCalls++;

  @override
  Future<void> disconnect() async => onConnectionChanged?.call(false);
}

class _CountingCustomerApi extends CustomerApiClient {
  _CountingCustomerApi()
      : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  int activeCalls = 0;
  int lostItemCalls = 0;
  bool fail = false;

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
    if (fail) throw ApiException('無法連線到伺服器，請檢查網路');
    return null;
  }

  @override
  Future<List<LostItemRequest>> fetchLostItems() async {
    lostItemCalls++;
    if (fail) throw ApiException('無法連線到伺服器，請檢查網路');
    return const [];
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
