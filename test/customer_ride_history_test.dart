import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/customer_api_client.dart';
import 'package:line_fleet_app/core/api/fleet_api_client.dart' show ApiException;
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/storage/customer_token_storage.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/customer/customer_controller.dart';
import 'package:line_fleet_app/customer/screens/ride_history_screen.dart';
import 'package:provider/provider.dart';

class _FakeApi extends CustomerApiClient {
  _FakeApi() : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  List<CustomerRideSummary> history = const [];
  ApiException? historyError;
  int fetchCount = 0;
  /// 每一次請求要的筆數（驗「視窗有沒有推進」用）。
  final List<int> requestedLimits = [];
  /// 非 null 時請求會卡在這裡，讓測試造出「請求還在飛」的狀態。
  Completer<void>? gate;

  @override
  Future<List<CustomerRideSummary>> fetchRideHistory({int limit = 20}) async {
    fetchCount++;
    requestedLimits.add(limit);
    if (gate != null) await gate!.future;
    if (historyError != null) throw historyError!;
    // 後端行為：新到舊排序後回前 limit 筆。
    return history.take(limit).toList();
  }
}

/// 造 n 筆歷史行程（#n 最新排最前，全部有司機以便驗「聯絡司機」入口）。
List<CustomerRideSummary> _rides(int n) => [
      for (var i = n; i >= 1; i--)
        CustomerRideSummary(
          rideId: i,
          status: 4,
          pickupAddress: '上車點 $i',
          driverId: 7,
          driverName: '阿明',
        ),
    ];

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

  // 「我的行程」是事後聯絡司機／申報遺失物／補評分的唯一入口。
  // 沒有這一組，第 21 趟以前的行程在乘客端永遠打不開。
  group('歷史行程分頁', () {
    test('回滿一頁 → 還有更多；不滿一頁 → 沒有了', () async {
      final api = _FakeApi()..history = _rides(25);
      final ctrl = _loggedIn(api);
      addTearDown(ctrl.dispose);

      await ctrl.loadRideHistory();
      expect(api.requestedLimits, [20]);
      expect(ctrl.rideHistory, hasLength(20));
      expect(ctrl.historyHasMore, isTrue);

      final api2 = _FakeApi()..history = _rides(12);
      final ctrl2 = _loggedIn(api2);
      addTearDown(ctrl2.dispose);
      await ctrl2.loadRideHistory();
      expect(ctrl2.historyHasMore, isFalse);
    });

    test('載入更多把視窗推到 40，第 21 筆之後的行程進得來', () async {
      final api = _FakeApi()..history = _rides(25);
      final ctrl = _loggedIn(api);
      addTearDown(ctrl.dispose);

      await ctrl.loadRideHistory();
      expect(ctrl.rideHistory.map((r) => r.rideId), isNot(contains(5)));

      await ctrl.loadMoreRideHistory();
      expect(api.requestedLimits, [20, 40]);
      expect(ctrl.rideHistory, hasLength(25));
      expect(ctrl.rideHistory.map((r) => r.rideId), contains(5));
      // 25 < 40：後面沒有了。
      expect(ctrl.historyHasMore, isFalse);
      expect(ctrl.historyMoreError, isNull);
    });

    test('沒有更多時不再打後端', () async {
      final api = _FakeApi()..history = _rides(3);
      final ctrl = _loggedIn(api);
      addTearDown(ctrl.dispose);

      await ctrl.loadRideHistory();
      await ctrl.loadMoreRideHistory();
      expect(api.fetchCount, 1);
    });

    test('載入更多失敗：清單原樣留著、錯誤不污染整頁、視窗不推進', () async {
      final api = _FakeApi()..history = _rides(25);
      final ctrl = _loggedIn(api);
      addTearDown(ctrl.dispose);

      await ctrl.loadRideHistory();
      api.historyError = ApiException('無法連線到伺服器，請檢查網路');
      await ctrl.loadMoreRideHistory();

      expect(ctrl.historyMoreError, '無法連線到伺服器，請檢查網路');
      expect(ctrl.historyError, isNull, reason: '整頁不能變成錯誤畫面');
      expect(ctrl.rideHistory, hasLength(20), reason: '已載入的行程不能消失');
      expect(ctrl.historyHasMore, isTrue, reason: '還要留著重試的入口');

      // 重試：要的仍是同一段 40，不是被失敗那次推到 60。
      api.historyError = null;
      await ctrl.loadMoreRideHistory();
      expect(api.requestedLimits, [20, 40, 40]);
      expect(ctrl.rideHistory, hasLength(25));
      expect(ctrl.historyMoreError, isNull);
    });

    test('請求還在飛時重複觸發只會發一次（捲動會連續呼叫）', () async {
      final api = _FakeApi()
        ..history = _rides(60)
        ..gate = Completer<void>();
      final ctrl = _loggedIn(api);
      addTearDown(ctrl.dispose);

      final first = ctrl.loadRideHistory();
      api.gate!.complete();
      await first;
      expect(api.fetchCount, 1);

      api.gate = Completer<void>();
      final a = ctrl.loadMoreRideHistory();
      final b = ctrl.loadMoreRideHistory();
      final c = ctrl.loadMoreRideHistory();
      api.gate!.complete();
      await Future.wait([a, b, c]);

      expect(api.fetchCount, 2);
      expect(api.requestedLimits, [20, 40]);
    });

    test('下拉刷新保持已展開的筆數，不會縮回第一頁', () async {
      final api = _FakeApi()..history = _rides(60);
      final ctrl = _loggedIn(api);
      addTearDown(ctrl.dispose);

      await ctrl.loadRideHistory();
      await ctrl.loadMoreRideHistory();
      expect(ctrl.rideHistory, hasLength(40));

      await ctrl.loadRideHistory(); // 下拉刷新
      expect(api.requestedLimits, [20, 40, 40]);
      expect(ctrl.rideHistory, hasLength(40));
    });

    test('登出把視窗收回一頁（換人登入不該替他要 60 筆）', () async {
      final api = _FakeApi()..history = _rides(60);
      final ctrl = CustomerController(
        storage: _MemoryCustomerStorage(),
        api: api,
        wsFactory: FleetWsClient.silent,
      );
      addTearDown(ctrl.dispose);
      ctrl.setSessionForTest(
        const CustomerSession(customerId: 1, token: 'tok', name: '小美'),
      );

      await ctrl.loadRideHistory();
      await ctrl.loadMoreRideHistory();
      await ctrl.logout();
      expect(ctrl.rideHistory, isEmpty);
      expect(ctrl.historyHasMore, isFalse);

      ctrl.setSessionForTest(
        const CustomerSession(customerId: 2, token: 'tok2', name: '阿華'),
      );
      await ctrl.loadRideHistory();
      expect(api.requestedLimits.last, 20);
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

    testWidgets('捲到底自動補上更舊的行程（第 21 筆之後）', (tester) async {
      final api = _FakeApi()..history = _rides(25);
      final ctrl = _loggedIn(api);
      addTearDown(ctrl.dispose);

      await pump(tester, ctrl);
      await tester.pumpAndSettle();
      expect(find.text('行程 #5'), findsNothing);

      await tester.scrollUntilVisible(
        find.text('行程 #5'),
        400,
        maxScrolls: 60,
      );
      await tester.pumpAndSettle();

      expect(find.text('行程 #5'), findsOneWidget);
      expect(api.requestedLimits, [20, 40]);
    });

    testWidgets('載入更多失敗時清單還在，尾巴給重試', (tester) async {
      final api = _FakeApi()..history = _rides(25);
      final ctrl = _loggedIn(api);
      addTearDown(ctrl.dispose);

      await pump(tester, ctrl);
      await tester.pumpAndSettle();
      api.historyError = ApiException('無法連線到伺服器，請檢查網路');

      await tester.scrollUntilVisible(
        find.text('無法連線到伺服器，請檢查網路'),
        400,
        maxScrolls: 60,
      );
      await tester.pumpAndSettle();

      expect(find.text('行程 #25'), findsNothing, reason: '已捲到底，最新那筆在畫面外');
      expect(find.text('載入更多'), findsOneWidget);

      api.historyError = null;
      await tester.tap(find.text('載入更多'));
      await tester.pumpAndSettle();
      expect(find.text('行程 #5'), findsOneWidget);
    });
  });
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
