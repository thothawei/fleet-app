import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:line_fleet_app/core/api/customer_api_client.dart';
import 'package:line_fleet_app/core/config/app_config.dart';
import 'package:line_fleet_app/core/location/driver_location_settings.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/util/maps.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/customer/customer_controller.dart';
import 'package:line_fleet_app/customer/screens/customer_home_screen.dart';
import 'package:provider/provider.dart';

void main() {
  test('driverLocationSettings 在測試環境回傳通用 LocationSettings', () {
    final settings = driverLocationSettings();
    expect(settings.accuracy, LocationAccuracy.high);
  });

  group('mapsNavigationUri 導航目標', () {
    test('有座標時用 lat,lng，不用地址', () {
      final uri = mapsNavigationUri('松山機場', lat: 25.06, lng: 121.55);
      expect(uri.queryParameters['query'], '25.06,121.55');
    });

    test('無座標時退回地址搜尋', () {
      final uri = mapsNavigationUri('松山機場');
      expect(uri.queryParameters['query'], '松山機場');
    });

    test('只有單邊座標時視為無座標', () {
      final uri = mapsNavigationUri('松山機場', lat: 25.06);
      expect(uri.queryParameters['query'], '松山機場');
    });
  });

  test('RideOffer 從 WS payload 解析', () {
    final offer = RideOffer.fromEvent(42, {
      'address': '台北車站',
      'eta_sec': 300,
      'dist_m': 1200,
      'dropoff_address': '松山機場',
      'dropoff_lat': 25.06,
      'dropoff_lng': 121.55,
    });
    expect(offer.rideId, 42);
    expect(offer.address, '台北車站');
    expect(offer.dropoffAddress, '松山機場');
    expect(offer.dropoffLat, 25.06);
    expect(offer.dropoffLng, 121.55);
    expect(offer.etaLabel, '約 5 分鐘');
  });

  test('RideOffer 無目的地座標時為 null（LINE 叫車路徑）', () {
    final offer = RideOffer.fromEvent(42, {'address': '台北車站'});
    expect(offer.dropoffAddress, isNull);
    expect(offer.dropoffLat, isNull);
    expect(offer.dropoffLng, isNull);
  });

  group('ActiveRide 行程階段轉移（Slice4：接單→上車→完成）', () {
    test('copyWith 只更新 phase，rideId/address 不變', () {
      const ride = ActiveRide(
        rideId: 7,
        address: '台北車站',
        phase: DriverRidePhase.enRouteToPickup,
      );
      final picked = ride.copyWith(phase: DriverRidePhase.onTrip);

      expect(picked.rideId, 7);
      expect(picked.address, '台北車站');
      expect(picked.phase, DriverRidePhase.onTrip);
    });

    test('copyWith 不傳 phase 時維持原值', () {
      const ride = ActiveRide(
        rideId: 7,
        address: '台北車站',
        phase: DriverRidePhase.onTrip,
      );
      expect(ride.copyWith().phase, DriverRidePhase.onTrip);
    });

    test('上車時 copyWith 帶入 dropoffAddress，供 onTrip 導航去目的地', () {
      const ride = ActiveRide(
        rideId: 7,
        address: '台北車站',
        phase: DriverRidePhase.enRouteToPickup,
      );
      final onTrip = ride.copyWith(
        phase: DriverRidePhase.onTrip,
        dropoffAddress: '松山機場',
      );
      expect(onTrip.phase, DriverRidePhase.onTrip);
      expect(onTrip.dropoffAddress, '松山機場');
    });

    test('copyWith 不傳 dropoffAddress 時維持原值（後續只換 phase 不清空目的地）', () {
      const ride = ActiveRide(
        rideId: 7,
        address: '台北車站',
        phase: DriverRidePhase.onTrip,
        dropoffAddress: '松山機場',
      );
      expect(ride.copyWith().dropoffAddress, '松山機場');
    });
  });

  group('FleetWsEvent 解析（對齊後端 internal/events/event.go 事件型別）', () {
    test('ride.assigned 帶 ride_id 與 payload（含 dropoff）', () {
      final event = FleetWsEvent.fromJson({
        'type': FleetEventTypes.rideAssigned,
        'ride_id': 42,
        'payload': {
          'address': '台北車站',
          'eta_sec': 300,
          'dist_m': 1200,
          'dropoff_address': '松山機場',
          'dropoff_lat': 25.08,
          'dropoff_lng': 121.57,
        },
      });
      expect(event.type, 'ride.assigned');
      expect(event.rideId, 42);
      expect(event.payload?['address'], '台北車站');
      expect(event.payload?['dropoff_address'], '松山機場');
      final offer = RideOffer.fromEvent(event.rideId!, event.payload);
      expect(offer.dropoffAddress, '松山機場');
    });

    test('ride.accepted 缺 payload 時仍能解析（payload 為 null）', () {
      final event = FleetWsEvent.fromJson({
        'type': FleetEventTypes.rideAccepted,
        'ride_id': 42,
      });
      expect(event.type, 'ride.accepted');
      expect(event.rideId, 42);
      expect(event.payload, isNull);
    });

    test('ride.accepted 司機端帶 dropoff_address（供 onTrip 預載目的地）', () {
      final event = FleetWsEvent.fromJson({
        'type': FleetEventTypes.rideAccepted,
        'ride_id': 42,
        'payload': {'dropoff_address': '松山機場'},
      });
      expect(event.payload?['dropoff_address'], '松山機場');
    });

    test('driver.location 帶 lat/lng/eta_sec/dist_m（乘客即時追蹤）', () {
      final event = FleetWsEvent.fromJson({
        'type': FleetEventTypes.driverLocation,
        'ride_id': 7,
        'payload': {'lat': 25.0, 'lng': 121.5, 'eta_sec': 300, 'dist_m': 320},
      });
      expect(event.type, 'driver.location');
      expect(event.rideId, 7);
      expect(event.payload?['dist_m'], 320);
      expect(event.payload?['eta_sec'], 300);
    });

    test('ride.picked_up / ride.completed / ride.cancelled 皆可正確解析', () {
      for (final type in [
        FleetEventTypes.ridePickedUp,
        FleetEventTypes.rideCompleted,
        FleetEventTypes.rideCancelled,
      ]) {
        final event = FleetWsEvent.fromJson({'type': type, 'ride_id': 1});
        expect(event.type, type);
        expect(event.rideId, 1);
      }
    });
  });

  group('乘客端 model 解析（對齊後端 customer.go / model.Ride）', () {
    test('CustomerLoginResult 解析 customer_id/token/name', () {
      final r = CustomerLoginResult.fromJson({
        'customer_id': 9,
        'token': 'jwt',
        'name': '小明',
      });
      expect(r.customerId, 9);
      expect(r.token, 'jwt');
      expect(r.name, '小明');
    });

    test('CustomerRide 解析下單回應（snake key: ride_id/status）', () {
      final ride = CustomerRide.fromJson({'ride_id': 12, 'status': 0});
      expect(ride.rideId, 12);
      expect(ride.status, 0);
      expect(ride.statusLabel, '尋找司機中');
      expect(ride.cancellable, isTrue);
      expect(ride.dropoffAddress, isNull);
    });

    test('CustomerRide 解析 model.Ride 查詢回應（PascalCase key + 目的地 + ETA）', () {
      final ride = CustomerRide.fromJson({
        'ID': 12,
        'Status': 2,
        'DropoffAddress': '松山機場',
        'EtaPickupSec': 300,
      });
      expect(ride.rideId, 12);
      expect(ride.status, 2);
      expect(ride.statusLabel, '司機前往上車點');
      expect(ride.cancellable, isTrue); // 上車前可取消
      expect(ride.dropoffAddress, '松山機場');
      expect(ride.etaLabel, '約 5 分鐘抵達');
    });

    test('CustomerRide 解析 pickup_point 座標（地圖追蹤用）', () {
      final ride = CustomerRide.fromJson({
        'ride_id': 5,
        'status': 2,
        'pickup_point': {'lat': 25.03, 'lng': 121.56},
      });
      expect(ride.pickupLat, closeTo(25.03, 0.001));
      expect(ride.pickupLng, closeTo(121.56, 0.001));
    });

    test('CustomerRide 已上車不可取消、無 ETA 時 etaLabel 為空', () {
      final ride = CustomerRide.fromJson({'ID': 12, 'Status': 3});
      expect(ride.cancellable, isFalse);
      expect(ride.etaLabel, '');
    });

    test('CustomerRide 已取消（status=9）顯示已取消、不可再取消', () {
      final ride = CustomerRide.fromJson({'ride_id': 12, 'status': 9});
      expect(ride.status, RideStatus.cancelled);
      expect(ride.statusLabel, '已取消');
      expect(ride.cancellable, isFalse);
    });

    test('CustomerRide 已完成（status=4）顯示已完成', () {
      final ride = CustomerRide.fromJson({'ride_id': 12, 'status': 4});
      expect(ride.statusLabel, '已完成');
      expect(RideStatus.isTerminal(ride.status), isTrue);
    });

    test('phaseLabel：Accepted + driverArrived → 司機已抵達上車點', () {
      const ride = CustomerRide(rideId: 1, status: RideStatus.accepted);
      expect(ride.phaseLabel(), '司機前往上車點');
      expect(
        ride.phaseLabel(driverArrived: true),
        '司機已抵達上車點',
      );
    });

    test('phaseLabel：非 Accepted 不受 driverArrived 影響', () {
      const ride = CustomerRide(rideId: 1, status: RideStatus.pickedUp);
      expect(ride.phaseLabel(driverArrived: true), '行程中');
    });
  });

  group('ActiveRide 從後端 active 查詢還原（司機 App 重啟）', () {
    test('status=2 → enRouteToPickup，帶目的地', () {
      final ride = ActiveRide.fromBackendJson({
        'id': 7,
        'status': RideStatus.accepted,
        'pickup_address': '台北車站',
        'dropoff_address': '松山機場',
      });
      expect(ride.rideId, 7);
      expect(ride.phase, DriverRidePhase.enRouteToPickup);
      expect(ride.dropoffAddress, '松山機場');
    });

    test('status=3 → onTrip', () {
      final ride = ActiveRide.fromBackendJson({
        'id': 7,
        'status': RideStatus.pickedUp,
        'pickup_address': '台北車站',
      });
      expect(ride.phase, DriverRidePhase.onTrip);
      expect(ride.hasDropoff, isFalse);
    });

    test('dropoff_point 還原目的地座標（App 重啟後仍可座標導航）', () {
      final ride = ActiveRide.fromBackendJson({
        'id': 7,
        'status': RideStatus.pickedUp,
        'pickup_address': '台北車站',
        'dropoff_address': '松山機場',
        'dropoff_point': {'lat': 25.06, 'lng': 121.55},
      });
      expect(ride.dropoffLat, 25.06);
      expect(ride.dropoffLng, 121.55);
      expect(ride.hasDropoff, isTrue);
    });
  });

  testWidgets('乘客端首頁預設顯示叫車表單（含目的地欄位）', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => CustomerController(),
        child: const MaterialApp(home: CustomerHomeScreen()),
      ),
    );
    expect(find.text('叫車'), findsWidgets);
    expect(find.text('目的地地址'), findsOneWidget);
  });

  testWidgets('B5 完成態顯示評分／付款佔位與再叫一輛', (tester) async {
    final ctrl = CustomerController();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: ctrl,
        child: const MaterialApp(home: CustomerHomeScreen()),
      ),
    );
    ctrl.markCompletedForTest(
      rideId: 42,
      dropoffAddress: '松山機場',
      driverName: '阿明',
    );
    await tester.pump();

    expect(find.text('行程已完成'), findsOneWidget);
    expect(find.text('行程 #42'), findsOneWidget);
    expect(find.text('司機：阿明'), findsOneWidget);
    expect(find.text('目的地：松山機場'), findsOneWidget);
    expect(find.text('留下評分（即將開放）'), findsOneWidget);
    expect(find.text('查看費用（即將開放）'), findsOneWidget);

    await tester.tap(find.text('再叫一輛'));
    await tester.pump();
    expect(find.text('行程已完成'), findsNothing);
    expect(find.text('目的地地址'), findsOneWidget);
  });

  group('CustomerApiClient.createRide 送出 body（地圖選點帶座標）', () {
    CustomerApiClient apiWith(_CaptureAdapter adapter) {
      final dio = Dio(BaseOptions(baseUrl: 'http://x/api'))
        ..httpClientAdapter = adapter;
      return CustomerApiClient(dio: dio);
    }

    test('有地圖座標時 body 帶 dropoff_lat/lng 與地址', () async {
      final adapter = _CaptureAdapter();
      await apiWith(adapter).createRide(
        pickupLat: 25,
        pickupLng: 121,
        pickupAddress: '上車',
        dropoffAddress: '松山機場',
        dropoffLat: 25.08,
        dropoffLng: 121.57,
      );
      expect(adapter.lastBody!['dropoff_address'], '松山機場');
      expect(adapter.lastBody!['dropoff_lat'], 25.08);
      expect(adapter.lastBody!['dropoff_lng'], 121.57);
    });

    test('純文字目的地時 body 不含 dropoff_lat/lng', () async {
      final adapter = _CaptureAdapter();
      await apiWith(adapter).createRide(
        pickupLat: 25,
        pickupLng: 121,
        pickupAddress: '上車',
        dropoffAddress: '松山機場',
      );
      expect(adapter.lastBody!.containsKey('dropoff_lat'), isFalse);
      expect(adapter.lastBody!.containsKey('dropoff_lng'), isFalse);
      expect(adapter.lastBody!['dropoff_address'], '松山機場');
    });
  });
}

/// 攔截 Dio 送出的 request，捕捉 body 供斷言；回固定成功回應。
class _CaptureAdapter implements HttpClientAdapter {
  Map<String, dynamic>? lastBody;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastBody = options.data as Map<String, dynamic>?;
    return ResponseBody.fromString(
      '{"ride_id":1,"status":0}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
