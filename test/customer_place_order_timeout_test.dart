import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/customer_api_client.dart';
import 'package:line_fleet_app/core/api/fleet_api_client.dart' show ApiException;
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/storage/customer_token_storage.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/customer/customer_controller.dart';

/// 建單是**有副作用**的請求：逾時只代表「沒收到回應」，不代表後端沒建。
/// 實測後端：同一乘客第二次建單會被擋下並回 **409「已有進行中的訂單」**——
/// 也就是說，逾時後再按一次，乘客會得到一句與畫面完全矛盾的話
/// （他面前根本沒有任何訂單），而唯一的出路是重開 App。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _CreateFakeApi api;
  late CustomerController ctrl;

  setUp(() {
    // placeOrder 的前半段要定位權限與座標；測試環境沒有平台端，改接管 geolocator 的
    // method channel，讓「取得定位」這段照常成立，才測得到後面的建單與對帳。
    _mockGeolocator();
    api = _CreateFakeApi();
    ctrl = CustomerController(
      storage: _MemoryCustomerStorage(),
      api: api,
      wsFactory: FleetWsClient.silent,
    );
  });

  tearDown(() => ctrl.dispose());

  Future<void> login() => ctrl.login(lineUserId: 'u', password: 'p');

  test('建單逾時但後端其實建好了 → 接手那張單，不報錯', () async {
    await login();
    api.createError = ApiException('請求逾時，請稍後再試'); // statusCode == null
    api.existingRide = _ride(71, RideStatus.requested);

    await ctrl.placeOrder(pickupAddress: '台北101', dropoffAddress: '台北車站');

    expect(ctrl.activeRide?.rideId, 71, reason: '後端有單就該進配對中畫面');
    expect(ctrl.error, isNull, reason: '單其實建起來了，不能說失敗');
  });

  test('重按後拿到 409「已有進行中的訂單」→ 也接手，不把矛盾訊息丟給乘客', () async {
    await login();
    api.createError = ApiException('已有進行中的訂單', statusCode: 409);
    api.existingRide = _ride(72, RideStatus.assigned);

    await ctrl.placeOrder(pickupAddress: '台北101', dropoffAddress: '台北車站');

    expect(ctrl.activeRide?.rideId, 72);
    expect(ctrl.error, isNull);
  });

  test('逾時期間已被司機接走 → 連司機資訊一起帶出來，不必等下一輪輪詢', () async {
    await login();
    api.createError = ApiException('請求逾時，請稍後再試');
    // 司機資訊在後端是**扁平鍵**（與 WS payload 同一組），不是巢狀物件。
    api.existingRide = CustomerRide.fromJson({
      'id': 73,
      'status': RideStatus.accepted,
      'driver_name': '阿明',
      'driver_phone': '0912345678',
      'driver_vehicle_type': 'sedan',
      'driver_plate_number': 'ABC-1234',
    });

    await ctrl.placeOrder(pickupAddress: '台北101', dropoffAddress: '台北車站');

    expect(ctrl.activeRide?.rideId, 73);
    expect(ctrl.driverName, '阿明');
    expect(ctrl.driverInfo?.plateNumber, 'ABC-1234');
  });

  test('逾時且後端真的沒建 → 照常報錯（不能因為對帳就把失敗吞掉）', () async {
    await login();
    api.createError = ApiException('請求逾時，請稍後再試');
    api.existingRide = null;

    await ctrl.placeOrder(pickupAddress: '台北101', dropoffAddress: '台北車站');

    expect(ctrl.activeRide, isNull);
    expect(ctrl.error, '請求逾時，請稍後再試');
  });

  test('對帳本身也失敗（網路仍不通）→ 維持原本的錯誤，不編故事', () async {
    await login();
    api.createError = ApiException('無法連線到伺服器，請檢查網路');
    api.activeError = ApiException('無法連線到伺服器，請檢查網路');

    await ctrl.placeOrder(pickupAddress: '台北101', dropoffAddress: '台北車站');

    expect(ctrl.activeRide, isNull);
    expect(ctrl.error, '無法連線到伺服器，請檢查網路');
  });

  test('400 之類的輸入錯誤不觸發對帳（那是真的沒建）', () async {
    await login();
    api.createError = ApiException('座標格式錯誤', statusCode: 400);
    api.existingRide = _ride(74, RideStatus.requested);
    final callsBefore = api.activeCalls; // 登入時的還原也會查一次

    await ctrl.placeOrder(pickupAddress: '台北101', dropoffAddress: '台北車站');

    expect(ctrl.activeRide, isNull, reason: '不該把別的既有訂單當成這次建單的結果');
    expect(ctrl.error, '座標格式錯誤');
    expect(api.activeCalls, callsBefore, reason: '輸入錯誤不必去問後端有沒有單');
  });

  test('接手的是終態訂單時不算數（剛結束的上一趟不能變成這一趟）', () async {
    await login();
    api.createError = ApiException('請求逾時，請稍後再試');
    api.existingRide = _ride(75, RideStatus.completed);

    await ctrl.placeOrder(pickupAddress: '台北101', dropoffAddress: '台北車站');

    expect(ctrl.activeRide, isNull);
    expect(ctrl.error, '請求逾時，請稍後再試');
  });
}

/// geolocator 的預設實作走 `flutter.baseflow.com/geolocator` 這支 method channel。
/// 權限給 whileInUse（enum 第 3 個 ＝ index 2），位置固定在台北 101。
void _mockGeolocator() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('flutter.baseflow.com/geolocator'),
    (call) async {
      switch (call.method) {
        case 'checkPermission':
        case 'requestPermission':
          return 2; // LocationPermission.whileInUse
        case 'isLocationServiceEnabled':
          return true;
        case 'getCurrentPosition':
        case 'getLastKnownPosition':
          return <String, dynamic>{
            'latitude': 25.0335,
            'longitude': 121.5655,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'accuracy': 5.0,
            'altitude': 0.0,
            'altitude_accuracy': 0.0,
            'heading': 0.0,
            'heading_accuracy': 0.0,
            'speed': 0.0,
            'speed_accuracy': 0.0,
            'is_mocked': true,
          };
      }
      return null;
    },
  );
}

CustomerRide _ride(int id, int status) =>
    CustomerRide.fromJson({'id': id, 'status': status});

class _CreateFakeApi extends CustomerApiClient {
  _CreateFakeApi()
      : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  ApiException? createError;
  ApiException? activeError;
  CustomerRide? existingRide;
  int activeCalls = 0;

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
    if (activeError != null) throw activeError!;
    return existingRide;
  }

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
    List<StopInput> stops = const [],
    String? requiredVehicleType,
  }) async {
    if (createError != null) throw createError!;
    return _ride(1, RideStatus.requested);
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
