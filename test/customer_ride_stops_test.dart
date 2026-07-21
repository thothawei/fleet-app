import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/customer_api_client.dart';
import 'package:line_fleet_app/core/config/app_config.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/theme/app_theme.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/customer/customer_controller.dart';
import 'package:line_fleet_app/customer/widgets/ride_stops_progress.dart';

/// 乘客端多停靠點行程進度（N8）。
/// 後端 `GET /api/customer/rides/active` 與 WS `ride.stop_updated` 都帶整趟 stops。
void main() {
  const stopsJson = [
    {
      'id': 1,
      'seq': 1,
      'kind': 'pickup',
      'lat': 25.033,
      'lng': 121.5654,
      'address': '台北101',
      'passenger_label': 'A',
      'arrived_at': '2026-07-21T19:09:52+08:00',
    },
    {
      'id': 2,
      'seq': 2,
      'kind': 'pickup',
      'lat': 25.036,
      'lng': 121.568,
      'address': '國父紀念館',
      'passenger_label': 'B',
      'skipped_at': '2026-07-21T19:12:00+08:00',
    },
    {
      'id': 3,
      'seq': 3,
      'kind': 'dropoff',
      'lat': 25.0478,
      'lng': 121.517,
      'address': '台北車站',
      'passenger_label': 'A',
    },
  ];

  test('CustomerRide 解析後端 stops，並算出下一站與已處理站數', () {
    final ride = CustomerRide.fromJson({
      'id': 7,
      'status': RideStatus.pickedUp,
      'stops': stopsJson,
    });

    expect(ride.hasStops, isTrue);
    expect(ride.stops.length, 3);
    // 已到達與已跳過都算「處理完」——司機都不會再回去那兩站。
    expect(ride.handledStopCount, 2);
    expect(ride.nextStop?.id, 3, reason: '第 3 站是唯一待處理的站');
    expect(ride.stops[0].arrived, isTrue);
    expect(ride.stops[1].skipped, isTrue);
  });

  test('單點訂單沒有 stops 鍵 → 空 list，既有行為不變', () {
    final ride = CustomerRide.fromJson({'id': 8, 'status': RideStatus.accepted});
    expect(ride.hasStops, isFalse);
    expect(ride.nextStop, isNull);
  });

  test('WS ride.stop_updated 以整批覆蓋進行中訂單的 stops', () async {
    final ctrl = CustomerController(
      api: CustomerApiClient(
        dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')),
      ),
    );
    addTearDown(ctrl.dispose);

    ctrl.setSessionForTest(
      const CustomerSession(customerId: 1, token: 'tok', name: '乘客'),
    );
    ctrl.setActiveRideForTest(
      CustomerRide.fromJson({
        'id': 7,
        'status': RideStatus.pickedUp,
        // 起始狀態：三站都還沒處理
        'stops': [
          for (final s in stopsJson)
            {
              for (final e in s.entries)
                if (e.key != 'arrived_at' && e.key != 'skipped_at') e.key: e.value,
            },
        ],
      }),
    );
    expect(ctrl.activeRide!.handledStopCount, 0, reason: '前提：起始沒有任何站被處理');

    ctrl.handleWsEventForTest(FleetWsEvent(
      type: FleetEventTypes.rideStopUpdated,
      rideId: 7,
      payload: const {'stops': stopsJson},
    ));

    expect(ctrl.activeRide!.handledStopCount, 2, reason: '收到事件應整批覆蓋');
    expect(ctrl.activeRide!.nextStop?.id, 3);
  });

  test('ride.stop_updated 的 ride_id 不符時不套用（別趟的進度不能蓋自己的）', () {
    final ctrl = CustomerController(
      api: CustomerApiClient(
        dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')),
      ),
    );
    addTearDown(ctrl.dispose);

    ctrl.setSessionForTest(
      const CustomerSession(customerId: 1, token: 'tok', name: '乘客'),
    );
    ctrl.setActiveRideForTest(
      CustomerRide.fromJson({'id': 7, 'status': RideStatus.pickedUp}),
    );

    ctrl.handleWsEventForTest(FleetWsEvent(
      type: FleetEventTypes.rideStopUpdated,
      rideId: 99,
      payload: const {'stops': stopsJson},
    ));

    expect(ctrl.activeRide!.hasStops, isFalse);
  });

  testWidgets('進度卡列出全程：下一站標示、已完成、未搭乘', (tester) async {
    final ride = CustomerRide.fromJson({
      'id': 7,
      'status': RideStatus.pickedUp,
      'stops': stopsJson,
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: appLightTheme,
        home: Scaffold(body: ListView(children: [RideStopsProgress(ride: ride)])),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('行程進度 2／3 站'), findsOneWidget);
    expect(find.text('下一站：乘客 A下車'), findsOneWidget);
    expect(find.text('已完成'), findsOneWidget);
    // 「跳過」是司機視角的動作，乘客看到的應該是結果。
    expect(find.text('未搭乘'), findsOneWidget);
    expect(find.text('跳過'), findsNothing);
  });

  testWidgets('單點訂單不顯示進度卡', (tester) async {
    final ride = CustomerRide.fromJson({'id': 8, 'status': RideStatus.accepted});

    await tester.pumpWidget(
      MaterialApp(
        theme: appLightTheme,
        home: Scaffold(body: RideStopsProgress(ride: ride)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('行程進度'), findsNothing);
  });
}
