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

    test('login 後即拉協尋工作清單（角標不用等進頁下拉）', () async {
      api.lostItems = [
        LostItemRequest.fromJson({
          'id': 3,
          'ride_id': 5,
          'customer_id': 1,
          'driver_id': 7,
          'description': '黑色錢包',
          'fee_cents': 1000,
          'fee_bps': 1000,
          'status': 'open',
          'created_at': '2026-07-15T10:00:00Z',
        }),
      ];
      await ctrl.init();
      expect(ctrl.lostItems, isEmpty);

      await ctrl.login(lineUserId: 'U_driver', password: 'pw');

      expect(ctrl.lostItems, hasLength(1));
      expect(ctrl.lostItems.single.status, 'open');
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

    test('WS ride.assigned 帶 pickup 座標 → acceptOffer 後 activeRide 有上車點座標', () async {
      // 司機端地圖要標出上車點；address 字串無法定位，座標得從派單事件一路帶到 activeRide。
      await ctrl.init();
      await ctrl.login(lineUserId: 'U_driver', password: 'pw');

      ctrl.handleWsEventForTest(FleetWsEvent(
        type: FleetEventTypes.rideAssigned,
        rideId: 21,
        payload: {
          'address': '台北車站',
          'pickup_lat': 25.0478,
          'pickup_lng': 121.5170,
        },
      ));
      expect(ctrl.pendingOffer?.pickupLat, 25.0478);
      expect(ctrl.pendingOffer?.pickupLng, 121.5170);

      await ctrl.acceptOffer();
      expect(ctrl.activeRide?.pickupLat, 25.0478);
      expect(ctrl.activeRide?.pickupLng, 121.5170);
    });

    test('WS ride.assigned 帶 stops → 接單「當下」activeRide 就有全程（N4）', () async {
      // 實跑抓到：RideOffer 沒解析 stops、acceptOffer 沒帶，接單當下清單與
      // 多點地圖不出現，要重啟 App 走 rides/active 還原才看得到。
      await ctrl.init();
      await ctrl.login(lineUserId: 'U_driver', password: 'pw');

      ctrl.handleWsEventForTest(FleetWsEvent(
        type: FleetEventTypes.rideAssigned,
        rideId: 22,
        payload: {
          'address': '台北101',
          'stops': [
            {'id': 1, 'seq': 1, 'kind': 'pickup', 'lat': 25.033, 'lng': 121.5654, 'passenger_label': 'A'},
            {'id': 2, 'seq': 2, 'kind': 'dropoff', 'lat': 25.04, 'lng': 121.51, 'passenger_label': 'A'},
          ],
        },
      ));
      expect(ctrl.pendingOffer?.hasStops, isTrue);
      expect(ctrl.pendingOffer?.stops.length, 2);

      await ctrl.acceptOffer();
      expect(ctrl.activeRide?.hasStops, isTrue,
          reason: '接單當下就要有全程，不能等 App 重啟還原');
      expect(ctrl.activeRide?.stops.map((s) => s.passengerLabel), ['A', 'A']);
    });

    test('推播喚醒路徑：offer 無 stops，acceptOffer 重讀 active 以後端補齊全程', () async {
      // FCM data 不帶結構化 stops 陣列，所以推播喚醒的 offer 缺全程；接單後
      // 重讀 rides/active 以後端為權威補齊，才不必讓推播 payload 塞 stops。
      await ctrl.init();
      await ctrl.login(lineUserId: 'U_driver', password: 'pw');

      // 後端 active 有全程（模擬 rides/active 回傳的多停靠點行程）。
      api.restoreRide = ActiveRide.fromBackendJson(const {
        'id': 30,
        'status': RideStatus.accepted,
        'pickup_address': '台北101',
        'pickup_point': {'lat': 25.033, 'lng': 121.5654},
        'stops': [
          {'id': 1, 'seq': 1, 'kind': 'pickup', 'lat': 25.033, 'lng': 121.5654, 'passenger_label': 'A'},
          {'id': 2, 'seq': 2, 'kind': 'pickup', 'lat': 25.036, 'lng': 121.568, 'passenger_label': 'B'},
          {'id': 3, 'seq': 3, 'kind': 'dropoff', 'lat': 25.048, 'lng': 121.517, 'passenger_label': 'A'},
          {'id': 4, 'seq': 4, 'kind': 'dropoff', 'lat': 25.04, 'lng': 121.51, 'passenger_label': 'B'},
        ],
      });

      // offer 不帶 stops（推播喚醒路徑）。
      ctrl.handleWsEventForTest(FleetWsEvent(
        type: FleetEventTypes.rideAssigned,
        rideId: 30,
        payload: {'address': '台北101'},
      ));
      expect(ctrl.pendingOffer?.hasStops, isFalse, reason: '前提：offer 無 stops');

      await ctrl.acceptOffer();
      expect(ctrl.activeRide?.hasStops, isTrue,
          reason: '接單後重讀 active 應補齊全程');
      expect(ctrl.activeRide?.stops.length, 4);
    });

    test('acceptOffer 重讀 active 回別的行程／null 時，不覆蓋剛接到的樂觀行程', () async {
      // 防競態：active API 短暫回 null 或回到別的 rideId 時，不能把剛接到的單清掉。
      await ctrl.init();
      await ctrl.login(lineUserId: 'U_driver', password: 'pw');

      // 後端回 rideId 不符（模擬競態）。
      api.restoreRide = ActiveRide.fromBackendJson(const {
        'id': 999,
        'status': RideStatus.accepted,
        'pickup_address': '別的行程',
      });

      ctrl.handleWsEventForTest(FleetWsEvent(
        type: FleetEventTypes.rideAssigned,
        rideId: 55,
        payload: {'address': '士林夜市'},
      ));
      await ctrl.acceptOffer();

      expect(ctrl.activeRide?.rideId, 55, reason: '保留樂觀行程，不被別的 rideId 蓋掉');
      expect(ctrl.activeRide?.address, '士林夜市');
    });

    test('init 還原行程時從 rides/active 的 pickup_point 取得上車點座標', () async {
      await storage.save(const AuthSession(
        driverId: 7,
        token: 'saved',
        name: '阿明',
      ));
      api.restoreRide = ActiveRide.fromBackendJson(const {
        'id': 42,
        'status': RideStatus.accepted,
        'pickup_address': '台北車站',
        'pickup_point': {'lat': 25.0478, 'lng': 121.5170},
        'dropoff_address': '松山機場',
        'dropoff_point': {'lat': 25.06, 'lng': 121.55},
      });

      await ctrl.init();

      expect(ctrl.activeRide?.pickupLat, 25.0478);
      expect(ctrl.activeRide?.pickupLng, 121.5170);
      expect(ctrl.activeRide?.dropoffLat, 25.06);
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
  List<LostItemRequest> lostItems = const [];
  // 預設已填車輛：init()／login() 都會呼叫 fetchVehicle，Fake 沒覆蓋就會打真網路，
  // 讓 testWidgets（FakeAsync）永遠卡住——既有坑，Fake 必須覆蓋 init 觸碰的所有端點。
  DriverVehicle vehicle = const DriverVehicle(
    vehicleType: 'sedan',
    plateNumber: 'ABC-1234',
    hasVehicle: true,
  );
  DriverProfile profile = const DriverProfile(
    driverId: 1,
    name: '測試司機',
    phone: '',
  );
  ApiException? phoneError;
  ApiException? vehicleError;
  final savedVehicles = <String>[];
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
  Future<List<LostItemRequest>> fetchLostItems() async => lostItems;

  @override
  Future<DriverVehicle> fetchVehicle() async {
    if (vehicleError != null) throw vehicleError!;
    return vehicle;
  }

  // init()／login() 也會呼叫 fetchProfile，理由同上方 fetchVehicle 的註解。
  @override
  Future<DriverProfile> fetchProfile() async => profile;

  @override
  Future<DriverProfile> updatePhone(String phone) async {
    if (phoneError != null) throw phoneError!;
    profile = DriverProfile(driverId: 1, name: '測試司機', phone: phone.trim());
    return profile;
  }

  @override
  Future<DriverVehicle> updateVehicle({
    required String vehicleType,
    required String plateNumber,
  }) async {
    if (vehicleError != null) throw vehicleError!;
    savedVehicles.add('$vehicleType/$plateNumber');
    // 模擬後端正規化（去空白、轉大寫）——App 必須以回傳值為準。
    final normalised = plateNumber.replaceAll(' ', '').toUpperCase();
    vehicle = DriverVehicle(
      vehicleType: vehicleType,
      plateNumber: normalised,
      hasVehicle: true,
    );
    return vehicle;
  }

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
