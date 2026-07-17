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

  testWidgets('上線但 WS 斷線時，hero 不得謊稱「等待派單中」', (tester) async {
    // 實跑遇過：WS Connection timed out，司機收不到任何派單，畫面卻一切正常。
    // 用「不回報連線」的 WS 替身模擬斷線（wsConnected 維持 false）。
    ctrl = DriverController(
      storage: storage,
      api: api,
      wsFactory: _NeverConnectsWs.new,
      push: push,
    );
    await ctrl.init();
    await ctrl.login(lineUserId: 'U_driver', password: 'pw');
    ctrl.setOnlineForTest(true);
    await pumpHome(tester);

    expect(ctrl.wsConnected, isFalse, reason: '前提：WS 未連上');
    expect(find.text('上線中'), findsOneWidget);
    expect(find.text('等待派單中'), findsNothing,
        reason: '斷線時說「等待派單中」會讓司機以為自己在接單');
    expect(find.textContaining('連線中斷'), findsOneWidget);
    // 收合的診斷區塊也要一致
    expect(find.text('未連線，派單可能延遲'), findsOneWidget);
  });

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

  /// 這些測試驗的是首頁，故一律當作「已填車輛」——未覆蓋的話 init() 會打真網路，
  /// 在 testWidgets 的 FakeAsync 下永不完成而卡死（Fake 必須覆蓋 init 觸碰的所有端點）。
  @override
  Future<DriverVehicle> fetchVehicle() async => const DriverVehicle(
        vehicleType: 'sedan',
        plateNumber: 'ABC-1234',
        hasVehicle: true,
      );

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

/// WS 替身：永遠連不上（不回報 connected），用來驗「上線但斷線」的畫面。
class _NeverConnectsWs extends FleetWsClient {
  _NeverConnectsWs({required super.onEvent, super.onConnectionChanged});

  @override
  Future<void> connect(String token) async {}

  @override
  Future<void> disconnect() async {}
}
