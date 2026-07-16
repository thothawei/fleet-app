import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/customer_api_client.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/storage/customer_token_storage.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/customer/customer_controller.dart';

void main() {
  group('登入後自動帶出進行中協尋', () {
    late CustomerController ctrl;
    late _FakeCustomerApi api;

    setUp(() {
      api = _FakeCustomerApi();
      ctrl = CustomerController(
        storage: _MemoryCustomerStorage(),
        api: api,
        wsFactory: FleetWsClient.silent,
      );
    });

    tearDown(() => ctrl.dispose());

    test('login 成功→立即拉未結案協尋單，首頁 banner 不用等下拉刷新', () async {
      await ctrl.init();
      expect(ctrl.lostItems, isEmpty);

      await ctrl.login(lineUserId: 'U_customer', password: 'pw');

      expect(ctrl.isLoggedIn, isTrue);
      expect(ctrl.lostItems, hasLength(1));
      expect(ctrl.lostItems.single.status, 'open');
    });
  });
}

/// 記憶體版 storage：避免單元測試打到 FlutterSecureStorage 平台通道。
class _MemoryCustomerStorage extends CustomerTokenStorage {
  CustomerSession? _saved;

  @override
  Future<CustomerSession?> read() async => _saved;

  @override
  Future<void> save(CustomerSession session) async => _saved = session;

  @override
  Future<void> clear() async => _saved = null;
}

class _FakeCustomerApi extends CustomerApiClient {
  _FakeCustomerApi()
      : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  @override
  void setToken(String? token) {}

  @override
  Future<CustomerLoginResult> login({
    required String lineUserId,
    required String password,
  }) async =>
      const CustomerLoginResult(customerId: 1, token: 'tok-1', name: '小美');

  @override
  Future<CustomerRide?> activeRide() async => null;

  @override
  Future<List<LostItemRequest>> fetchLostItems() async => [
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
}
