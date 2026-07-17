import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/customer_api_client.dart';
import 'package:line_fleet_app/core/api/fleet_api_client.dart' show ApiException;
import 'package:line_fleet_app/core/config/app_config.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/storage/customer_token_storage.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/customer/customer_controller.dart';

void main() {
  late _VehicleFakeApi api;
  late CustomerController ctrl;

  setUp(() {
    api = _VehicleFakeApi();
    ctrl = CustomerController(
      storage: _MemoryCustomerStorage(),
      api: api,
      wsFactory: FleetWsClient.silent,
    );
  });

  tearDown(() => ctrl.dispose());

  group('車種選擇與清潔費預告（P2／P5）', () {
    test('預設不指定車種', () {
      expect(ctrl.requiredVehicleType, isNull);
    });

    test('選寵物車 → 自動查費率並快取', () async {
      api.petFeeBps = 2000;
      await ctrl.setRequiredVehicleType(VehicleType.pet);

      expect(ctrl.requiredVehicleType, VehicleType.pet);
      expect(ctrl.petCleaningFeeBps, 2000);
      expect(api.feeCallCount, 1);

      // 費率不常變，已查過就不再打 API。
      await ctrl.setRequiredVehicleType(VehicleType.sedan);
      await ctrl.setRequiredVehicleType(VehicleType.pet);
      expect(api.feeCallCount, 1);
    });

    test('選其他車種不查費率（只有寵物車會加價）', () async {
      await ctrl.setRequiredVehicleType(VehicleType.accessible);
      expect(api.feeCallCount, 0);
    });

    test('查費率失敗 → 靜默降級，不擋叫車也不顯示錯誤', () async {
      // UI 會顯示「上限 30%」的保守說明；因為查費率失敗就不能叫車是不可接受的。
      api.feeError = ApiException('連線失敗');
      await ctrl.setRequiredVehicleType(VehicleType.pet);

      expect(ctrl.requiredVehicleType, VehicleType.pet);
      expect(ctrl.petCleaningFeeBps, isNull);
      expect(ctrl.error, isNull);
    });
  });

  group('ride.accepted 帶司機車輛與電話（O4／O7）', () {
    test('解析車種車牌電話', () async {
      await ctrl.init();
      await ctrl.login(lineUserId: 'U', password: 'pw');
      ctrl.setActiveRideForTest(_ride(1));

      ctrl.handleWsEventForTest(FleetWsEvent(
        type: FleetEventTypes.rideAccepted,
        rideId: 1,
        payload: const {
          'driver_name': '王司機',
          'driver_vehicle_type': 'pet',
          'driver_plate_number': 'PET-0001',
          'driver_phone': '0912345678',
          'eta_sec': 300,
        },
      ));

      expect(ctrl.driverName, '王司機');
      expect(ctrl.driverInfo?.type, VehicleType.pet);
      expect(ctrl.driverInfo?.plateNumber, 'PET-0001');
      expect(ctrl.driverInfo?.phone, '0912345678');
    });
  });

  group('ride.cancelled 取消原因（P4）', () {
    test('指定車種找不到 → 帶 no_vehicle_of_type 與車種', () async {
      await ctrl.init();
      await ctrl.login(lineUserId: 'U', password: 'pw');
      ctrl.setActiveRideForTest(_ride(1));

      ctrl.handleWsEventForTest(FleetWsEvent(
        type: FleetEventTypes.rideCancelled,
        rideId: 1,
        payload: const {
          'cancel_reason': 'no_vehicle_of_type',
          'required_vehicle_type': 'pet',
        },
      ));

      expect(ctrl.cancelReason, CancelReason.noVehicleOfType);
      expect(ctrl.cancelledVehicleType, 'pet');
      expect(cancelMessage(ctrl.cancelReason, ctrl.cancelledVehicleType), contains('寵物用車'));
    });

    test('乘客主動取消不帶 cancel_reason → null（UI 須容忍缺席）', () async {
      await ctrl.init();
      await ctrl.login(lineUserId: 'U', password: 'pw');
      ctrl.setActiveRideForTest(_ride(1));

      ctrl.handleWsEventForTest(FleetWsEvent(
        type: FleetEventTypes.rideCancelled,
        rideId: 1,
        payload: const {},
      ));

      expect(ctrl.cancelReason, isNull);
    });
  });

  group('ride.completed 清潔費分項（O6）', () {
    test('有加收 → 完成卡拿得到清潔費', () async {
      await ctrl.init();
      await ctrl.login(lineUserId: 'U', password: 'pw');
      ctrl.setActiveRideForTest(_ride(1));

      ctrl.handleWsEventForTest(FleetWsEvent(
        type: FleetEventTypes.rideCompleted,
        rideId: 1,
        payload: const {'fare_amount_cents': 21500, 'cleaning_fee_cents': 4300},
      ));

      final s = ctrl.completedSummary!;
      expect(s.fareAmountCents, 21500);
      expect(s.cleaningFeeCents, 4300);
      expect(s.totalCents, 25800);
    });

    test('未加收時後端不帶鍵 → null，完成卡不顯示清潔費', () async {
      await ctrl.init();
      await ctrl.login(lineUserId: 'U', password: 'pw');
      ctrl.setActiveRideForTest(_ride(1));

      ctrl.handleWsEventForTest(FleetWsEvent(
        type: FleetEventTypes.rideCompleted,
        rideId: 1,
        payload: const {'fare_amount_cents': 21500},
      ));

      expect(ctrl.completedSummary!.hasCleaningFee, isFalse);
    });
  });
}

CustomerRide _ride(int id) => CustomerRide.fromJson({
      'ride_id': id,
      'status': 2,
      'pickup_address': '台北車站',
      'dropoff_address': '台北101',
    });

class _VehicleFakeApi extends CustomerApiClient {
  _VehicleFakeApi() : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  int petFeeBps = 2000;
  ApiException? feeError;
  int feeCallCount = 0;

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
  Future<int> fetchPetCleaningFeeBps() async {
    feeCallCount++;
    if (feeError != null) throw feeError!;
    return petFeeBps;
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
