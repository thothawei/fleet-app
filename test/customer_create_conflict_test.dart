import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/customer_api_client.dart';
import 'package:line_fleet_app/core/api/fleet_api_client.dart' show ApiException;
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/storage/customer_token_storage.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/customer/customer_controller.dart';

/// 建單被 409「已有進行中的訂單」擋下時的出路。
///
/// 這句話是後端在明說「你已經有一張單」，而乘客的畫面上一張都沒有——
/// 成因多半是上一次建單逾時其實成立了（弱網），也可能訂單來自 LINE 或另一台裝置。
/// 只把訊息原樣顯示，乘客無事可做：再按一次還是 409，唯一出路是重開 App。
void main() {
  group('建單 409：把死路變成接手既有訂單', () {
    test('後端真的有一張進行中訂單 → 直接接手，錯誤訊息清掉', () async {
      final api = _ConflictApi()
        ..active = CustomerRide.fromJson(const {
          'id': 31,
          'status': RideStatus.requested,
          'pickup_address': '台北車站',
        });
      final ctrl = await _customer(api);
      addTearDown(ctrl.dispose);

      await ctrl.handleCreateFailure(
        ApiException('已有進行中的訂單', statusCode: 409),
      );

      expect(ctrl.activeRide?.rideId, 31,
          reason: '後端說有單、App 說沒有——以後端為準才走得下去');
      expect(ctrl.error, isNull);
    });

    test('接手時清掉編輯中的多乘客清單與預估（別把上一趟的殘骸帶進這一趟）', () async {
      final api = _ConflictApi()
        ..active = CustomerRide.fromJson(const {
          'id': 32,
          'status': RideStatus.requested,
          'pickup_address': '台北車站',
        });
      final ctrl = await _customer(api);
      addTearDown(ctrl.dispose);
      ctrl.enableMultiStop();
      ctrl.addPassenger();
      expect(ctrl.passengers, isNotEmpty, reason: '前置：叫車表單正編到一半');

      await ctrl.handleCreateFailure(
        ApiException('已有進行中的訂單', statusCode: 409),
      );

      expect(ctrl.passengers, isEmpty,
          reason: '這趟已經成立，編輯狀態留著會出現在下一次叫車表單上');
      expect(ctrl.fareEstimate, isNull);
    });

    test('後端說沒有進行中訂單 → 維持 409 訊息，不編故事', () async {
      final api = _ConflictApi()..active = null;
      final ctrl = await _customer(api);
      addTearDown(ctrl.dispose);

      await ctrl.handleCreateFailure(
        ApiException('已有進行中的訂單', statusCode: 409),
      );

      expect(ctrl.activeRide, isNull);
      expect(ctrl.error, '已有進行中的訂單');
    });

    test('接手時連司機資訊一起帶出來（不必等下一輪輪詢）', () async {
      // 建單失敗到接手之間可能已經被司機接走了。少了這一步，乘客會先看到一段
      // 「配對中」的假象，直到 15 秒後的輪詢才冒出司機——而司機可能已經在門口。
      // 司機欄在後端是**扁平鍵**（與 WS payload 同一組），不是巢狀物件。
      final api = _ConflictApi()
        ..active = CustomerRide.fromJson(const {
          'id': 33,
          'status': RideStatus.accepted,
          'pickup_address': '台北車站',
          'driver_name': '阿明',
          'driver_phone': '0912345678',
          'driver_vehicle_type': 'sedan',
          'driver_plate_number': 'ABC-1234',
        });
      final ctrl = await _customer(api);
      addTearDown(ctrl.dispose);

      await ctrl.handleCreateFailure(
        ApiException('已有進行中的訂單', statusCode: 409),
      );

      expect(ctrl.activeRide?.rideId, 33);
      expect(ctrl.driverName, '阿明');
      expect(ctrl.driverInfo?.plateNumber, 'ABC-1234',
          reason: '路邊要對車牌，這是這張卡存在的理由');
      expect(ctrl.driverInfo?.phone, '0912345678');
    });

    test('對帳本身也失敗（網路仍不通）→ 維持原本的錯誤，不編故事', () async {
      final api = _ConflictApi()
        ..activeError = ApiException('無法連線到伺服器，請檢查網路');
      final ctrl = await _customer(api);
      addTearDown(ctrl.dispose);

      await ctrl.handleCreateFailure(
        ApiException('已有進行中的訂單', statusCode: 409),
      );

      expect(ctrl.activeRide, isNull);
      expect(ctrl.error, '已有進行中的訂單', reason: '問不到就維持原訊息，不可假裝接手成功');
    });

    test('後端回的是終態訂單 → 不算數（剛結束的上一趟不能變成這一趟）', () async {
      final api = _ConflictApi()
        ..active = CustomerRide.fromJson(const {
          'id': 34,
          'status': RideStatus.completed,
          'pickup_address': '上一趟',
        });
      final ctrl = await _customer(api);
      addTearDown(ctrl.dispose);

      await ctrl.handleCreateFailure(
        ApiException('已有進行中的訂單', statusCode: 409),
      );

      expect(ctrl.activeRide, isNull,
          reason: '把已完成的上一趟接手過來，乘客會盯著一張永遠不會動的行程');
      expect(ctrl.error, '已有進行中的訂單');
    });

    test('其他有狀態碼的拒絕（如 429 限流）仍不對帳', () async {
      final api = _ConflictApi()
        ..active = CustomerRide.fromJson(const {
          'id': 99,
          'status': RideStatus.requested,
          'pickup_address': '別人的訂單',
        });
      final ctrl = await _customer(api);
      addTearDown(ctrl.dispose);

      await ctrl.handleCreateFailure(
        ApiException('叫車太頻繁，請稍後再試', statusCode: 429),
      );

      expect(ctrl.activeRide, isNull, reason: '被限流擋下的這次根本沒建單');
      expect(ctrl.error, '叫車太頻繁，請稍後再試');
    });
  });
}

Future<CustomerController> _customer(_ConflictApi api) async {
  final ctrl = CustomerController(
    storage: _MemoryCustomerStorage()
      ..save(const CustomerSession(customerId: 3, token: 'tok')),
    api: api,
    wsFactory: FleetWsClient.silent,
  );
  await ctrl.init();
  return ctrl;
}

class _ConflictApi extends CustomerApiClient {
  // 預約／常用地點：controller.init() 會載這兩份。沒覆寫的話會走真實 Dio 打網路，
  // 在測試裡變成不確定的非同步延遲，把不相干的測試拖成 flaky（實測會讓
  // customer_location_exits 的預估 notifyListeners 落在 dispose 之後）。
  @override
  Future<List<SavedPlace>> fetchSavedPlaces() async => const [];

  @override
  Future<ScheduledRidesResult> fetchScheduledRides({bool upcomingOnly = false}) async =>
      const ScheduledRidesResult(rides: [], leadMinutes: 15);

  _ConflictApi()
      : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  CustomerRide? active;
  ApiException? activeError;
  int _calls = 0;
  int adoptCalls = 0;

  @override
  void setToken(String? token) {}

  @override
  // init() 的還原一律回 null——乘客按下叫車時畫面上沒有任何訂單，
  // 這正是 409「已有進行中的訂單」讓人無路可走的前提。
  Future<CustomerRide?> activeRide() async {
    final first = _calls++ == 0;
    if (first) return null;
    adoptCalls++;
    if (activeError != null) throw activeError!;
    return active;
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
