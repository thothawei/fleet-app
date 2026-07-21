import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/util/route_stops.dart';

RideStop _stop(
  int id, {
  StopKind kind = StopKind.pickup,
  double lat = 25.0,
  double lng = 121.0,
  bool arrived = false,
  bool skipped = false,
}) {
  return RideStop(
    id: id,
    seq: id,
    kind: kind,
    lat: lat,
    lng: lng,
    passengerLabel: 'A',
    arrivedAt: arrived ? DateTime(2026, 7, 17) : null,
    skippedAt: skipped ? DateTime(2026, 7, 17) : null,
  );
}

void main() {
  group('概覽地圖多點連線（N）純函式', () {
    test('visibleRouteStops 濾掉已跳過的站（乘客沒出現，畫出來會誤導路線）', () {
      final stops = [_stop(1), _stop(2, skipped: true), _stop(3, arrived: true)];
      expect(visibleRouteStops(stops).map((s) => s.id).toList(), [1, 3]);
    });

    test('nextPendingStop 取第一個待處理；全處理完回 null', () {
      final stops = [
        _stop(1, arrived: true),
        _stop(2, skipped: true),
        _stop(3),
        _stop(4),
      ];
      expect(nextPendingStop(stops)?.id, 3);
      expect(
        nextPendingStop([_stop(1, arrived: true), _stop(2, skipped: true)]),
        isNull,
      );
    });

    test('routePolylinePoints：司機 → 待處理站依序；已到達／已跳過不入線', () {
      final stops = [
        _stop(1, arrived: true, lat: 25.1, lng: 121.1),
        _stop(2, skipped: true, lat: 25.2, lng: 121.2),
        _stop(3, lat: 25.3, lng: 121.3),
        _stop(4, kind: StopKind.dropoff, lat: 25.4, lng: 121.4),
      ];
      final points = routePolylinePoints(const LatLng(25.0, 121.0), stops);
      expect(points, [
        const LatLng(25.0, 121.0),
        const LatLng(25.3, 121.3),
        const LatLng(25.4, 121.4),
      ]);
    });

    test('routePolylinePoints：無 GPS fix 時只串待處理站', () {
      final stops = [
        _stop(1, lat: 25.3, lng: 121.3),
        _stop(2, kind: StopKind.dropoff, lat: 25.4, lng: 121.4),
      ];
      expect(routePolylinePoints(null, stops), [
        const LatLng(25.3, 121.3),
        const LatLng(25.4, 121.4),
      ]);
    });

    test('routePolylinePoints：不足兩點回空（沒有線可畫）', () {
      expect(routePolylinePoints(null, [_stop(1)]), isEmpty);
      expect(routePolylinePoints(const LatLng(25.0, 121.0), const []), isEmpty);
      // 只剩已跳過的站 → 司機一個點也畫不出線。
      expect(
        routePolylinePoints(
          const LatLng(25.0, 121.0),
          [_stop(1, skipped: true)],
        ),
        isEmpty,
      );
    });
  });
}
