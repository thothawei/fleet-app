import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/fleet_api_client.dart';
import 'package:line_fleet_app/core/config/app_config.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/push/driver_push_service.dart';
import 'package:line_fleet_app/core/storage/token_storage.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/driver/driver_controller.dart';

void main() {
  group('DriverController 整合層（注入假 API / 靜默 WS / 記憶體 storage）', () {
    late MemoryDriverAuthStore storage;
    late _FakeFleetApi api;
    late _FakePush push;
    late DriverController ctrl;

    setUp(() {
      storage = MemoryDriverAuthStore();
      api = _FakeFleetApi();
      push = _FakePush();
      ctrl = DriverController(
        storage: storage,
        api: api,
        wsFactory: FleetWsClient.silent,
        push: push,
      );
    });

    tearDown(() => ctrl.dispose());

    test('login 成功→存 session、設 token、WS 連線旗標為 true', () async {
      await ctrl.init();
      await ctrl.login(lineUserId: 'U_driver', password: 'pw');

      expect(ctrl.isLoggedIn, isTrue);
      expect(ctrl.session?.driverId, 7);
      expect(ctrl.session?.name, '阿明');
      expect(ctrl.error, isNull);
      expect(ctrl.wsConnected, isTrue);
      expect(ctrl.fcmAvailable, isTrue);
      expect(ctrl.fcmTokenPrefix, 'fcm-tok-…');
      expect(api.lastToken, 'tok-7');
      expect(api.registeredFcmTokens, ['fcm-tok-abc']);
      expect((await storage.read())?.token, 'tok-7');
    });

    test('login 失敗→顯示錯誤、不登入', () async {
      api.loginError = ApiException('密碼錯誤', statusCode: 401);
      await ctrl.init();
      await ctrl.login(lineUserId: 'U_driver', password: 'bad');

      expect(ctrl.isLoggedIn, isFalse);
      expect(ctrl.error, '密碼錯誤');
    });

    test('init 從 storage 還原 session 並還原進行中行程', () async {
      await storage.save(const AuthSession(
        driverId: 7,
        token: 'saved',
        name: '阿明',
      ));
      api.restoreRide = const ActiveRide(
        rideId: 42,
        address: '台北車站',
        phase: DriverRidePhase.enRouteToPickup,
        dropoffAddress: '松山機場',
      );

      await ctrl.init();

      expect(ctrl.isLoggedIn, isTrue);
      expect(ctrl.activeRide?.rideId, 42);
      expect(ctrl.activeRide?.dropoffAddress, '松山機場');
      expect(api.lastToken, 'saved');
    });

    test('WS ride.assigned 帶 dropoff → acceptOffer 預載目的地', () async {
      await ctrl.init();
      await ctrl.login(lineUserId: 'U_driver', password: 'pw');

      ctrl.handleWsEventForTest(FleetWsEvent(
        type: FleetEventTypes.rideAssigned,
        rideId: 99,
        payload: {
          'address': '士林夜市',
          'dropoff_address': '松山機場',
        },
      ));
      expect(ctrl.pendingOffer?.dropoffAddress, '松山機場');

      await ctrl.acceptOffer();
      expect(ctrl.activeRide?.dropoffAddress, '松山機場');
    });

    test('WS ride.assigned → pendingOffer；acceptOffer → activeRide', () async {
      await ctrl.init();
      await ctrl.login(lineUserId: 'U_driver', password: 'pw');

      ctrl.handleWsEventForTest(FleetWsEvent(
        type: FleetEventTypes.rideAssigned,
        rideId: 99,
        payload: {'address': '士林夜市', 'eta_sec': 180, 'dist_m': 800},
      ));
      expect(ctrl.pendingOffer?.rideId, 99);
      expect(ctrl.pendingOffer?.address, '士林夜市');

      await ctrl.acceptOffer();
      expect(ctrl.pendingOffer, isNull);
      expect(ctrl.activeRide?.rideId, 99);
      expect(ctrl.activeRide?.phase, DriverRidePhase.enRouteToPickup);
      expect(api.acceptedRideIds, [99]);
    });

    test('acceptOffer API 失敗→保留 offer、顯示錯誤', () async {
      await ctrl.init();
      await ctrl.login(lineUserId: 'U_driver', password: 'pw');
      ctrl.handleWsEventForTest(FleetWsEvent(
        type: FleetEventTypes.rideAssigned,
        rideId: 99,
        payload: {'address': '士林夜市'},
      ));
      api.acceptError = ApiException('手慢了');

      await ctrl.acceptOffer();

      expect(ctrl.error, '手慢了');
      expect(ctrl.pendingOffer?.rideId, 99);
      expect(ctrl.activeRide, isNull);
    });

    test('pickUpPassenger → onTrip + dropoff；completeTrip → 清空', () async {
      await ctrl.init();
      await ctrl.login(lineUserId: 'U_driver', password: 'pw');
      ctrl.handleWsEventForTest(FleetWsEvent(
        type: FleetEventTypes.rideAssigned,
        rideId: 3,
        payload: {'address': '上車點'},
      ));
      await ctrl.acceptOffer();

      api.pickUpDropoff = const DropoffInfo(
        address: '松山機場',
        lat: 25.06,
        lng: 121.55,
      );
      await ctrl.pickUpPassenger();
      expect(ctrl.activeRide?.phase, DriverRidePhase.onTrip);
      expect(ctrl.activeRide?.dropoffAddress, '松山機場');
      expect(ctrl.activeRide?.dropoffLat, 25.06);
      expect(ctrl.activeRide?.dropoffLng, 121.55);

      await ctrl.completeTrip();
      expect(ctrl.activeRide, isNull);
      expect(api.completedRideIds, [3]);
    });

    test('abandonTrip → 清空行程', () async {
      await ctrl.init();
      await ctrl.login(lineUserId: 'U_driver', password: 'pw');
      ctrl.handleWsEventForTest(FleetWsEvent(
        type: FleetEventTypes.rideAssigned,
        rideId: 5,
        payload: {'address': '上車點'},
      ));
      await ctrl.acceptOffer();

      await ctrl.abandonTrip();
      expect(ctrl.activeRide, isNull);
      expect(api.cancelledRideIds, [5]);
    });

    test('WS ride.cancelled 清掉相同 ride 的 offer 或 active', () async {
      await ctrl.init();
      await ctrl.login(lineUserId: 'U_driver', password: 'pw');
      ctrl.handleWsEventForTest(FleetWsEvent(
        type: FleetEventTypes.rideAssigned,
        rideId: 8,
        payload: {'address': 'A'},
      ));
      expect(ctrl.pendingOffer?.rideId, 8);

      ctrl.handleWsEventForTest(FleetWsEvent(
        type: FleetEventTypes.rideCancelled,
        rideId: 8,
      ));
      expect(ctrl.pendingOffer, isNull);
    });

    test('WS ride.accepted 預載 dropoff_address', () async {
      await ctrl.init();
      await ctrl.login(lineUserId: 'U_driver', password: 'pw');
      ctrl.handleWsEventForTest(FleetWsEvent(
        type: FleetEventTypes.rideAssigned,
        rideId: 11,
        payload: {'address': '上車'},
      ));
      await ctrl.acceptOffer();

      ctrl.handleWsEventForTest(FleetWsEvent(
        type: FleetEventTypes.rideAccepted,
        rideId: 11,
        payload: {'dropoff_address': '松山機場'},
      ));
      expect(ctrl.activeRide?.dropoffAddress, '松山機場');
      expect(ctrl.activeRide?.phase, DriverRidePhase.enRouteToPickup);
    });

    test('logout → 清 session / offer / ride', () async {
      await ctrl.init();
      await ctrl.login(lineUserId: 'U_driver', password: 'pw');
      ctrl.handleWsEventForTest(FleetWsEvent(
        type: FleetEventTypes.rideAssigned,
        rideId: 1,
        payload: {'address': 'X'},
      ));

      await ctrl.logout();
      expect(ctrl.isLoggedIn, isFalse);
      expect(ctrl.pendingOffer, isNull);
      expect(ctrl.activeRide, isNull);
      expect(await storage.read(), isNull);
      expect(api.lastToken, isNull);
      expect(api.unregisteredFcmTokens, ['fcm-tok-abc']);
    });

    test('FCM 推播事件 → 與 WS 相同顯示 pendingOffer', () async {
      await ctrl.init();
      await ctrl.login(lineUserId: 'U_driver', password: 'pw');

      push.emit(FleetWsEvent(
        type: FleetEventTypes.rideAssigned,
        rideId: 77,
        payload: {'address': '推播上車點'},
      ));
      await Future<void>.delayed(Duration.zero);

      expect(ctrl.pendingOffer?.rideId, 77);
      expect(ctrl.pendingOffer?.address, '推播上車點');
    });

    test('FCM token 輪替 → 向後端重新註冊新 token', () async {
      await ctrl.init();
      await ctrl.login(lineUserId: 'U_driver', password: 'pw');
      expect(api.registeredFcmTokens, ['fcm-tok-abc']);

      push.refreshToken('fcm-tok-new');
      await Future<void>.delayed(Duration.zero);

      expect(api.registeredFcmTokens, ['fcm-tok-abc', 'fcm-tok-new']);
    });
  });
}

/// 覆寫 FleetApiClient，不打真實網路。
class _FakeFleetApi extends FleetApiClient {
  _FakeFleetApi()
      : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  String? lastToken;
  ApiException? loginError;
  ApiException? acceptError;
  ActiveRide? restoreRide;
  DropoffInfo pickUpDropoff = const DropoffInfo();
  final acceptedRideIds = <int>[];
  final completedRideIds = <int>[];
  final cancelledRideIds = <int>[];
  final registeredFcmTokens = <String>[];
  final unregisteredFcmTokens = <String>[];

  @override
  void setToken(String? token) {
    lastToken = token;
  }

  @override
  Future<LoginResult> login({
    required String lineUserId,
    required String password,
  }) async {
    if (loginError != null) throw loginError!;
    return const LoginResult(driverId: 7, token: 'tok-7', name: '阿明');
  }

  @override
  Future<ActiveRide?> activeRide() async => restoreRide;

  @override
  Future<List<LostItemRequest>> fetchLostItems() async => const [];

  @override
  Future<String> acceptRide(int rideId) async {
    if (acceptError != null) throw acceptError!;
    acceptedRideIds.add(rideId);
    return '接單成功';
  }

  @override
  Future<DropoffInfo> pickUp(int rideId) async => pickUpDropoff;

  @override
  Future<void> completeRide(int rideId) async {
    completedRideIds.add(rideId);
  }

  @override
  Future<void> cancelRide(int rideId) async {
    cancelledRideIds.add(rideId);
  }

  @override
  Future<void> reportLocation({required double lat, required double lng}) async {}

  @override
  Future<void> registerDeviceToken({
    required String platform,
    required String token,
  }) async {
    registeredFcmTokens.add(token);
  }

  @override
  Future<void> unregisterDeviceToken({required String token}) async {
    unregisteredFcmTokens.add(token);
  }
}

class _FakePush implements DriverPushService {
  final _controller = StreamController<FleetWsEvent>.broadcast();
  final _tokenRefresh = StreamController<String>.broadcast();

  String currentToken = 'fcm-tok-abc';

  void emit(FleetWsEvent event) => _controller.add(event);

  void refreshToken(String token) {
    currentToken = token;
    _tokenRefresh.add(token);
  }

  @override
  Future<bool> initialize() async => true;

  @override
  bool get isAvailable => true;

  @override
  Future<String?> getToken() async => currentToken;

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
