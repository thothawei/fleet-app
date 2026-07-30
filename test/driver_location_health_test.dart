import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:line_fleet_app/core/api/fleet_api_client.dart';
import 'package:line_fleet_app/core/config/app_config.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/storage/token_storage.dart';
import 'package:line_fleet_app/core/theme/app_theme.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/driver/driver_controller.dart';
import 'package:line_fleet_app/driver/widgets/online_hero_card.dart';

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

/// 定位串流死掉時，畫面必須知道。
///
/// 第六輪做了 `locationStale`（位置久到後端不再把司機當派單候選 → hero 改說
/// 「位置回報失敗，暫時收不到派單」）。但它是在 build 當下用 `DateTime.now()` 算的，
/// 而司機端**沒有任何輪詢**——唯一會觸發重畫的就是位置回報本身。
/// 於是最該被它接住的情境（權限被撤、定位服務被關 → 串流不再吐 tick）
/// 正好就是「重畫來源消失」的情境：狀態是對的，螢幕永遠不會知道。
void main() {
  group('定位串流出錯', () {
    test('要留下錯誤訊息並通知畫面（不能靜靜吞掉）', () async {
      final (ctrl, gps) = await _driverWithGps();
      addTearDown(ctrl.dispose);
      ctrl.setOnlineForTest(true);
      await ctrl.startLocationStreamForTest();

      var notified = 0;
      ctrl.addListener(() => notified++);

      gps.addError(const LocationServiceDisabledException());
      await Future<void>.delayed(Duration.zero);

      expect(ctrl.error, isNotNull, reason: '串流死了卻一句話都沒有＝司機不會知道');
      expect(ctrl.error, contains('定位'));
      expect(ctrl.locationStale, isTrue, reason: '不會再有位置送出去，不必等滿 60 秒');
      expect(notified, greaterThan(0), reason: '設了狀態沒人通知＝畫面照舊');

      ctrl.setOnlineForTest(false);
    });

    test('權限被撤與定位服務被關要分開講（司機的下一步不一樣）', () async {
      final (ctrl, gps) = await _driverWithGps();
      addTearDown(ctrl.dispose);
      ctrl.setOnlineForTest(true);
      await ctrl.startLocationStreamForTest();

      gps.addError(const PermissionDeniedException(null));
      await Future<void>.delayed(Duration.zero);
      final denied = ctrl.error;

      gps.addError(const LocationServiceDisabledException());
      await Future<void>.delayed(Duration.zero);
      final disabled = ctrl.error;

      expect(denied, isNot(disabled));
      expect(denied, contains('權限'));
      expect(disabled, contains('定位服務'));

      ctrl.setOnlineForTest(false);
    });

    test('位置又送得出去就恢復（權限補回來之後不能一直掛著紅字）', () async {
      final (ctrl, gps) = await _driverWithGps();
      addTearDown(ctrl.dispose);
      ctrl.setOnlineForTest(true);
      await ctrl.startLocationStreamForTest();

      gps.addError(const LocationServiceDisabledException());
      await Future<void>.delayed(Duration.zero);
      expect(ctrl.locationStale, isTrue);

      gps.add(_pos(25.03));
      await Future<void>.delayed(Duration.zero);

      expect(ctrl.locationStale, isFalse, reason: '一筆成功回報就代表串流活過來了');
      ctrl.setOnlineForTest(false);
    });
  });

  group('沒有 tick 的時候誰來把畫面叫醒', () {
    test('過了鮮度窗要自己通知一次——這正是串流死掉時的樣子', () {
      fakeAsync((async) {
        final ctrl = _syncDriver(async);
        var sawStale = false;
        ctrl.addListener(() {
          if (ctrl.locationStale) sawStale = true;
        });

        ctrl.setOnlineForTest(true);
        unawaited(ctrl.startLocationStreamForTest());
        async.elapse(const Duration(milliseconds: 1));
        // 上線時刻挪到鮮度窗之外，而且**不會再有任何位置回報**——
        // 這時能把畫面叫醒的只剩定期重評那支 timer。
        ctrl.markOnlineSinceForTest(DateTime.now()
            .subtract(const Duration(seconds: AppConfig.driverOfflineSec + 5)));
        sawStale = false;

        async.elapse(const Duration(seconds: 30));

        expect(sawStale, isTrue,
            reason: '過了鮮度窗卻沒人通知，hero 會一直停在「等待派單中」');
        ctrl.dispose();
      });
    });

    test('離線之後不再定期喚醒（不留背景 timer 白耗電）', () {
      fakeAsync((async) {
        final ctrl = _syncDriver(async);
        ctrl.setOnlineForTest(true);
        unawaited(ctrl.startLocationStreamForTest());
        async.elapse(const Duration(milliseconds: 1));
        ctrl.markOnlineSinceForTest(DateTime.now()
            .subtract(const Duration(seconds: AppConfig.driverOfflineSec + 5)));
        ctrl.setOnlineForTest(false);

        var notified = 0;
        ctrl.addListener(() => notified++);
        async.elapse(const Duration(minutes: 5));

        expect(notified, 0);
        ctrl.dispose();
      });
    });
  });

  testWidgets('串流死掉後，hero 自己降級成「收不到派單」', (tester) async {
    final (ctrl, gps) = await _driverWithGps();
    addTearDown(ctrl.dispose);
    ctrl.setOnlineForTest(true);
    await ctrl.startLocationStreamForTest();
    ctrl.setWsConnectedForTest(true); // WS 好好的——這正是難處，只有 GPS 死了

    // 正式畫面是 context.watch 訂閱 controller；這裡用 ListenableBuilder 等價重現，
    // 否則「有沒有通知」根本測不到（OnlineHeroCard 自己不訂閱）。
    await tester.pumpWidget(MaterialApp(
      theme: appLightTheme,
      home: Scaffold(
        body: ListenableBuilder(
          listenable: ctrl,
          builder: (_, _) => OnlineHeroCard(ctrl: ctrl),
        ),
      ),
    ));
    expect(find.text('等待派單中'), findsOneWidget);

    gps.addError(const LocationServiceDisabledException());
    await tester.pump();

    expect(find.text('等待派單中'), findsNothing,
        reason: 'GPS 死了還說等待派單中，司機會一直等一張永遠不會來的單');
    expect(find.text('位置回報失敗，暫時收不到派單'), findsOneWidget);

    // 收尾：testWidgets 結束時有未完成的 timer 會直接判失敗（tearDown 的 dispose
    // 排在那個檢查之後）。這裡有兩支要清：定位健康度 timer，以及上線時那筆
    // 「立即回報」在 geolocator 內部排的 8 秒 timeLimit。
    ctrl.setOnlineForTest(false);
    await tester.pump(const Duration(seconds: 10));
  });
}

/// 假的定位串流：測試自己決定什麼時候吐位置、什麼時候丟錯誤。
Future<(DriverController, StreamController<Position>)> _driverWithGps() async {
  final gps = StreamController<Position>();
  final ctrl = DriverController(
    storage: MemoryDriverAuthStore()
      ..save(const AuthSession(driverId: 7, token: 'tok')),
    api: _SilentApi(),
    wsFactory: FleetWsClient.silent,
    positionStream: (_) => gps.stream,
  );
  await ctrl.init();
  return (ctrl, gps);
}

Future<DriverController> _driver() async => (await _driverWithGps()).$1;

/// fakeAsync 裡不能 await：用 flushMicrotasks 把 `init()` 推完。
DriverController _syncDriver(FakeAsync async) {
  DriverController? made;
  _driver().then((c) => made = c);
  async.flushMicrotasks();
  return made!;
}

/// 這幾案都不碰網路，只要別打真 API。
class _SilentApi extends FleetApiClient {
  _SilentApi() : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  @override
  void setToken(String? token) {}

  @override
  Future<void> reportLocation({required double lat, required double lng}) async {}

  @override
  Future<ActiveRide?> activeRide() async => null;

  @override
  Future<List<LostItemRequest>> fetchLostItems() async => <LostItemRequest>[];

  // init() 會查車輛（O3 gate）；沒覆蓋的話會打真網路，測試就掛在那裡不動
  // （既有坑：Fake API 必須覆蓋 init 觸碰的所有端點）。
  @override
  Future<DriverVehicle> fetchVehicle() async => const DriverVehicle(
        vehicleType: 'sedan',
        plateNumber: 'TEST-01',
        hasVehicle: true,
        canAccept: true,
      );
}
