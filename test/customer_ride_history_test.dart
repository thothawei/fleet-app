import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/customer_api_client.dart';
import 'package:line_fleet_app/core/api/fleet_api_client.dart' show ApiException;
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/customer/customer_controller.dart';
import 'package:line_fleet_app/customer/screens/ride_history_screen.dart';
import 'package:provider/provider.dart';

class _FakeApi extends CustomerApiClient {
  _FakeApi() : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  List<CustomerRideSummary> history = const [];
  ApiException? historyError;
  int fetchCount = 0;

  @override
  Future<List<CustomerRideSummary>> fetchRideHistory({int limit = 20}) async {
    fetchCount++;
    if (historyError != null) throw historyError!;
    return history;
  }
}

CustomerController _loggedIn(_FakeApi api) {
  final ctrl = CustomerController(api: api);
  ctrl.setSessionForTest(
    const CustomerSession(customerId: 1, token: 'tok', name: '小美'),
  );
  return ctrl;
}

void main() {
  group('CustomerRideSummary 解析', () {
    test('有司機 → hasDriver；車資/時間/狀態解析', () {
      final s = CustomerRideSummary.fromJson(const {
        'id': 42,
        'status': 4,
        'pickup_address': '台北101',
        'dropoff_address': '台北車站',
        'requested_at': '2026-07-18T10:00:00Z',
        'completed_at': '2026-07-18T10:30:00Z',
        'fare_amount_cents': 21500,
        'driver_id': 7,
        'driver_name': '阿明',
      });
      expect(s.hasDriver, isTrue);
      expect(s.driverName, '阿明');
      expect(s.fareAmountCents, 21500);
      expect(s.statusLabel, '已完成');
      expect(s.completedAt, isNotNull);
    });

    test('無司機（派單前取消）→ hasDriver=false、缺鍵容忍', () {
      final s = CustomerRideSummary.fromJson(const {
        'id': 43,
        'status': 9,
        'pickup_address': '某處',
      });
      expect(s.hasDriver, isFalse);
      expect(s.driverName, isNull);
      expect(s.dropoffAddress, isNull);
      expect(s.fareAmountCents, isNull);
      expect(s.statusLabel, '已取消');
    });
  });

  group('loadRideHistory', () {
    test('成功載入填入 rideHistory', () async {
      final api = _FakeApi()
        ..history = const [
          CustomerRideSummary(rideId: 2, status: 4, pickupAddress: 'B'),
          CustomerRideSummary(rideId: 1, status: 9, pickupAddress: 'A'),
        ];
      final ctrl = _loggedIn(api);
      addTearDown(ctrl.dispose);

      await ctrl.loadRideHistory();
      expect(ctrl.rideHistory.length, 2);
      expect(ctrl.historyError, isNull);
      expect(ctrl.historyLoading, isFalse);
    });

    test('失敗設 historyError、不丟例外', () async {
      final api = _FakeApi()..historyError = ApiException('壞了');
      final ctrl = _loggedIn(api);
      addTearDown(ctrl.dispose);

      await ctrl.loadRideHistory();
      expect(ctrl.historyError, '壞了');
      expect(ctrl.rideHistory, isEmpty);
      expect(ctrl.historyLoading, isFalse);
    });
  });

  group('歷史畫面', () {
    Future<void> pump(WidgetTester tester, CustomerController ctrl) {
      return tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: ctrl,
          child: const MaterialApp(home: CustomerRideHistoryScreen()),
        ),
      );
    }

    testWidgets('有司機的行程顯示「聯絡司機」，無司機的不顯示', (tester) async {
      final api = _FakeApi()
        ..history = const [
          CustomerRideSummary(
            rideId: 2, status: 4, pickupAddress: '台北101',
            dropoffAddress: '台北車站', driverId: 7, driverName: '阿明',
          ),
          CustomerRideSummary(rideId: 1, status: 9, pickupAddress: '某處'),
        ];
      final ctrl = _loggedIn(api);
      addTearDown(ctrl.dispose);

      await pump(tester, ctrl);
      await tester.pumpAndSettle();

      expect(find.text('行程 #2'), findsOneWidget);
      expect(find.text('行程 #1'), findsOneWidget);
      // 兩筆行程、只有有司機那筆給「聯絡司機」。
      expect(find.text('聯絡司機'), findsOneWidget);
      expect(find.textContaining('阿明'), findsOneWidget);
    });

    testWidgets('空清單顯示提示', (tester) async {
      final ctrl = _loggedIn(_FakeApi()..history = const []);
      addTearDown(ctrl.dispose);
      await pump(tester, ctrl);
      await tester.pumpAndSettle();
      expect(find.text('還沒有行程紀錄'), findsOneWidget);
    });
  });
}
