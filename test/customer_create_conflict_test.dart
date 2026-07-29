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
  _ConflictApi()
      : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  CustomerRide? active;
  int _calls = 0;

  @override
  void setToken(String? token) {}

  @override
  // init() 的還原一律回 null——乘客按下叫車時畫面上沒有任何訂單，
  // 這正是 409「已有進行中的訂單」讓人無路可走的前提。
  Future<CustomerRide?> activeRide() async => _calls++ == 0 ? null : active;

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
