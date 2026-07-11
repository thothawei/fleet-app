import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:line_fleet_app/core/api/fleet_api_client.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/push/driver_push_service.dart';
import 'package:line_fleet_app/core/storage/token_storage.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/driver/driver_controller.dart';
import 'package:line_fleet_app/driver/screens/driver_earnings_screen.dart';

class _EarningsApi extends FleetApiClient {
  _EarningsApi(this.earnings);

  final DriverEarnings earnings;
  String? lastMonth;

  @override
  Future<DriverEarnings> fetchEarnings({String? month}) async {
    lastMonth = month;
    return earnings;
  }
}

void main() {
  testWidgets('司機收入頁顯示營業額、實得與應付總公司', (tester) async {
    final api = _EarningsApi(const DriverEarnings(
      month: '2026-07',
      tripCount: 3,
      totalRevenueCents: 27000,
      totalCommissionCents: 4050,
      driverNetCents: 22950,
      membershipFeeCents: 300000,
      owedToHqCents: 304050,
    ));
    final ctrl = DriverController(
      storage: MemoryDriverAuthStore(),
      api: api,
      wsFactory: FleetWsClient.silent,
      push: NoOpDriverPushService(),
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
    expect(find.text('NT\$ 270.00'), findsOneWidget); // 營業額
    expect(find.text('NT\$ 229.50'), findsOneWidget); // 司機實得
    expect(find.text('NT\$ 3,000.00'), findsOneWidget); // 月會費
    expect(find.text('NT\$ 3,040.50'), findsOneWidget); // 應付總公司
    // 有帶當月參數查詢
    expect(api.lastMonth, isNotNull);
  });
}
