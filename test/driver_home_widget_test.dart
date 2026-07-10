import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/fleet_api_client.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/push/driver_push_service.dart';
import 'package:line_fleet_app/core/storage/token_storage.dart';
import 'package:line_fleet_app/core/theme/app_theme.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/driver/driver_controller.dart';
import 'package:line_fleet_app/driver/screens/driver_home_screen.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('離線時 hero 顯示「離線」且診斷資訊預設收合', (tester) async {
    final storage = MemoryDriverAuthStore();
    final api = _FakeFleetApi();
    final push = _FakePush();
    final ctrl = DriverController(
      storage: storage,
      api: api,
      wsFactory: FleetWsClient.silent,
      push: push,
    );
    addTearDown(ctrl.dispose);

    await ctrl.init();
    await ctrl.login(lineUserId: 'U_driver', password: 'pw');

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: ctrl,
        child: MaterialApp(
          theme: appLightTheme,
          darkTheme: appDarkTheme,
          home: const DriverHomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('離線'), findsOneWidget);
    expect(find.text('目前不會收到派單'), findsOneWidget);
    // 收合狀態下不直接顯示 API base
    expect(find.textContaining('http'), findsNothing);
    // 展開「連線狀態」後才看得到
    await tester.tap(find.text('連線狀態'));
    await tester.pumpAndSettle();
    expect(find.textContaining('http'), findsOneWidget);
  });
}

class _FakeFleetApi extends FleetApiClient {
  _FakeFleetApi()
      : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  @override
  void setToken(String? token) {}

  @override
  Future<LoginResult> login({
    required String lineUserId,
    required String password,
  }) async {
    return const LoginResult(driverId: 7, token: 'tok-7', name: '阿明');
  }

  @override
  Future<ActiveRide?> activeRide() async => null;

  @override
  Future<void> registerDeviceToken({
    required String platform,
    required String token,
  }) async {}

  @override
  Future<void> unregisterDeviceToken({required String token}) async {}
}

class _FakePush implements DriverPushService {
  final _controller = StreamController<FleetWsEvent>.broadcast();
  final _tokenRefresh = StreamController<String>.broadcast();

  @override
  Future<bool> initialize() async => true;

  @override
  bool get isAvailable => true;

  @override
  Future<String?> getToken() async => 'fcm-tok-abc';

  @override
  Stream<FleetWsEvent> get rideEvents => _controller.stream;

  @override
  Stream<String> get tokenRefresh => _tokenRefresh.stream;

  @override
  Future<void> dispose() async {
    await _tokenRefresh.close();
    await _controller.close();
  }
}
