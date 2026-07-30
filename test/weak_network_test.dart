import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:line_fleet_app/core/api/customer_api_client.dart';
import 'package:line_fleet_app/core/api/fleet_api_client.dart';
import 'package:line_fleet_app/core/config/app_config.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/storage/customer_token_storage.dart';
import 'package:line_fleet_app/core/storage/token_storage.dart';
import 'package:line_fleet_app/core/theme/app_theme.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/customer/customer_controller.dart';
import 'package:line_fleet_app/driver/driver_controller.dart';
import 'package:line_fleet_app/driver/widgets/online_hero_card.dart';

/// 弱網＝**連得上但通不了**，比整條斷線更難處理：TCP 還在、WS 不會收到 FIN，
/// 所以畫面上的「即時連線正常」是真的（socket 沒死），司機卻早就不在派單池裡。
/// 逾時分支先前只有單元測試層驗過，這組把行為釘住（真裝置實跑見 docs/TODO.md）。
void main() {
  group('司機端：位置回報不可疊起來', () {
    test('前一筆還在路上時，這一個 tick 直接丟掉（不併發、不亂序）', () async {
      final api = _SlowApi();
      final ctrl = await _driver(api);
      addTearDown(ctrl.dispose);
      ctrl.setOnlineForTest(true);

      // 三個 tick 幾乎同時進來（弱網下請求要 20 秒才回，tick 每 8 秒一次）。
      final first = ctrl.reportPositionForTest(_pos(25.03));
      final second = ctrl.reportPositionForTest(_pos(25.04));
      final third = ctrl.reportPositionForTest(_pos(25.05));

      expect(api.inFlight, 1, reason: '同時只能有一筆位置在路上');
      api.complete();
      await Future.wait([first, second, third]);
      expect(api.sentLats, [25.03], reason: '被擋下的 tick 直接丟掉，不排隊補送');

      // 前一筆結束後，下一個 tick 照常送。
      final fourth = ctrl.reportPositionForTest(_pos(25.06));
      expect(api.inFlight, 1);
      api.complete();
      await fourth;
      expect(api.sentLats, [25.03, 25.06]);
    });

    test('回報丟出例外後旗標要放掉（不然之後永遠不再回報）', () async {
      final api = _SlowApi()..failWith = ApiException('請求逾時，請稍後再試');
      final ctrl = await _driver(api);
      addTearDown(ctrl.dispose);
      ctrl.setOnlineForTest(true);

      await ctrl.reportPositionForTest(_pos(25.03));
      expect(ctrl.error, '請求逾時，請稍後再試');

      api.failWith = null;
      final next = ctrl.reportPositionForTest(_pos(25.07));
      expect(api.inFlight, 1, reason: '上一筆失敗後仍要放行下一筆');
      api.complete();
      await next;
      expect(api.sentLats, [25.07]);
    });
  });

  group('司機端：位置過期＝不在派單池，畫面不能說「等待派單中」', () {
    test('locationStale 以後端的離線鮮度窗為準', () async {
      final api = _SlowApi();
      final ctrl = await _driver(api);
      addTearDown(ctrl.dispose);

      expect(ctrl.locationStale, isFalse, reason: '離線時無所謂過期');

      ctrl.setOnlineForTest(true);
      ctrl.markOnlineSinceForTest(
        DateTime.now().subtract(const Duration(seconds: 10)),
      );
      expect(ctrl.locationStale, isFalse, reason: '剛上線的幾秒不能誤報');

      ctrl.markOnlineSinceForTest(
        DateTime.now()
            .subtract(const Duration(seconds: AppConfig.driverOfflineSec + 5)),
      );
      expect(ctrl.locationStale, isTrue);

      // 成功回報一次就恢復。
      final report = ctrl.reportPositionForTest(_pos(25.03));
      api.complete();
      await report;
      expect(ctrl.locationStale, isFalse);
    });

    testWidgets('hero 在位置過期時改成紅底「位置回報失敗，暫時收不到派單」', (tester) async {
      final api = _SlowApi();
      final ctrl = await _driver(api);
      addTearDown(ctrl.dispose);
      ctrl.setOnlineForTest(true);
      ctrl.setWsConnectedForTest(true); // WS 看起來還好好的——弱網就是這樣
      ctrl.markOnlineSinceForTest(
        DateTime.now()
            .subtract(const Duration(seconds: AppConfig.driverOfflineSec + 5)),
      );

      await tester.pumpWidget(MaterialApp(
        theme: appLightTheme,
        home: Scaffold(body: OnlineHeroCard(ctrl: ctrl)),
      ));

      expect(find.text('位置回報失敗，暫時收不到派單'), findsOneWidget);
      expect(find.text('等待派單中'), findsNothing,
          reason: '他不在派單池裡，寫「等待派單中」就是說謊');
    });
  });

  group('接單逾時：後端可能其實接到了', () {
    test('逾時後查到這張單是我的 → 顯示行程卡並清掉逾時訊息', () async {
      final api = _TimeoutAcceptApi()
        ..activeAfterTimeout = ActiveRide.fromBackendJson(const {
          'id': 21,
          'status': RideStatus.accepted,
          'pickup_address': '台北車站',
        });
      final ctrl = await _driver(api);
      addTearDown(ctrl.dispose);

      ctrl.handleWsEventForTest(FleetWsEvent(
        type: FleetEventTypes.rideAssigned,
        rideId: 21,
        payload: const {'pickup_address': '台北車站'},
      ));
      await ctrl.acceptOffer();

      expect(ctrl.activeRide?.rideId, 21,
          reason: '逾時不代表沒接到；再按一次只會拿到「手慢了」——他自己搶走自己的單');
      expect(ctrl.pendingOffer, isNull);
      expect(ctrl.error, isNull);
    });

    test('逾時後後端說沒有這張單 → 維持逾時訊息，接單卡留著讓他重試', () async {
      final api = _TimeoutAcceptApi()..activeAfterTimeout = null;
      final ctrl = await _driver(api);
      addTearDown(ctrl.dispose);

      ctrl.handleWsEventForTest(FleetWsEvent(
        type: FleetEventTypes.rideAssigned,
        rideId: 21,
        payload: const {'pickup_address': '台北車站'},
      ));
      await ctrl.acceptOffer();

      expect(ctrl.activeRide, isNull);
      expect(ctrl.pendingOffer?.rideId, 21);
      expect(ctrl.error, '請求逾時，請稍後再試');
    });
  });

  group('乘客端建單逾時：後端可能其實建好了', () {
    test('逾時後查到訂單 → 直接進追蹤，不留錯誤', () async {
      final api = _TimeoutCreateApi();
      final ctrl = await _customer(api); // init 當下後端還沒有訂單
      addTearDown(ctrl.dispose);
      // 建單其實成立了，只是回應沒回來。
      api.activeAfterTimeout = CustomerRide.fromJson(const {
        'id': 31,
        'status': RideStatus.requested,
        'pickup_address': '台北車站',
      });

      await ctrl.handleCreateFailure(ApiException('請求逾時，請稍後再試'));

      expect(ctrl.activeRide?.rideId, 31,
          reason: '訂單其實成立了；停在叫車畫面＝車在派他卻看不到，再按一次還會撞「已有進行中的訂單」');
      expect(ctrl.error, isNull);
    });

    test('後端明確拒絕（有狀態碼）時不對帳——它本來就沒建單', () async {
      final api = _TimeoutCreateApi();
      final ctrl = await _customer(api);
      addTearDown(ctrl.dispose);
      // 就算後端此刻有一張別的進行中訂單，被 429 擋下的這次建單也不該把它認成自己的成果。
      api.activeAfterTimeout = CustomerRide.fromJson(const {
        'id': 99,
        'status': RideStatus.requested,
        'pickup_address': '別的訂單',
      });

      await ctrl.handleCreateFailure(
        ApiException('叫車太頻繁，請稍後再試', statusCode: 429),
      );

      expect(ctrl.activeRide, isNull);
      expect(ctrl.error, '叫車太頻繁，請稍後再試');
    });

    test('逾時後後端也說沒有 → 保留逾時訊息讓他重試', () async {
      final api = _TimeoutCreateApi()..activeAfterTimeout = null;
      final ctrl = await _customer(api);
      addTearDown(ctrl.dispose);

      await ctrl.handleCreateFailure(ApiException('請求逾時，請稍後再試'));

      expect(ctrl.activeRide, isNull);
      expect(ctrl.error, '請求逾時，請稍後再試');
    });
  });

  // 2026-07-30 模擬器實跑（blackhole cancel ＋ ws_block）抓到的缺口：取消成功卻被報成失敗。
  // 後端真的取消了、回應遺失，App 唯一的回饋是「請求逾時，請稍後再試」——
  // 而 WS 斷線時連「行程已取消」都沒有，乘客無從判斷到底取消了沒有。
  group('乘客端取消逾時：後端可能其實取消了', () {
    test('逾時後後端說這張單沒了 → 清掉逾時訊息，並給「行程已取消」的確認', () async {
      final api = _TimeoutCancelApi()..activeNow = _ride(41);
      final ctrl = await _customer(api);
      addTearDown(ctrl.dispose);
      expect(ctrl.activeRide?.rideId, 41, reason: '前置：畫面上要先有這張進行中訂單');
      // 取消其實成立了，只是回應沒回來。
      api.activeNow = null;

      await ctrl.cancelOrder();

      expect(ctrl.activeRide, isNull);
      expect(ctrl.error, isNull, reason: '取消成功卻說「請求逾時」＝畫面在說謊');
      expect(ctrl.cancelNotice, '行程已取消。',
          reason: 'WS 斷線時沒有 ride.cancelled 事件，這條通知是乘客唯一的確認');
    });

    test('逾時後這張單還在 → 保留逾時訊息，訂單卡留著讓他重試', () async {
      final api = _TimeoutCancelApi()..activeNow = _ride(41);
      final ctrl = await _customer(api);
      addTearDown(ctrl.dispose);

      await ctrl.cancelOrder();

      expect(ctrl.activeRide?.rideId, 41);
      expect(ctrl.error, '請求逾時，請稍後再試');
      expect(ctrl.cancelNotice, isNull, reason: '沒取消成功就不能說「行程已取消」');
    });

    test('409「當下不能取消」多半是上一次逾時其實生效了 → 也要對帳', () async {
      final api = _TimeoutCancelApi()
        ..activeNow = _ride(41)
        ..cancelFailure = ApiException('這張訂單目前無法取消', statusCode: 409);
      final ctrl = await _customer(api);
      addTearDown(ctrl.dispose);
      api.activeNow = null;

      await ctrl.cancelOrder();

      expect(ctrl.activeRide, isNull);
      expect(ctrl.error, isNull);
      expect(ctrl.cancelNotice, '行程已取消。');
    });

    test('後端明確拒絕（其他狀態碼）時不對帳——白問一次也沒用', () async {
      final api = _TimeoutCancelApi()
        ..activeNow = _ride(41)
        ..cancelFailure = ApiException('請重新登入', statusCode: 401);
      final ctrl = await _customer(api);
      addTearDown(ctrl.dispose);
      final callsBefore = api.activeCalls;

      await ctrl.cancelOrder();

      expect(api.activeCalls, callsBefore, reason: '401 不是「不知道成不成功」，不必再問');
      expect(ctrl.error, '請重新登入');
      expect(ctrl.activeRide?.rideId, 41);
    });

    test('對帳時後端換成另一張單 → 套用它，但不掛取消通知', () async {
      final api = _TimeoutCancelApi()..activeNow = _ride(41);
      final ctrl = await _customer(api);
      addTearDown(ctrl.dispose);
      // 這張是來自 LINE／另一台裝置的新單：眼前那張確實取消了，但新單還在進行。
      api.activeNow = _ride(42);

      await ctrl.cancelOrder();

      expect(ctrl.activeRide?.rideId, 42);
      expect(ctrl.error, isNull);
      expect(ctrl.cancelNotice, isNull,
          reason: '掛上取消通知會讓乘客以為這張新單也被取消了');
    });
  });
}

CustomerRide _ride(int id) => CustomerRide.fromJson({
      'id': id,
      'status': RideStatus.requested,
      'pickup_address': '台北車站',
    });

Future<DriverController> _driver(FleetApiClient api) async {
  final ctrl = DriverController(
    storage: MemoryDriverAuthStore()
      ..save(const AuthSession(driverId: 7, token: 'tok')),
    api: api,
    wsFactory: FleetWsClient.silent,
  );
  await ctrl.init();
  return ctrl;
}

Future<CustomerController> _customer(CustomerApiClient api) async {
  final ctrl = CustomerController(
    storage: _MemoryCustomerStorage()
      ..save(const CustomerSession(customerId: 3, token: 'tok')),
    api: api,
    wsFactory: FleetWsClient.silent,
  );
  await ctrl.init();
  return ctrl;
}

Position _pos(double lat) => Position(
      latitude: lat,
      longitude: 121.56,
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

/// 位置回報「掛在半路」的假後端（弱網：連得上但不回應）；呼叫 [complete] 才放行。
class _SlowApi extends FleetApiClient {
  _SlowApi() : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  final sentLats = <double>[];
  int inFlight = 0;
  ApiException? failWith;
  Completer<void>? _gate;

  void complete() {
    final gate = _gate;
    _gate = null;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  void setToken(String? token) {}

  @override
  Future<void> reportLocation({
    required double lat,
    required double lng,
  }) async {
    if (failWith != null) throw failWith!;
    sentLats.add(lat);
    inFlight++;
    final gate = Completer<void>();
    _gate = gate;
    try {
      await gate.future;
    } finally {
      inFlight--;
    }
  }

  @override
  Future<ActiveRide?> activeRide() async => null;

  @override
  Future<List<LostItemRequest>> fetchLostItems() async => const [];

  @override
  Future<DriverVehicle> fetchVehicle() async => const DriverVehicle(
        vehicleType: 'sedan',
        plateNumber: 'ABC-1234',
        hasVehicle: true,
        reviewStatus: VehicleReviewStatus.approved,
        canAccept: true,
      );
}

/// 接單請求逾時（沒有 statusCode ＝沒收到 HTTP 回應）的假後端。
class _TimeoutAcceptApi extends FleetApiClient {
  _TimeoutAcceptApi()
      : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  ActiveRide? activeAfterTimeout;
  var _acceptTried = false;

  @override
  void setToken(String? token) {}

  @override
  Future<String> acceptRide(int rideId) async {
    _acceptTried = true;
    throw ApiException('請求逾時，請稍後再試');
  }

  @override
  Future<ActiveRide?> activeRide() async =>
      _acceptTried ? activeAfterTimeout : null;

  @override
  Future<List<LostItemRequest>> fetchLostItems() async => const [];

  @override
  Future<DriverVehicle> fetchVehicle() async => const DriverVehicle(
        vehicleType: 'sedan',
        plateNumber: 'ABC-1234',
        hasVehicle: true,
        reviewStatus: VehicleReviewStatus.approved,
        canAccept: true,
      );
}

/// 建單請求逾時的假後端。
class _TimeoutCreateApi extends CustomerApiClient {
  // 預約／常用地點：controller.init() 會載這兩份。沒覆寫的話會走真實 Dio 打網路，
  // 在測試裡變成不確定的非同步延遲，把不相干的測試拖成 flaky（實測會讓
  // customer_location_exits 的預估 notifyListeners 落在 dispose 之後）。
  @override
  Future<List<SavedPlace>> fetchSavedPlaces() async => const [];

  @override
  Future<ScheduledRidesResult> fetchScheduledRides({bool upcomingOnly = false}) async =>
      const ScheduledRidesResult(rides: [], leadMinutes: 15);

  _TimeoutCreateApi()
      : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  CustomerRide? activeAfterTimeout;

  @override
  void setToken(String? token) {}

  @override
  Future<CustomerRide> createRide({
    required double pickupLat,
    required double pickupLng,
    required String pickupAddress,
    String? dropoffAddress,
    double? dropoffLat,
    double? dropoffLng,
    List<StopInput> stops = const [],
    String? requiredVehicleType,
  }) async {
    throw ApiException('請求逾時，請稍後再試');
  }

  @override
  Future<CustomerRide?> activeRide() async => activeAfterTimeout;

  @override
  Future<List<LostItemRequest>> fetchLostItems() async => const [];
}

/// 取消「掛在半路」的假後端：`cancelRide` 一律以 [cancelFailure] 失敗，
/// `activeRide` 回 [activeNow]＝後端此刻的真實現況（對帳問的就是它）。
class _TimeoutCancelApi extends CustomerApiClient {
  // 預約／常用地點：controller.init() 會載這兩份。沒覆寫的話會走真實 Dio 打網路，
  // 在測試裡變成不確定的非同步延遲，把不相干的測試拖成 flaky（實測會讓
  // customer_location_exits 的預估 notifyListeners 落在 dispose 之後）。
  @override
  Future<List<SavedPlace>> fetchSavedPlaces() async => const [];

  @override
  Future<ScheduledRidesResult> fetchScheduledRides({bool upcomingOnly = false}) async =>
      const ScheduledRidesResult(rides: [], leadMinutes: 15);

  _TimeoutCancelApi()
      : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  CustomerRide? activeNow;
  ApiException cancelFailure = ApiException('請求逾時，請稍後再試');
  int activeCalls = 0;

  @override
  void setToken(String? token) {}

  @override
  Future<void> cancelRide(int rideId) async => throw cancelFailure;

  @override
  Future<CustomerRide?> activeRide() async {
    activeCalls++;
    return activeNow;
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
