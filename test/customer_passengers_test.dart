import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/customer_api_client.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/storage/customer_token_storage.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/customer/customer_controller.dart';

void main() {
  late _StopsFakeApi api;
  late CustomerController ctrl;

  setUp(() {
    api = _StopsFakeApi();
    ctrl = CustomerController(
      storage: _MemoryCustomerStorage(),
      api: api,
      wsFactory: FleetWsClient.silent,
    );
  });

  tearDown(() => ctrl.dispose());

  StopPoint p(double v) => StopPoint(lat: v, lng: v, address: '地點$v');

  group('多乘客編輯（N3）', () {
    test('預設不啟用 → 單點訂單的既有流程', () {
      expect(ctrl.multiStopEnabled, isFalse);
      expect(ctrl.passengers, isEmpty);
    });

    test('啟用時只加一位（漸進展開，不逼使用者一次填滿 5 位）', () {
      ctrl.enableMultiStop();
      expect(ctrl.passengers.length, 1);
      expect(ctrl.passengers.first.label, 'A');
    });

    test('新增乘客的標籤依序 A/B/C…', () {
      ctrl.enableMultiStop();
      ctrl.addPassenger();
      ctrl.addPassenger();
      expect(ctrl.passengers.map((e) => e.label).toList(), ['A', 'B', 'C']);
    });

    test('上限 5 位（後端 N2 拍板，超過會回 400）', () {
      ctrl.enableMultiStop();
      for (var i = 0; i < 10; i++) {
        ctrl.addPassenger();
      }
      expect(ctrl.passengers.length, maxRidePassengers);
      expect(ctrl.canAddPassenger, isFalse);
    });

    test('移除後重新編號，不留跳號', () {
      ctrl.enableMultiStop();
      ctrl.addPassenger();
      ctrl.addPassenger();
      ctrl.setPassengerPoint(2, pickup: p(3)); // C 的資料
      ctrl.removePassenger(1); // 移除 B

      // 原本的 C 變成 B——留下「A、C」會讓司機困惑。
      expect(ctrl.passengers.map((e) => e.label).toList(), ['A', 'B']);
      // 資料要跟著搬，不能因為重新編號就掉。
      expect(ctrl.passengers[1].pickup?.lat, 3);
    });

    test('關閉多乘客模式 → 回到單一目的地', () {
      ctrl.enableMultiStop();
      ctrl.disableMultiStop();
      expect(ctrl.multiStopEnabled, isFalse);
    });

    test('completePassengerCount 只算填完的', () {
      ctrl.enableMultiStop();
      ctrl.addPassenger();
      ctrl.setPassengerPoint(0, pickup: p(1), dropoff: p(2));
      ctrl.setPassengerPoint(1, pickup: p(3)); // B 只有上車
      expect(ctrl.completePassengerCount, 1);
    });
  });

  group('送出前的資料準備（N3）', () {
    // placeOrder 全流程需要 geolocator（platform channel），單元測試環境沒有 binding，
    // 故這裡驗「送出前」這一段：擋未填完、以及 buildStops 產出的形狀。
    // 端到端已由後端 live E2E 覆蓋（dispatch：2 乘客 4 停建單成功）。

    test('沒有任何乘客填完 → 擋下並提示，不送出半套資料', () async {
      await ctrl.init();
      await ctrl.login(lineUserId: 'U', password: 'pw');
      ctrl.enableMultiStop();
      ctrl.setPassengerPoint(0, pickup: p(1)); // 只有上車

      await ctrl.placeOrder(pickupAddress: '', dropoffAddress: '');

      // 後端會回 ErrUnpairedStop，但這種錯不該讓使用者跑一趟網路才知道。
      expect(ctrl.error, contains('上車與下車'));
      expect(api.createCalls, 0);
    });

    test('填完的乘客會被轉成後端要的扁平 stops', () {
      ctrl.enableMultiStop();
      ctrl.addPassenger();
      ctrl.setPassengerPoint(0, pickup: p(1), dropoff: p(3));
      ctrl.setPassengerPoint(1, pickup: p(2), dropoff: p(4));

      final stops = buildStops(ctrl.passengers);
      expect(stops.length, 4);
      expect(stops.map((s) => s.seq).toList(), [1, 2, 3, 4]);
      for (final label in ['A', 'B']) {
        final mine = stops.where((s) => s.passengerLabel == label);
        final pickup = mine.firstWhere((s) => s.kind == StopKind.pickup);
        final dropoff = mine.firstWhere((s) => s.kind == StopKind.dropoff);
        expect(dropoff.seq, greaterThan(pickup.seq));
      }
    });

    test('未填完的乘客不會混進送出的資料', () {
      ctrl.enableMultiStop();
      ctrl.addPassenger();
      ctrl.setPassengerPoint(0, pickup: p(1), dropoff: p(2));
      ctrl.setPassengerPoint(1, pickup: p(3)); // B 只有上車

      final stops = buildStops(ctrl.passengers);
      expect(stops.every((s) => s.passengerLabel == 'A'), isTrue);
    });
  });

}

class _StopsFakeApi extends CustomerApiClient {
  _StopsFakeApi() : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  List<StopInput> lastStops = const [];
  int createCalls = 0;

  @override
  void setToken(String? token) {}

  @override
  Future<CustomerLoginResult> login({
    required String lineUserId,
    required String password,
  }) async =>
      const CustomerLoginResult(customerId: 1, token: 'tok-1', name: '小美');

  @override
  Future<CustomerRide?> activeRide() async => null;

  @override
  Future<List<LostItemRequest>> fetchLostItems() async => const [];

  @override
  Future<int> fetchPetCleaningFeeBps() async => 2000;

  @override
  Future<CustomerRide> createRide({
    required double pickupLat,
    required double pickupLng,
    required String pickupAddress,
    String? dropoffAddress,
    double? dropoffLat,
    double? dropoffLng,
    String? requiredVehicleType,
    List<StopInput> stops = const [],
  }) async {
    createCalls++;
    lastStops = stops;
    return CustomerRide.fromJson({'ride_id': 1, 'status': 0});
  }
}

class _MemoryCustomerStorage extends CustomerTokenStorage {
  CustomerSession? _saved;

  @override
  Future<CustomerSession?> read() async => _saved;

  @override
  Future<void> save(CustomerSession session) async => _saved = session;

  @override
  Future<void> clear() async => _saved = null;
}
