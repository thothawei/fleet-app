import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/models/models.dart';

void main() {
  group('RideStop 解析（N6）', () {
    test('完整欄位', () {
      final s = RideStop.fromJson({
        'id': 11,
        'seq': 1,
        'kind': 'pickup',
        'lat': 25.0478,
        'lng': 121.5170,
        'address': '台北車站',
        'passenger_label': 'A',
        'arrived_at': '2026-07-17T10:00:00Z',
      });
      expect(s.seq, 1);
      expect(s.kind, StopKind.pickup);
      expect(s.lat, 25.0478);
      expect(s.passengerLabel, 'A');
      expect(s.arrived, isTrue);
      expect(s.skipped, isFalse);
      expect(s.pending, isFalse);
      expect(s.title, '乘客 A上車');
    });

    test('待處理：後端不帶 arrived_at／skipped_at', () {
      // 後端只在真的發生時才帶這兩個鍵。
      final s = RideStop.fromJson({'id': 1, 'seq': 2, 'kind': 'dropoff', 'lat': 25.0, 'lng': 121.0});
      expect(s.pending, isTrue);
      expect(s.arrived, isFalse);
      expect(s.skipped, isFalse);
    });

    test('已跳過', () {
      final s = RideStop.fromJson({
        'id': 1, 'seq': 2, 'kind': 'pickup', 'lat': 25.0, 'lng': 121.0,
        'skipped_at': '2026-07-17T10:05:00Z',
      });
      expect(s.skipped, isTrue);
      expect(s.pending, isFalse);
    });

    test('座標為字串也吃得下（FCM data 值全是字串）', () {
      // 見 pitfall-fcm-data-all-strings：漏掉會讓推播路徑直接 TypeError。
      final s = RideStop.fromJson({'id': '3', 'seq': '2', 'kind': 'pickup', 'lat': '25.5', 'lng': '121.5'});
      expect(s.id, 3);
      expect(s.seq, 2);
      expect(s.lat, 25.5);
      expect(s.lng, 121.5);
    });

    test('listFrom 依 seq 排序；缺鍵或非陣列回空（＝單點訂單）', () {
      final list = RideStop.listFrom([
        {'id': 2, 'seq': 3, 'kind': 'dropoff', 'lat': 1.0, 'lng': 2.0},
        {'id': 1, 'seq': 1, 'kind': 'pickup', 'lat': 1.0, 'lng': 2.0},
      ]);
      expect(list.map((e) => e.seq).toList(), [1, 3]);
      expect(RideStop.listFrom(null), isEmpty);
      expect(RideStop.listFrom('nope'), isEmpty);
    });
  });

  group('ActiveRide.stops（N6）', () {
    ActiveRide rideWith(List<Map<String, dynamic>> stops) => ActiveRide.fromBackendJson({
          'id': 1,
          'status': 2,
          'pickup_address': '台北車站',
          'stops': stops,
        });

    test('單點訂單沒有 stops 鍵 → 空 list、hasStops=false', () {
      final r = ActiveRide.fromBackendJson({'id': 1, 'status': 2, 'pickup_address': '台北車站'});
      expect(r.hasStops, isFalse);
      expect(r.nextStop, isNull);
    });

    test('nextStop 跳過已處理的站', () {
      final r = rideWith([
        {'id': 1, 'seq': 1, 'kind': 'pickup', 'lat': 1.0, 'lng': 2.0, 'arrived_at': '2026-07-17T10:00:00Z'},
        {'id': 2, 'seq': 2, 'kind': 'pickup', 'lat': 1.0, 'lng': 2.0, 'skipped_at': '2026-07-17T10:01:00Z'},
        {'id': 3, 'seq': 3, 'kind': 'dropoff', 'lat': 1.0, 'lng': 2.0},
      ]);
      expect(r.hasStops, isTrue);
      // 已到達與已跳過的都不是「下一站」。
      expect(r.nextStop?.id, 3);
    });

    test('全部處理完 → nextStop 為 null', () {
      final r = rideWith([
        {'id': 1, 'seq': 1, 'kind': 'pickup', 'lat': 1.0, 'lng': 2.0, 'arrived_at': '2026-07-17T10:00:00Z'},
      ]);
      expect(r.nextStop, isNull);
    });
  });

  group('buildStops：以人為單位 → 後端要的扁平陣列（N3）', () {
    StopPoint p(double v) => StopPoint(lat: v, lng: v, address: '地點$v');

    test('兩位乘客 → 先全部上車、再全部下車', () {
      final stops = buildStops([
        PassengerTrip(label: 'A', pickup: p(1), dropoff: p(3)),
        PassengerTrip(label: 'B', pickup: p(2), dropoff: p(4)),
      ]);

      expect(stops.map((s) => '${s.seq}${s.kind.code}${s.passengerLabel}').toList(),
          ['1pickupA', '2pickupB', '3dropoffA', '4dropoffB']);
    });

    test('產生的 stops 必定滿足後端 N2 的配對規則', () {
      final stops = buildStops([
        for (final l in ['A', 'B', 'C', 'D', 'E'])
          PassengerTrip(label: l, pickup: p(1), dropoff: p(2)),
      ]);

      expect(stops.length, maxRideStops); // 5 位 → 10 停（上限）

      // 每位成對、且下車一定排在上車之後（後端會擋「先送再接」）。
      for (final label in ['A', 'B', 'C', 'D', 'E']) {
        final mine = stops.where((s) => s.passengerLabel == label).toList();
        expect(mine.length, 2);
        final pickup = mine.firstWhere((s) => s.kind == StopKind.pickup);
        final dropoff = mine.firstWhere((s) => s.kind == StopKind.dropoff);
        expect(dropoff.seq, greaterThan(pickup.seq));
      }
      // seq 不重複（後端 UNIQUE(ride_id, seq) 會擋）。
      final seqs = stops.map((s) => s.seq).toList();
      expect(seqs.toSet().length, seqs.length);
    });

    test('未填完的乘客直接略過（不會送出半套資料）', () {
      final stops = buildStops([
        PassengerTrip(label: 'A', pickup: p(1), dropoff: p(2)),
        PassengerTrip(label: 'B', pickup: p(3)), // 只有上車 → 後端會回 ErrUnpairedStop
      ]);
      expect(stops.length, 2);
      expect(stops.every((s) => s.passengerLabel == 'A'), isTrue);
    });

    test('沒有任何完整乘客 → 空（＝單點訂單，不帶 stops 鍵）', () {
      expect(buildStops([]), isEmpty);
      expect(buildStops([PassengerTrip(label: 'A')]), isEmpty);
    });

    test('toJson 的鍵名與後端一致', () {
      final s = buildStops([PassengerTrip(label: 'A', pickup: p(1), dropoff: p(2))]).first;
      expect(s.toJson(), {
        'seq': 1,
        'kind': 'pickup',
        'lat': 1.0,
        'lng': 1.0,
        'address': '地點1.0',
        'passenger_label': 'A',
      });
    });
  });
}
