import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/fleet_api_client.dart';
import 'package:line_fleet_app/core/config/app_config.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/push/driver_push_service.dart';
import 'package:line_fleet_app/core/storage/token_storage.dart';
import 'package:line_fleet_app/core/theme/app_theme.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/driver/driver_controller.dart';
import 'package:line_fleet_app/driver/screens/driver_home_screen.dart';
import 'package:provider/provider.dart';

void main() {
  late MemoryDriverAuthStore storage;
  late _FakeFleetApi api;
  late _FakePush push;
  late DriverController ctrl;

  setUp(() {
    storage = MemoryDriverAuthStore();
    api = _FakeFleetApi();
    push = _FakePush();
    ctrl = DriverController(
      storage: storage,
      api: api,
      wsFactory: FleetWsClient.silent,
      push: push,
    );
  });

  tearDown(() => ctrl.dispose());

  Future<void> pumpHome(WidgetTester tester) async {
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
  }

  testWidgets('離線時 hero 顯示「離線」且診斷資訊預設收合', (tester) async {
    await ctrl.init();
    await ctrl.login(lineUserId: 'U_driver', password: 'pw');
    await pumpHome(tester);

    expect(find.text('離線'), findsOneWidget);
    expect(find.text('目前不會收到派單'), findsOneWidget);
    expect(find.textContaining('http'), findsNothing);
    await tester.tap(find.text('連線狀態'));
    await tester.pumpAndSettle();
    expect(find.textContaining('http'), findsOneWidget);
  });

  testWidgets('收到派單顯示全螢幕接單卡，接單鈕高度 >= 56', (tester) async {
    await ctrl.init();
    await ctrl.login(lineUserId: 'U_driver', password: 'pw');
    ctrl.handleWsEventForTest(FleetWsEvent(
      type: FleetEventTypes.rideAssigned,
      rideId: 99,
      payload: {
        'address': '士林夜市',
        'dropoff_address': '松山機場',
        'dist_m': 1200,
        'eta_sec': 300,
      },
    ));
    await pumpHome(tester);

    expect(find.text('新派單'), findsOneWidget);
    expect(find.text('接單'), findsOneWidget);
    final size = tester.getSize(find.widgetWithText(FilledButton, '接單'));
    expect(size.height, greaterThanOrEqualTo(56));
  });

  testWidgets('放棄此單需二次確認', (tester) async {
    await storage.save(const AuthSession(
      driverId: 7,
      token: 'saved',
      name: '阿明',
    ));
    api.restoreRide = const ActiveRide(
      rideId: 42,
      address: '台北車站',
      phase: DriverRidePhase.enRouteToPickup,
      dropoffAddress: '松山機場',
    );
    await ctrl.init();
    await pumpHome(tester);

    await tester.tap(find.text('放棄此單'));
    await tester.pumpAndSettle();
    expect(find.text('確定放棄這筆訂單？'), findsOneWidget);
    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();
    expect(find.text('確定放棄這筆訂單？'), findsNothing);
  });
}

class _FakeFleetApi extends FleetApiClient {
  _FakeFleetApi()
      : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  ActiveRide? restoreRide;

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
  Future<ActiveRide?> activeRide() async => restoreRide;

  @override
  Future<List<LostItemRequest>> fetchLostItems() async => const [];

  @override
  Future<String> acceptRide(int rideId) async => '接單成功';

  @override
  Future<void> cancelRide(int rideId) async {}

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
