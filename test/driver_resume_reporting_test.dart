import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:line_fleet_app/core/api/fleet_api_client.dart';
import 'package:line_fleet_app/core/config/app_config.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/storage/token_storage.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/driver/driver_controller.dart';

/// App 被收掉後重開，行程還在——但位置回報整段消失。
///
/// 這是「定位健康度」這一族最後一個沒有網的角落：前景服務被系統收走、或司機自己
/// 把 App 從最近工作清單滑掉，`_restoreActiveRide` 會把行程還原、行程卡照樣顯示
/// 「導航／已上車／完成」，但 `_online` 一律從 false 起、定位串流也沒起來。
/// 後果不在司機這一端：**乘客端的司機 marker 定格、後端的抵達圍籬不會觸發、
/// F3 里程的軌跡缺一整段**，而司機看到的只是 hero 上那句「離線／目前不會收到派單」。
void main() {
  group('冷啟動還原到行程中', () {
    test('要把定位回報接回來（不然整趟乘客都看不到司機在動）', () async {
      final api = _RideApi()..active = _ride;
      final gps = StreamController<Position>();
      final ctrl = _driver(api, gps, granted: true);
      addTearDown(ctrl.dispose);

      await ctrl.init();

      expect(ctrl.activeRide?.rideId, 9, reason: '前置：行程有還原');
      expect(ctrl.online, isTrue, reason: '載客途中卻不回報位置＝乘客端的司機定格');

      gps.add(_pos(25.03));
      await Future<void>.delayed(Duration.zero);
      expect(api.reportCalls, greaterThan(0),
          reason: '旗標打開卻沒接上串流，位置一樣送不出去');

      await ctrl.goOffline();
    });

    test('沒有行程就不自動上線（接不接單是司機的決定）', () async {
      final api = _RideApi()..active = null;
      final gps = StreamController<Position>();
      final ctrl = _driver(api, gps, granted: true);
      addTearDown(ctrl.dispose);

      await ctrl.init();

      expect(ctrl.online, isFalse);
      expect(api.reportCalls, 0);
    });

    test('查不到權限狀態（平台不可用）→ 什麼都不做，也不編故事', () async {
      final api = _RideApi()..active = _ride;
      final gps = StreamController<Position>();
      final ctrl = DriverController(
        storage: MemoryDriverAuthStore()
          ..save(const AuthSession(driverId: 7, token: 'tok')),
        api: api,
        wsFactory: FleetWsClient.silent,
        positionStream: (_) => gps.stream,
        locationPermissionProbe: () async => null,
      );
      addTearDown(ctrl.dispose);

      await ctrl.init();

      expect(ctrl.online, isFalse);
      expect(ctrl.error, isNull, reason: '「查不到」與「被拒絕」是兩件事');
    });

    test('權限被拒 → 不上線、不彈視窗，但要講「回報給乘客」不是「上線」', () async {
      final api = _RideApi()..active = _ride;
      final gps = StreamController<Position>();
      final ctrl = _driver(api, gps, granted: false);
      addTearDown(ctrl.dispose);

      await ctrl.init();

      expect(ctrl.online, isFalse);
      expect(ctrl.error, contains('乘客'),
          reason: '行程中的司機看到「才能上線」會以為那只影響接新單');
    });

    test('司機自己按了離線就不再自動接回來（那顆鈕要按得掉）', () async {
      final api = _RideApi()..active = _ride;
      final gps = StreamController<Position>();
      final ctrl = _driver(api, gps, granted: true);
      addTearDown(ctrl.dispose);
      await ctrl.init();
      await ctrl.goOffline();
      expect(ctrl.online, isFalse, reason: '前置：司機按下離線');

      // 回前景會再對帳一次行程——這條路徑**不可以**順手把他重新上線。
      await ctrl.onAppResumed();

      expect(ctrl.online, isFalse);
    });
  });
}

final _ride = const ActiveRide(
  rideId: 9,
  address: '台北車站',
  phase: DriverRidePhase.onTrip,
);

Position _pos(double lat) => Position(
      latitude: lat,
      longitude: 121.56,
      timestamp: DateTime.now(),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

DriverController _driver(
  _RideApi api,
  StreamController<Position> gps, {
  required bool granted,
  LocationPermission? probe,
}) =>
    DriverController(
      storage: MemoryDriverAuthStore()
        ..save(const AuthSession(driverId: 7, token: 'tok')),
      api: api,
      wsFactory: FleetWsClient.silent,
      positionStream: (_) => gps.stream,
      locationPermissions: () async => granted,
      locationPermissionProbe: () async =>
          probe ??
          (granted
              ? LocationPermission.whileInUse
              : LocationPermission.denied),
    );

class _RideApi extends FleetApiClient {
  _RideApi() : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  ActiveRide? active;
  int reportCalls = 0;

  @override
  void setToken(String? token) {}

  @override
  Future<ActiveRide?> activeRide() async => active;

  @override
  Future<void> reportLocation({required double lat, required double lng}) async {
    reportCalls++;
  }

  @override
  Future<List<LostItemRequest>> fetchLostItems() async => <LostItemRequest>[];

  @override
  Future<DriverVehicle> fetchVehicle() async => const DriverVehicle(
        vehicleType: 'sedan',
        plateNumber: 'TEST-01',
        hasVehicle: true,
        canAccept: true,
      );
}
