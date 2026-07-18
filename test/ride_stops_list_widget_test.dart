import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/fleet_api_client.dart';
import 'package:line_fleet_app/core/config/app_config.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/storage/token_storage.dart';
import 'package:line_fleet_app/core/theme/app_theme.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/driver/driver_controller.dart';
import 'package:line_fleet_app/driver/widgets/ride_stops_list.dart';

/// 回歸：RideStopsList 必須用**真的 App 主題**測。
///
/// 全域主題把 FilledButton／OutlinedButton 的 minimumSize 設成
/// `Size.fromHeight(48)`（寬＝infinity）；下一站的操作鈕放在 Row（寬度無界）裡，
/// 沒覆寫寬度就會 `BoxConstraints forces an infinite width`，整個 home body
/// layout 全滅變空白。模擬器實跑抓到——widget 測試當時用預設主題，測不出來。
void main() {
  testWidgets('多停靠點清單在真主題下可 layout，下一站給操作鈕', (tester) async {
    final ctrl = DriverController(
      storage: MemoryDriverAuthStore(),
      api: FleetApiClient(
        dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')),
      ),
      wsFactory: FleetWsClient.silent,
    );
    addTearDown(ctrl.dispose);

    const ride = ActiveRide(
      rideId: 1,
      address: '台北101',
      phase: DriverRidePhase.enRouteToPickup,
      stops: [
        RideStop(
            id: 1, seq: 1, kind: StopKind.pickup, lat: 25.033, lng: 121.5654, passengerLabel: 'A'),
        RideStop(
            id: 2, seq: 2, kind: StopKind.pickup, lat: 25.036, lng: 121.568, passengerLabel: 'B'),
        RideStop(
            id: 3, seq: 3, kind: StopKind.dropoff, lat: 25.0478, lng: 121.517, passengerLabel: 'A'),
        RideStop(
            id: 4, seq: 4, kind: StopKind.dropoff, lat: 25.04, lng: 121.51, passengerLabel: 'B'),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: appLightTheme,
        home: Scaffold(
          body: ListView(children: [RideStopsList(ctrl: ctrl, ride: ride)]),
        ),
      ),
    );

    // 有 layout 例外時 takeException 會回傳它——這正是本測試存在的原因。
    expect(tester.takeException(), isNull);
    expect(find.text('全程 4 站'), findsOneWidget);
    // 只有下一站（A 上車）有操作鈕。
    expect(find.text('已上車'), findsOneWidget);
    expect(find.text('跳過'), findsOneWidget);
  });
}
