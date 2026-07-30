import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/customer_api_client.dart';
import 'package:line_fleet_app/core/api/fleet_api_client.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/storage/customer_token_storage.dart';
import 'package:line_fleet_app/core/storage/token_storage.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/customer/customer_controller.dart';
import 'package:line_fleet_app/driver/driver_controller.dart';

/// 協尋單的六個寫入路徑（乘客三、司機三）先前都沒有逾時對帳：
/// 例外原樣丟給畫面，畫面只顯示訊息、不會再查那張單。
/// 於是**後端其實做到了、只是回應遺失**的那一次會被報成失敗——
/// 其中 `payLostItem` 是付款，逾時後乘客不知道自己付了沒有。
/// 這組把「逾時後要再問一次後端」的行為釘住（實跑證據見 docs/TODO.md 第十六輪）。
void main() {
  group('乘客端 payLostItem：後端可能其實收到付款了', () {
    test('逾時後後端已記到 paid_at → 當成成功，清單同步成 paid', () async {
      final api = _CustomerLostItemApi()
        ..failWith = ApiException('請求逾時，請稍後再試')
        ..freshItem = _item(status: LostItemStatus.paid, paid: true);
      final ctrl = await _customer(api);
      addTearDown(ctrl.dispose);

      final item = await ctrl.payLostItem(3, rideId: 5);

      expect(item.status, LostItemStatus.paid);
      expect(ctrl.lostItems.single.status, LostItemStatus.paid,
          reason: '對帳查到的狀態要合併回清單，否則畫面還停在「待支付」');
    });

    test('逾時後後端還是 found（沒付到）→ 丟回原本的逾時錯誤', () async {
      final api = _CustomerLostItemApi()
        ..failWith = ApiException('請求逾時，請稍後再試')
        ..freshItem = _item(status: LostItemStatus.found);
      final ctrl = await _customer(api);
      addTearDown(ctrl.dispose);

      await expectLater(
        ctrl.payLostItem(3, rideId: 5),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', '請求逾時，請稍後再試')),
      );
    });

    test('409「這張單現在不能付款」＋後端已 paid → 也算成功（上一次其實付到了）',
        () async {
      final api = _CustomerLostItemApi()
        ..failWith = ApiException('這張協尋單目前無法付款', statusCode: 409)
        ..freshItem = _item(status: LostItemStatus.paid, paid: true);
      final ctrl = await _customer(api);
      addTearDown(ctrl.dispose);

      final item = await ctrl.payLostItem(3, rideId: 5);

      expect(item.paidAt, isNotNull);
    });

    test('後端明確拒絕（其他狀態碼）時不對帳——白問一次也沒用', () async {
      final api = _CustomerLostItemApi()
        ..failWith = ApiException('請重新登入', statusCode: 401)
        ..freshItem = _item(status: LostItemStatus.paid, paid: true);
      final ctrl = await _customer(api);
      addTearDown(ctrl.dispose);

      await expectLater(
        ctrl.payLostItem(3, rideId: 5),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 401)),
      );
      expect(api.byRideCalls, 0, reason: '401 不是「不知道成不成功」，不必再問');
    });

    test('對帳查詢自己也失敗 → 丟回原本那個錯誤，不是查詢的錯誤', () async {
      final api = _CustomerLostItemApi()
        ..failWith = ApiException('請求逾時，請稍後再試')
        ..byRideFailure = ApiException('連線中斷');
      final ctrl = await _customer(api);
      addTearDown(ctrl.dispose);

      await expectLater(
        ctrl.payLostItem(3, rideId: 5),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', '請求逾時，請稍後再試')),
      );
    });
  });

  group('乘客端 closeLostItem／reportLostItem 的逾時對帳', () {
    test('取消協尋逾時後後端已 closed → 當成成功，清單移除這張單', () async {
      final api = _CustomerLostItemApi()
        ..failWith = ApiException('請求逾時，請稍後再試')
        ..freshItem = _item(status: LostItemStatus.closed);
      final ctrl = await _customer(api);
      addTearDown(ctrl.dispose);

      final item = await ctrl.closeLostItem(3, rideId: 5);

      expect(item.status, LostItemStatus.closed);
      expect(ctrl.lostItems, isEmpty, reason: '結案的單不留在未結案清單裡');
    });

    test('回報遺失逾時後查到一張未結案的單 → 那就是這次建的', () async {
      final api = _CustomerLostItemApi()
        ..failWith = ApiException('請求逾時，請稍後再試')
        ..freshItem = _item(status: LostItemStatus.open);
      final ctrl = await _customer(api);
      addTearDown(ctrl.dispose);

      final item = await ctrl.reportLostItem(5, '黑色錢包');

      expect(item.status, LostItemStatus.open);
      expect(ctrl.lostItems.single.id, 3);
    });

    test('回報遺失逾時後只查到舊的結案單 → 不能認成這次建的', () async {
      final api = _CustomerLostItemApi()
        ..failWith = ApiException('請求逾時，請稍後再試')
        ..freshItem = _item(status: LostItemStatus.closed);
      final ctrl = await _customer(api);
      addTearDown(ctrl.dispose);

      await expectLater(
        ctrl.reportLostItem(5, '黑色錢包'),
        throwsA(isA<ApiException>()),
      );
      expect(ctrl.lostItems, isEmpty);
    });
  });

  group('司機端協尋寫入的逾時對帳', () {
    test('標尋獲逾時後後端已 found → 當成成功', () async {
      final api = _DriverLostItemApi()
        ..failWith = ApiException('請求逾時，請稍後再試')
        ..freshItem = _item(status: LostItemStatus.found);
      final ctrl = await _driver(api);
      addTearDown(ctrl.dispose);

      final item = await ctrl.markLostItemFound(3, rideId: 5);

      expect(item.status, LostItemStatus.found);
      expect(ctrl.lostItems.single.status, LostItemStatus.found);
    });

    test('標尋獲逾時後那張單被結案了 → 不能認成尋獲成功', () async {
      final api = _DriverLostItemApi()
        ..failWith = ApiException('請求逾時，請稍後再試')
        ..freshItem = _item(status: LostItemStatus.closed);
      final ctrl = await _driver(api);
      addTearDown(ctrl.dispose);

      await expectLater(
        ctrl.markLostItemFound(3, rideId: 5),
        throwsA(isA<ApiException>()),
      );
    });

    test('標歸還逾時後後端已 returned → 當成成功，工作清單移除', () async {
      final api = _DriverLostItemApi()
        ..failWith = ApiException('請求逾時，請稍後再試')
        ..freshItem = _item(status: LostItemStatus.returned, paid: true);
      final ctrl = await _driver(api);
      addTearDown(ctrl.dispose);

      final item = await ctrl.markLostItemReturned(3, rideId: 5);

      expect(item.status, LostItemStatus.returned);
      expect(ctrl.lostItems, isEmpty);
    });

    test('標歸還逾時後後端仍是 paid → 丟回原本的錯誤（還沒歸還）', () async {
      final api = _DriverLostItemApi()
        ..failWith = ApiException('請求逾時，請稍後再試')
        ..freshItem = _item(status: LostItemStatus.paid, paid: true);
      final ctrl = await _driver(api);
      addTearDown(ctrl.dispose);

      await expectLater(
        ctrl.markLostItemReturned(3, rideId: 5),
        throwsA(isA<ApiException>()),
      );
    });
  });
}

LostItemRequest _item({required String status, bool paid = false}) =>
    LostItemRequest.fromJson({
      'id': 3,
      'ride_id': 5,
      'customer_id': 1,
      'driver_id': 7,
      'description': '黑色錢包',
      'fee_cents': 1000,
      'status': status,
      'paid_at': paid ? '2026-07-30T10:00:00Z' : null,
      'created_at': '2026-07-30T09:00:00Z',
    });

Future<CustomerController> _customer(CustomerApiClient api) async {
  final ctrl = CustomerController(
    storage: _MemoryCustomerStorage()
      ..save(const CustomerSession(customerId: 1, token: 'tok')),
    api: api,
    wsFactory: FleetWsClient.silent,
  );
  await ctrl.init();
  return ctrl;
}

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

/// 乘客端假後端：協尋寫入一律以 [failWith] 失敗，
/// 對帳查詢回 [freshItem]（或以 [byRideFailure] 失敗）。
class _CustomerLostItemApi extends CustomerApiClient {
  _CustomerLostItemApi()
      : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  ApiException failWith = ApiException('請求逾時，請稍後再試');
  LostItemRequest? freshItem;
  ApiException? byRideFailure;
  int byRideCalls = 0;

  @override
  void setToken(String? token) {}

  @override
  Future<CustomerRide?> activeRide() async => null;

  // 回**可變**空 list：controller 會把它當成清單狀態、之後 insert 進去。
  // 回 `const []` 的話會撞到 `Cannot add to an unmodifiable list`（見下方 group）。
  @override
  Future<List<LostItemRequest>> fetchLostItems() async => <LostItemRequest>[];

  @override
  Future<LostItemRequest> createLostItem(int rideId, String description) async =>
      throw failWith;

  @override
  Future<LostItemRequest> payLostItem(int itemId) async => throw failWith;

  @override
  Future<LostItemRequest> closeLostItem(int itemId) async => throw failWith;

  @override
  Future<LostItemRequest?> fetchLostItemByRide(int rideId) async {
    byRideCalls++;
    if (byRideFailure != null) throw byRideFailure!;
    return freshItem;
  }
}

/// 司機端假後端：同上。
class _DriverLostItemApi extends FleetApiClient {
  _DriverLostItemApi()
      : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  ApiException failWith = ApiException('請求逾時，請稍後再試');
  LostItemRequest? freshItem;
  int byRideCalls = 0;

  @override
  void setToken(String? token) {}

  @override
  Future<ActiveRide?> activeRide() async => null;

  @override
  Future<DriverVehicle> fetchVehicle() async => DriverVehicle.fromJson(const {
        'has_vehicle': true,
        'vehicle_type': 'sedan',
        'plate_number': 'ABC-1234',
        'review_status': 'approved',
        'can_accept': true,
      });

  @override
  Future<List<LostItemRequest>> fetchLostItems() async => <LostItemRequest>[];

  @override
  Future<LostItemRequest> markLostItemFound(int itemId) async => throw failWith;

  @override
  Future<LostItemRequest> markLostItemReturned(int itemId) async =>
      throw failWith;

  @override
  Future<LostItemRequest> closeLostItem(int itemId) async => throw failWith;

  @override
  Future<LostItemRequest?> fetchLostItemByRide(int rideId) async {
    byRideCalls++;
    return freshItem;
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
