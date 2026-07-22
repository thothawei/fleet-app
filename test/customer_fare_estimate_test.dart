import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/customer_api_client.dart';
import 'package:line_fleet_app/core/api/fleet_api_client.dart' show ApiException;
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/customer/customer_controller.dart';

/// 記錄 estimateFare 收到的參數，回一筆可控的預估；可設定為丟例外（測靜默失敗）。
class _FakeEstimateApi extends CustomerApiClient {
  _FakeEstimateApi();

  int calls = 0;
  List<StopInput> lastStops = const [];
  String? lastVehicleType;
  bool shouldThrow = false;
  FareEstimate result = const FareEstimate(
    fareCents: 18500,
    cleaningFeeCents: 0,
    totalCents: 18500,
    distanceM: 5000,
    durationSec: 600,
  );

  @override
  Future<FareEstimate> estimateFare({
    required double pickupLat,
    required double pickupLng,
    double? dropoffLat,
    double? dropoffLng,
    String? requiredVehicleType,
    List<StopInput> stops = const [],
  }) async {
    calls++;
    lastStops = stops;
    lastVehicleType = requiredVehicleType;
    if (shouldThrow) {
      throw ApiException('boom');
    }
    return result;
  }

  // 選寵物車時 controller 會查費率，避免打真網路。
  @override
  Future<int> fetchPetCleaningFeeBps() async => 2000;
}

void main() {
  StopPoint p(double v) => StopPoint(lat: v, lng: v, address: '地點$v');

  // _refreshEstimate 是 fire-and-forget 的 async，flush 幾輪微任務讓它跑完。
  Future<void> flush() async {
    for (var i = 0; i < 3; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  group('建單前車資預估（懸而未決 #1）', () {
    late _FakeEstimateApi api;
    late CustomerController ctrl;

    setUp(() {
      api = _FakeEstimateApi();
      ctrl = CustomerController(api: api);
      ctrl.setSessionForTest(
        const CustomerSession(customerId: 1, token: 'tok', name: '小美'),
      );
    });

    tearDown(() => ctrl.dispose());

    test('多停靠點填完 → 帶 stops 預估，不需 GPS', () async {
      ctrl.addPassenger();
      ctrl.setPassengerPoint(0, pickup: p(1), dropoff: p(2));
      await flush();

      expect(api.calls, greaterThan(0));
      expect(api.lastStops, isNotEmpty, reason: '多停靠點模式應帶 stops');
      expect(ctrl.fareEstimate, isNotNull);
      expect(ctrl.fareEstimate!.totalCents, 18500);
      expect(ctrl.estimating, isFalse);
    });

    test('車種改寵物車 → 重算預估並帶新車種（含清潔費）', () async {
      ctrl.addPassenger();
      ctrl.setPassengerPoint(0, pickup: p(1), dropoff: p(2));
      await flush();
      final before = api.calls;

      // 寵物車的預估含清潔費。
      api.result = const FareEstimate(
        fareCents: 18500,
        cleaningFeeCents: 3700,
        totalCents: 22200,
        distanceM: 5000,
        durationSec: 600,
      );
      await ctrl.setRequiredVehicleType(VehicleType.pet);
      await flush();

      expect(api.calls, greaterThan(before), reason: '車種變更要觸發重算');
      expect(api.lastVehicleType, VehicleType.pet.code);
      expect(ctrl.fareEstimate!.hasCleaningFee, isTrue);
      expect(ctrl.fareEstimate!.totalCents, 22200);
    });

    test('預估失敗 → 靜默清空，不擋叫車、不丟例外', () async {
      api.shouldThrow = true;
      ctrl.addPassenger();
      ctrl.setPassengerPoint(0, pickup: p(1), dropoff: p(2));
      await flush();

      expect(api.calls, greaterThan(0));
      expect(ctrl.fareEstimate, isNull, reason: '失敗時不顯示預估');
      expect(ctrl.estimating, isFalse);
    });

    test('clearEstimate 清掉預估與座標', () async {
      ctrl.addPassenger();
      ctrl.setPassengerPoint(0, pickup: p(1), dropoff: p(2));
      await flush();
      expect(ctrl.fareEstimate, isNotNull);

      ctrl.clearEstimate();
      expect(ctrl.fareEstimate, isNull);
      expect(ctrl.estimating, isFalse);
    });

    test('移除全部乘客且無單點目的地 → 沒有可預估輸入，清空', () async {
      ctrl.addPassenger();
      ctrl.setPassengerPoint(0, pickup: p(1), dropoff: p(2));
      await flush();
      expect(ctrl.fareEstimate, isNotNull);

      ctrl.disableMultiStop(); // 清空乘客
      await flush();
      expect(ctrl.fareEstimate, isNull, reason: '無 stops 又無單點座標 → 無預估');
    });
  });

  group('FareEstimate 模型', () {
    test('fromJson 解析後端欄位', () {
      final e = FareEstimate.fromJson(const {
        'fare_cents': 18500,
        'cleaning_fee_cents': 3700,
        'total_cents': 22200,
        'distance_m': 5000,
        'duration_sec': 600,
      });
      expect(e.fareCents, 18500);
      expect(e.cleaningFeeCents, 3700);
      expect(e.totalCents, 22200);
      expect(e.hasCleaningFee, isTrue);
    });

    test('缺鍵時歸零、無清潔費', () {
      final e = FareEstimate.fromJson(const {'total_cents': 8500});
      expect(e.fareCents, 0);
      expect(e.cleaningFeeCents, 0);
      expect(e.hasCleaningFee, isFalse);
      expect(e.totalCents, 8500);
    });
  });
}
