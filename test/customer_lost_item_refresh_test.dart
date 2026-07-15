import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/customer_api_client.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/customer/customer_controller.dart';

void main() {
  group('協尋詳情頁新鮮抓取與清單一致', () {
    late _StaleListApi api;
    late CustomerController ctrl;

    setUp(() {
      api = _StaleListApi();
      ctrl = CustomerController(api: api);
      ctrl.setSessionForTest(
        const CustomerSession(customerId: 1, token: 'tok', name: '小美'),
      );
    });

    tearDown(() => ctrl.dispose());

    test('fetchLostItemByRide 抓到較新狀態時，會把過期清單合併為最新', () async {
      // 清單先有過期的 open（模擬漏收 WS lost_item.updated）
      await ctrl.refreshLostItems();
      expect(ctrl.lostItems.single.status, 'open');

      // 詳情頁進場抓到最新的 found
      final item = await ctrl.fetchLostItemByRide(5);
      expect(item?.status, 'found');

      // 清單應被合併為 found —— 詳情頁 build 以 lostItems 為準，不會再顯示過期 open
      expect(ctrl.lostItems.single.status, 'found',
          reason: '新鮮抓取應成為清單權威來源，避免過期清單蓋掉本頁狀態');
    });

    test('抓到已結案（returned）時，從未結案清單移除', () async {
      await ctrl.refreshLostItems();
      expect(ctrl.lostItems, hasLength(1));

      api.byRideStatus = 'returned';
      final item = await ctrl.fetchLostItemByRide(5);
      expect(item?.status, 'returned');
      expect(ctrl.lostItems, isEmpty, reason: '已結案協尋單應移出未結案清單');
    });
  });
}

class _StaleListApi extends CustomerApiClient {
  _StaleListApi()
      : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  /// fetchLostItemByRide 回傳的狀態（比清單新）。
  String byRideStatus = 'found';

  LostItemRequest _item(String status) => LostItemRequest.fromJson({
        'id': 3,
        'ride_id': 5,
        'customer_id': 1,
        'driver_id': 7,
        'description': '黑色錢包',
        'fee_cents': 1000,
        'fee_bps': 1000,
        'status': status,
        'created_at': '2026-07-15T10:00:00Z',
      });

  // 清單維持過期的 open
  @override
  Future<List<LostItemRequest>> fetchLostItems() async => [_item('open')];

  @override
  Future<LostItemRequest?> fetchLostItemByRide(int rideId) async =>
      _item(byRideStatus);
}
