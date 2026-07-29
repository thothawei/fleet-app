import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:line_fleet_app/core/api/fleet_api_client.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/push/fleet_push_service.dart';
import 'package:line_fleet_app/core/storage/token_storage.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/driver/driver_controller.dart';
import 'package:line_fleet_app/driver/screens/driver_earnings_screen.dart';

class _EarningsApi extends FleetApiClient {
  _EarningsApi(this.earnings, {this.rating, this.ratingError});

  final DriverEarnings earnings;

  /// null ＋ ratingError=null → 比照舊後端不帶 rating_* 鍵（解析成 0 則）。
  final DriverRatingSummary? rating;
  final Object? ratingError;
  String? lastMonth;

  @override
  Future<DriverEarnings> fetchEarnings({String? month}) async {
    lastMonth = month;
    return earnings;
  }

  @override
  Future<DriverRatingSummary> fetchMyRating() async {
    if (ratingError != null) throw ratingError!;
    return rating ?? const DriverRatingSummary(average: 0, count: 0);
  }
}

DriverController _controller(_EarningsApi api) => DriverController(
      storage: MemoryDriverAuthStore(),
      api: api,
      wsFactory: FleetWsClient.silent,
      push: NoOpFleetPushService(),
    );

const _earnings = DriverEarnings(
  month: '2026-07',
  tripCount: 3,
  totalRevenueCents: 27000,
  totalCommissionCents: 4000,
  driverNetCents: 23000,
  membershipFeeCents: 300000,
  owedToHqCents: 304000,
);

Future<void> _pumpEarnings(WidgetTester tester, DriverController ctrl) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<DriverController>.value(
      value: ctrl,
      child: const MaterialApp(home: DriverEarningsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('司機收入頁顯示營業額、實得與應付總公司', (tester) async {
    final api = _EarningsApi(const DriverEarnings(
      month: '2026-07',
      tripCount: 3,
      totalRevenueCents: 27000,
      totalCommissionCents: 4000,
      driverNetCents: 23000,
      membershipFeeCents: 300000,
      owedToHqCents: 304000,
    ));
    final ctrl = DriverController(
      storage: MemoryDriverAuthStore(),
      api: api,
      wsFactory: FleetWsClient.silent,
      push: NoOpFleetPushService(),
    );
    addTearDown(ctrl.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<DriverController>.value(
        value: ctrl,
        child: const MaterialApp(home: DriverEarningsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('3 趟'), findsOneWidget);
    expect(find.text('NT\$ 270'), findsOneWidget); // 營業額
    expect(find.text('NT\$ 230'), findsOneWidget); // 司機實得
    expect(find.text('NT\$ 3,000'), findsOneWidget); // 月會費
    expect(find.text('NT\$ 3,040'), findsOneWidget); // 應付總公司
    // 有帶當月參數查詢
    expect(api.lastMonth, isNotNull);
  });

  testWidgets('B5：有評分時顯示平均分與則數', (tester) async {
    final api = _EarningsApi(_earnings,
        rating: const DriverRatingSummary(average: 4.5, count: 12));
    final ctrl = _controller(api);
    addTearDown(ctrl.dispose);

    await _pumpEarnings(tester, ctrl);

    expect(find.text('服務評價'), findsOneWidget);
    expect(find.text('4.5 ／ 5.0（12 則）'), findsOneWidget);
  });

  testWidgets('B5：尚無評分時說「尚無評分」，不顯示 0.0 顆星', (tester) async {
    final api = _EarningsApi(_earnings);
    final ctrl = _controller(api);
    addTearDown(ctrl.dispose);

    await _pumpEarnings(tester, ctrl);

    expect(find.text('尚無評分'), findsOneWidget);
    expect(find.textContaining('0.0'), findsNothing);
  });

  testWidgets('B5：評價查詢失敗不擋收入頁——整塊不顯示，金額照常', (tester) async {
    final api = _EarningsApi(_earnings, ratingError: ApiException('後端掛了'));
    final ctrl = _controller(api);
    addTearDown(ctrl.dispose);

    await _pumpEarnings(tester, ctrl);

    expect(find.text('服務評價'), findsNothing);
    expect(find.text('後端掛了'), findsNothing, reason: '加值資訊的錯誤不該占版面');
    expect(find.text('NT\$ 230'), findsOneWidget, reason: '收入才是這頁的主體');
  });
}
