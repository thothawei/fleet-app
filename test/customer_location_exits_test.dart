import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:line_fleet_app/core/api/customer_api_client.dart';
import 'package:line_fleet_app/core/location/customer_locator.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/storage/customer_token_storage.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/customer/customer_controller.dart';

/// 乘客端叫車時「定位拿不到」的每一條出口。
///
/// 這是第二十一輪（司機端定位健康度）的同族角落：定位失敗的路徑上，
/// **狀態算得對不代表乘客看得到，看得到也不代表他知道下一步該做什麼**。
/// 原本三條都壞：
/// 1. 系統定位服務關著時 `getCurrentPosition` 丟 `LocationServiceDisabledException`，
///    `_acquirePosition` 只攔 `TimeoutException`、`placeOrder` 只攔 `ApiException`，
///    例外整個穿出去變成未處理的非同步錯誤——`_error` 沒設、busy 被 finally 清掉，
///    乘客按「叫車」轉一下就回到原狀，**畫面上一句話都沒有**。
/// 2. 權限被「永久拒絕」後 `requestPermission` 不會再彈窗，
///    但文案只說「需要定位權限才能叫車」——乘客在 App 裡按到死都按不出結果。
/// 3. 多停靠點行程的 pickup／dropoff 由 stops 推導（後端 prepareStops 會覆蓋座標欄位），
///    根本不需要裝置定位，卻照樣被權限／GPS fix 擋在門外。
void main() {
  StopPoint p(double v) => StopPoint(lat: v, lng: v, address: '地點$v');

  group('單點叫車：定位失敗要說得出下一步', () {
    test('系統定位服務關著 → 明確提示，不可靜默什麼都沒發生', () async {
      final api = _FakeApi();
      final ctrl = await _customer(
        api,
        _FakeLocator()..currentError = const LocationServiceDisabledException(),
      );
      addTearDown(ctrl.dispose);

      await ctrl.placeOrder(pickupAddress: '', dropoffAddress: '信義路');

      expect(ctrl.error, isNotNull,
          reason: '例外穿出去、畫面沒訊息＝乘客只看到按鈕轉一下就沒事了');
      expect(ctrl.error, contains('定位服務'));
      expect(ctrl.busy, isFalse);
      expect(api.createCalls, 0);
    });

    test('權限被永久拒絕 → 要說「到系統設定」（App 裡再按也不會彈窗）', () async {
      final api = _FakeApi();
      final ctrl = await _customer(
        api,
        _FakeLocator()..permission = LocationPermission.deniedForever,
      );
      addTearDown(ctrl.dispose);

      await ctrl.placeOrder(pickupAddress: '', dropoffAddress: '信義路');

      expect(ctrl.error, contains('設定'));
      expect(api.createCalls, 0);
    });

    test('這次被拒（還能再問）與永久拒絕要分開講', () async {
      final denyOnce = _FakeLocator()
        ..permission = LocationPermission.denied
        ..requestResult = LocationPermission.denied;
      final ctrlDenied = await _customer(_FakeApi(), denyOnce);
      addTearDown(ctrlDenied.dispose);
      await ctrlDenied.placeOrder(pickupAddress: '', dropoffAddress: '信義路');

      final forever = _FakeLocator()
        ..permission = LocationPermission.deniedForever;
      final ctrlForever = await _customer(_FakeApi(), forever);
      addTearDown(ctrlForever.dispose);
      await ctrlForever.placeOrder(pickupAddress: '', dropoffAddress: '信義路');

      expect(denyOnce.requestCalls, 1, reason: 'denied 還有機會，要問一次');
      expect(forever.requestCalls, 0,
          reason: 'deniedForever 再問也不會彈窗，問了只是讓乘客以為在等系統對話框');
      expect(ctrlDenied.error, isNot(ctrlForever.error));
    });

    test('檢查通過後權限才被撤 → 也要提示，不是靜默失敗', () async {
      final api = _FakeApi();
      final ctrl = await _customer(
        api,
        _FakeLocator()..currentError = const PermissionDeniedException(null),
      );
      addTearDown(ctrl.dispose);

      await ctrl.placeOrder(pickupAddress: '', dropoffAddress: '信義路');

      expect(ctrl.error, contains('權限'));
      expect(api.createCalls, 0);
    });

    test('拿 fix 逾時但有最後已知位置 → 照樣叫得到車（不要因為室內就不能叫車）', () async {
      final api = _FakeApi();
      final ctrl = await _customer(
        api,
        _FakeLocator()
          ..currentError = TimeoutException('no fix')
          ..lastKnown = _pos(25.03, 121.56),
      );
      addTearDown(ctrl.dispose);

      await ctrl.placeOrder(pickupAddress: '', dropoffAddress: '信義路');

      expect(api.createCalls, 1);
      expect(api.lastPickupLat, 25.03);
      expect(ctrl.error, isNull);
    });

    test('逾時又沒有最後已知位置 → 維持原本可行動的提示', () async {
      final api = _FakeApi();
      final ctrl = await _customer(
        api,
        _FakeLocator()..currentError = TimeoutException('no fix'),
      );
      addTearDown(ctrl.dispose);

      await ctrl.placeOrder(pickupAddress: '', dropoffAddress: '信義路');

      expect(ctrl.error, contains('無法取得定位'));
      expect(api.createCalls, 0);
    });
  });

  group('多停靠點行程：不需要裝置定位', () {
    test('定位服務關著也照樣建單（後端只看 stops）', () async {
      final api = _FakeApi();
      final locator = _FakeLocator()
        ..permission = LocationPermission.deniedForever
        ..currentError = const LocationServiceDisabledException();
      final ctrl = await _customer(api, locator);
      addTearDown(ctrl.dispose);
      ctrl.enableMultiStop();
      ctrl.setPassengerPoint(0, pickup: p(25.05), dropoff: p(25.07));

      await ctrl.placeOrder(pickupAddress: '', dropoffAddress: '');

      expect(api.createCalls, 1,
          reason: 'pickup／dropoff 由 stops 推導，被 GPS 擋住等於白擋');
      expect(ctrl.error, isNull);
      expect(locator.currentCalls, 0, reason: '這條路徑根本不該去問 GPS');
    });

    test('帶出去的 pickup 座標＝第一個上車點（與後端推導的同一組）', () async {
      final api = _FakeApi();
      final ctrl = await _customer(
        api,
        _FakeLocator()..currentError = const LocationServiceDisabledException(),
      );
      addTearDown(ctrl.dispose);
      ctrl.enableMultiStop();
      ctrl.setPassengerPoint(0, pickup: p(25.05), dropoff: p(25.07));
      ctrl.addPassenger();
      ctrl.setPassengerPoint(1, pickup: p(25.06), dropoff: p(25.08));

      await ctrl.placeOrder(pickupAddress: '', dropoffAddress: '');

      expect(api.lastPickupLat, 25.05);
      expect(api.lastPickupLng, 25.05);
      expect(api.lastPickupAddress, '地點25.05',
          reason: '送 (0,0) 會被後端 validatePickupCoords 判成無效座標');
      expect(api.lastStops.length, 4);
    });
  });
}

Position _pos(double lat, double lng) => Position(
      latitude: lat,
      longitude: lng,
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

Future<CustomerController> _customer(_FakeApi api, _FakeLocator locator) async {
  final ctrl = CustomerController(
    storage: _MemoryCustomerStorage()
      ..save(const CustomerSession(customerId: 3, token: 'tok')),
    api: api,
    wsFactory: FleetWsClient.silent,
    locator: locator,
  );
  await ctrl.init();
  return ctrl;
}

/// 假定位：測試自己決定權限狀態、以及取座標時丟哪一種例外。
class _FakeLocator implements CustomerLocator {
  LocationPermission permission = LocationPermission.whileInUse;
  LocationPermission requestResult = LocationPermission.whileInUse;
  Object? currentError;
  Position? lastKnown;
  int requestCalls = 0;
  int currentCalls = 0;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    requestCalls++;
    return requestResult;
  }

  @override
  Future<Position> getCurrentPosition(LocationSettings settings) async {
    currentCalls++;
    if (currentError != null) throw currentError!;
    return _pos(25.0, 121.5);
  }

  @override
  Future<Position?> getLastKnownPosition() async => lastKnown;
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

  int createCalls = 0;
  double? lastPickupLat;
  double? lastPickupLng;
  String? lastPickupAddress;
  List<StopInput> lastStops = const [];

  @override
  void setToken(String? token) {}

  @override
  Future<CustomerRide?> activeRide() async => null;

  @override
  Future<List<LostItemRequest>> fetchLostItems() async => const [];

  @override
  Future<CustomerRide> createRide({
    required double pickupLat,
    required double pickupLng,
    required String pickupAddress,
    String? dropoffAddress,
    double? dropoffLat,
    double? dropoffLng,
    String? requiredVehicleType,
    List<StopInput> stops = const [],
  }) async {
    createCalls++;
    lastPickupLat = pickupLat;
    lastPickupLng = pickupLng;
    lastPickupAddress = pickupAddress;
    lastStops = stops;
    return CustomerRide.fromJson({'ride_id': 1, 'status': 0});
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
