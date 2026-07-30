import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/customer_api_client.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/customer/customer_controller.dart';
import 'package:line_fleet_app/customer/screens/customer_map_home_screen.dart';
import 'package:provider/provider.dart';

/// production 首頁上的入口。
///
/// **這支守的是一個真的踩過的坑**：預約司機的入口與「即將到來」卡原本加在
/// `CustomerHomeScreen`（卡片版），而 `app.dart` 掛的是 `CustomerMapHomeScreen`
/// （地圖版）——功能寫完、測試全綠、畫面上根本沒有那顆按鈕。
/// 兩個同類畫面並存時，「我改的那個」跟「使用者看到的那個」要分別確認。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('地圖版首頁要有「預約司機」入口', (tester) async {
    final ctrl = CustomerController(api: _StubApi());
    ctrl.setSessionForTest(
      const CustomerSession(customerId: 1, token: 'tok', name: '小美'),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<CustomerController>.value(
        value: ctrl,
        child: const MaterialApp(home: CustomerMapHomeScreen()),
      ),
    );
    await tester.pump();

    expect(
      find.byTooltip('預約司機'),
      findsOneWidget,
      reason: '入口不在 production 首頁上＝功能無法從 UI 到達',
    );
  });
}

class _StubApi extends CustomerApiClient {
  _StubApi() : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  @override
  void setToken(String? token) {}

  @override
  Future<CustomerRide?> activeRide() async => null;

  @override
  Future<List<LostItemRequest>> fetchLostItems() async => <LostItemRequest>[];

  @override
  Future<List<SavedPlace>> fetchSavedPlaces() async => const [];

  @override
  Future<ScheduledRidesResult> fetchScheduledRides({
    bool upcomingOnly = false,
  }) async =>
      const ScheduledRidesResult(rides: [], leadMinutes: 15);
}
