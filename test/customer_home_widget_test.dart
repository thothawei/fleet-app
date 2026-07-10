import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/customer_api_client.dart';
import 'package:line_fleet_app/core/config/app_config.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/theme/app_theme.dart';
import 'package:line_fleet_app/customer/customer_controller.dart';
import 'package:line_fleet_app/customer/screens/customer_home_screen.dart';
import 'package:line_fleet_app/customer/screens/customer_map_home_screen.dart';
import 'package:provider/provider.dart';

enum TestPhase { idle, searching, completed }

void main() {
  late CustomerController ctrl;

  setUp(() {
    ctrl = CustomerController(api: _FakeCustomerApi());
    ctrl.setSessionForTest(
      const CustomerSession(customerId: 1, token: 'tok', name: '測試乘客'),
    );
  });

  tearDown(() => ctrl.dispose());

  Widget buildCustomerTestApp({required TestPhase phase}) {
    switch (phase) {
      case TestPhase.searching:
        ctrl.setActiveRideForTest(
          const CustomerRide(rideId: 7, status: RideStatus.requested),
        );
        break;
      case TestPhase.completed:
        ctrl.markCompletedForTest(
          rideId: 42,
          dropoffAddress: '松山機場',
          driverName: '阿明',
        );
        break;
      case TestPhase.idle:
        break;
    }

    return ChangeNotifierProvider.value(
      value: ctrl,
      child: MaterialApp(
        theme: appLightTheme,
        home: AppConfig.mapsConfigured
            ? const CustomerMapHomeScreen()
            : const CustomerHomeScreen(),
      ),
    );
  }

  testWidgets('配對中顯示搜尋動畫與取消，且沒有「更新狀態」按鈕', (tester) async {
    await tester.pumpWidget(buildCustomerTestApp(phase: TestPhase.searching));
    await tester.pump();

    expect(find.text('正在為您配對司機'), findsOneWidget);
    expect(find.text('取消叫車'), findsOneWidget);
    expect(find.text('更新狀態'), findsNothing);
  });

  testWidgets('完成態顯示評分佔位與再叫一輛', (tester) async {
    await tester.pumpWidget(buildCustomerTestApp(phase: TestPhase.completed));
    await tester.pumpAndSettle();

    expect(find.text('行程已完成'), findsOneWidget);
    expect(find.text('再叫一輛'), findsOneWidget);
  });

  testWidgets('未設 Maps key 時走卡片版（有 AppBar）', (tester) async {
    await tester.pumpWidget(buildCustomerTestApp(phase: TestPhase.idle));
    await tester.pumpAndSettle();

    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('叫車'), findsWidgets);
  });
}

class _FakeCustomerApi extends CustomerApiClient {
  _FakeCustomerApi()
      : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  @override
  void setToken(String? token) {}

  @override
  Future<CustomerRide?> activeRide() async => null;
}
