import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/customer_api_client.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/storage/customer_token_storage.dart';
import 'package:line_fleet_app/core/theme/app_theme.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/customer/customer_controller.dart';
import 'package:line_fleet_app/customer/screens/ride_history_screen.dart';
import 'package:provider/provider.dart';

/// 「我的行程」是完成卡關掉後**唯一**能申請遺失物協尋的地方。
///
/// `_completedSummary` 只由 WS `ride.completed` 設定、**沒有任何 REST 還原路徑**：
/// 按下「再叫一輛」、重開 App，或行程完成當下 App 剛好在背景／WS 斷線，
/// 完成卡上那顆「物品遺失？聯絡司機」就永遠不會再出現。
/// 而東西通常是**下車以後**才發現不見的——首頁的協尋 banner 又只顯示**已存在**的單子，
/// 進不了申請表單。
void main() {
  group('歷史清單的遺失物協尋入口', () {
    testWidgets('已完成且有司機的行程 → 給「物品遺失」入口', (tester) async {
      final ctrl = await _historyWith([_summary(rideId: 42)]);
      addTearDown(ctrl.dispose);
      await _pump(tester, ctrl);

      expect(find.widgetWithText(OutlinedButton, '物品遺失'), findsOneWidget);
    });

    testWidgets('未完成的行程沒有入口（後端也會回 409）', (tester) async {
      final ctrl = await _historyWith([
        _summary(rideId: 43, status: RideStatus.cancelled),
      ]);
      addTearDown(ctrl.dispose);
      await _pump(tester, ctrl);

      expect(find.widgetWithText(OutlinedButton, '物品遺失'), findsNothing);
    });

    testWidgets('派單前取消（無司機）沒有入口——東西不會留在誰的車上', (tester) async {
      final ctrl = await _historyWith([
        _summary(rideId: 44, status: RideStatus.completed, driverId: null),
      ]);
      addTearDown(ctrl.dispose);
      await _pump(tester, ctrl);

      expect(find.widgetWithText(OutlinedButton, '物品遺失'), findsNothing);
    });

    test('canReportLostItem 與後端 CreateByCustomer 同一組條件', () {
      expect(_summary(rideId: 1).canReportLostItem, isTrue);
      expect(
        _summary(rideId: 2, status: RideStatus.completed, driverId: null)
            .canReportLostItem,
        isFalse,
        reason: '沒有司機就沒有協尋的對象',
      );
      expect(
        _summary(rideId: 3, status: RideStatus.accepted).canReportLostItem,
        isFalse,
        reason: '行程還沒結束就報遺失，後端會回 409',
      );
    });
  });
}

Future<void> _pump(WidgetTester tester, CustomerController ctrl) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: appLightTheme,
      home: ChangeNotifierProvider<CustomerController>.value(
        value: ctrl,
        child: const CustomerRideHistoryScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<CustomerController> _historyWith(
  List<CustomerRideSummary> rides,
) async {
  final api = _FakeApi()..history = rides;
  final ctrl = CustomerController(
    storage: _MemoryStorage()
      ..save(const CustomerSession(customerId: 3, token: 'tok')),
    api: api,
    wsFactory: FleetWsClient.silent,
  );
  await ctrl.init();
  return ctrl;
}

CustomerRideSummary _summary({
  required int rideId,
  int status = RideStatus.completed,
  int? driverId = 7,
}) =>
    CustomerRideSummary(
      rideId: rideId,
      status: status,
      pickupAddress: '台北101',
      dropoffAddress: '台北車站',
      requestedAt: DateTime(2026, 7, 29, 10),
      fareAmountCents: 8500,
      driverId: driverId,
      driverName: driverId == null ? null : '阿明',
    );

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

  List<CustomerRideSummary> history = const [];

  @override
  void setToken(String? token) {}

  @override
  Future<CustomerRide?> activeRide() async => null;

  @override
  Future<List<LostItemRequest>> fetchLostItems() async => const [];

  @override
  Future<List<CustomerRideSummary>> fetchRideHistory({int limit = 20}) async =>
      history;
}

class _MemoryStorage extends CustomerTokenStorage {
  CustomerSession? _saved;

  @override
  Future<CustomerSession?> read() async => _saved;

  @override
  Future<void> save(CustomerSession session) async => _saved = session;

  @override
  Future<void> clear() async => _saved = null;
}
