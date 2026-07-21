import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/fleet_api_client.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/storage/token_storage.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/driver/driver_controller.dart';
import 'package:line_fleet_app/driver/screens/driver_vehicle_screen.dart';
import 'package:provider/provider.dart';

void main() {
  group('VehicleType（O1 車種 code ↔ 顯示名）', () {
    test('code 解析與顯示名', () {
      expect(VehicleType.fromCode('pet'), VehicleType.pet);
      expect(VehicleType.pet.label, '寵物用車');
      expect(VehicleType.labelOf('accessible'), '無障礙車');
    });

    test('未知 code 不崩潰也不露出原始 code', () {
      // 後端日後新增車種而 App 尚未更新時，寧可顯示 fallback。
      expect(VehicleType.fromCode('spaceship'), isNull);
      expect(VehicleType.fromCode(''), isNull);
      expect(VehicleType.fromCode(null), isNull);
      expect(VehicleType.labelOf('spaceship'), '—');
      expect(VehicleType.labelOf(null, fallback: '未設定'), '未設定');
    });

    test('code 值必須與後端白名單一致（送錯後端會 400）', () {
      expect(
        VehicleType.values.map((v) => v.code).toList(),
        ['sedan', 'suv', 'van7', 'accessible', 'pet'],
      );
    });
  });

  group('DriverVehicle', () {
    test('以後端的 has_vehicle 為準，不自行判斷兩欄非空', () {
      // 與 O3 gate 同一條件；App 自行判斷會與後端分歧。
      final v = DriverVehicle.fromJson(
        {'vehicle_type': 'pet', 'plate_number': 'PET-0001', 'has_vehicle': true},
      );
      expect(v.hasVehicle, isTrue);
      expect(v.type, VehicleType.pet);

      final empty = DriverVehicle.fromJson(
        {'vehicle_type': '', 'plate_number': '', 'has_vehicle': false},
      );
      expect(empty.hasVehicle, isFalse);
      expect(empty.type, isNull);
    });

    test('審核狀態（O5）：review_status/can_accept 解析', () {
      final pending = DriverVehicle.fromJson({
        'vehicle_type': 'sedan', 'plate_number': 'ABC-1234',
        'has_vehicle': true, 'review_status': 'pending', 'can_accept': false,
      });
      expect(pending.reviewStatus, VehicleReviewStatus.pending);
      expect(pending.canAccept, isFalse);

      final rejected = DriverVehicle.fromJson({
        'vehicle_type': 'sedan', 'plate_number': 'ABC-1234',
        'has_vehicle': true, 'review_status': 'rejected',
        'review_note': '車牌照片模糊', 'can_accept': false,
      });
      expect(rejected.reviewStatus, VehicleReviewStatus.rejected);
      expect(rejected.reviewNote, '車牌照片模糊');

      final approved = DriverVehicle.fromJson({
        'vehicle_type': 'sedan', 'plate_number': 'ABC-1234',
        'has_vehicle': true, 'review_status': 'approved', 'can_accept': true,
      });
      expect(approved.reviewStatus, VehicleReviewStatus.approved);
      expect(approved.canAccept, isTrue);
    });

    test('未知/缺 review_status → none；舊後端無 can_accept → 退回 has_vehicle', () {
      // 後端日後新增狀態而 App 未更新 → none（走設定頁，不誤判可接單）。
      final unknown = DriverVehicle.fromJson({
        'vehicle_type': 'sedan', 'plate_number': 'A', 'has_vehicle': true,
        'review_status': 'future_state',
      });
      expect(unknown.reviewStatus, VehicleReviewStatus.none);
      // 舊後端沒有 can_accept 欄位 → 退回 has_vehicle（維持 O3 語意，不誤鎖）。
      expect(unknown.canAccept, isTrue);
    });
  });

  group('DriverController 車輛狀態（O2／O3）', () {
    late _VehicleFakeApi api;
    late DriverController ctrl;

    setUp(() {
      api = _VehicleFakeApi();
      ctrl = DriverController(
        storage: MemoryDriverAuthStore(),
        api: api,
        wsFactory: FleetWsClient.silent,
      );
    });

    tearDown(() => ctrl.dispose());

    test('登入前 vehicleChecked=false（還不知道，不是沒填）', () async {
      await ctrl.init();
      expect(ctrl.vehicleChecked, isFalse);
      expect(ctrl.hasVehicle, isFalse);
    });

    test('登入後自動載入車輛', () async {
      api.vehicle = const DriverVehicle(
        vehicleType: 'pet',
        plateNumber: 'PET-0001',
        hasVehicle: true,
      );
      await ctrl.init();
      await ctrl.login(lineUserId: 'U', password: 'pw');

      expect(ctrl.vehicleChecked, isTrue);
      expect(ctrl.hasVehicle, isTrue);
      expect(ctrl.vehicle?.type, VehicleType.pet);
    });

    test('審核狀態 getter（O5）：pending/rejected/approved 對映 _DriverRoot 四態', () async {
      // pending → 審核中畫面；rejected → 已退回（帶原因）；approved → 首頁。
      api.vehicle = const DriverVehicle(
        vehicleType: 'sedan', plateNumber: 'ABC-1234', hasVehicle: true,
        reviewStatus: VehicleReviewStatus.rejected,
        reviewNote: '車牌照片模糊', canAccept: false,
      );
      await ctrl.init();
      await ctrl.login(lineUserId: 'U', password: 'pw');

      expect(ctrl.hasVehicle, isTrue, reason: '填了但');
      expect(ctrl.vehicleReviewStatus, VehicleReviewStatus.rejected);
      expect(ctrl.canAcceptRides, isFalse, reason: '未核准不得接單');
      expect(ctrl.vehicleReviewNote, '車牌照片模糊');
    });

    test('查詢失敗時維持「未載入」，不可誤判成沒填', () async {
      // 網路錯誤把司機推去強制設定頁，等於因為連線問題就宣告他不能接單。
      api.vehicleError = ApiException('連線失敗');
      await ctrl.init();
      await ctrl.login(lineUserId: 'U', password: 'pw');

      expect(ctrl.vehicleChecked, isFalse);
      expect(ctrl.error, '連線失敗');
    });

    test('查詢失敗要能被 UI 分辨（否則卡在無限 spinner）', () async {
      // 模擬器實跑抓到的真 bug：舊 session 對新後端無效 → 查詢失敗 →
      // vehicleChecked 永遠 false → _DriverRoot 永遠轉圈 → 司機連登出都按不到。
      // 「尚未查」與「查失敗」都是 vehicleChecked==false，但 UI 後果天差地遠。
      api.vehicleError = ApiException('找不到司機');
      await ctrl.init();
      await ctrl.login(lineUserId: 'U', password: 'pw');

      expect(ctrl.vehicleLoadFailed, isTrue);
      expect(ctrl.vehicleChecked, isFalse);
    });

    test('重試成功後清除失敗狀態', () async {
      api.vehicleError = ApiException('連線失敗');
      await ctrl.init();
      await ctrl.login(lineUserId: 'U', password: 'pw');
      expect(ctrl.vehicleLoadFailed, isTrue);

      api.vehicleError = null;
      await ctrl.refreshVehicle();

      expect(ctrl.vehicleLoadFailed, isFalse);
      expect(ctrl.vehicleChecked, isTrue);
      expect(ctrl.error, isNull);
    });

    test('儲存後以後端回傳值為準（車牌已正規化）', () async {
      await ctrl.init();
      await ctrl.login(lineUserId: 'U', password: 'pw');

      final ok = await ctrl.saveVehicle(vehicleType: 'pet', plateNumber: ' pet-0001 ');
      expect(ok, isTrue);
      // 送出去的是小寫帶空白，存下來的必須是後端正規化後的值。
      expect(ctrl.vehicle?.plateNumber, 'PET-0001');
      expect(ctrl.hasVehicle, isTrue);
    });

    test('車牌重複（409）→ 回 false 並顯示後端訊息', () async {
      await ctrl.init();
      await ctrl.login(lineUserId: 'U', password: 'pw');

      api.vehicleError = ApiException('此車牌已被其他司機使用');
      final ok = await ctrl.saveVehicle(vehicleType: 'sedan', plateNumber: 'DUP-0001');
      expect(ok, isFalse);
      expect(ctrl.error, '此車牌已被其他司機使用');
    });
  });

  group('聯絡電話（乘客端撥號按鈕的資料來源）', () {
    testWidgets('儲存電話走 profile 端點，不動車輛審核狀態', (tester) async {
      // 這是本功能存在的理由：改電話若走 PUT /driver/vehicle，
      // 後端會把審核重置為 pending，司機每改一次號碼就被鎖出接單（O5 gate）。
      final api = _VehicleFakeApi()
        ..vehicle = const DriverVehicle(
          vehicleType: 'sedan',
          plateNumber: 'ABC-1234',
          hasVehicle: true,
          reviewStatus: VehicleReviewStatus.approved,
          canAccept: true,
        );
      final ctrl = DriverController(
        storage: MemoryDriverAuthStore(),
        api: api,
        wsFactory: FleetWsClient.silent,
      );
      addTearDown(ctrl.dispose);
      await ctrl.init();
      await ctrl.login(lineUserId: 'U', password: 'pw');
      expect(ctrl.canAcceptRides, isTrue, reason: '前置：這位司機原本已核准可接單');

      await tester.pumpWidget(
        ChangeNotifierProvider<DriverController>.value(
          value: ctrl,
          child: const MaterialApp(home: DriverVehicleScreen()),
        ),
      );
      await tester.pump();

      await tester.enterText(
        find.widgetWithText(TextFormField, '電話（選填）'),
        '0912-345-678',
      );
      await tester.tap(find.text('儲存聯絡電話'));
      await tester.pumpAndSettle();

      expect(api.savedPhones, ['0912-345-678']);
      // 沒有碰到車輛端點——否則審核會被重置。
      expect(api.savedVehicles, isEmpty);
      expect(ctrl.vehicleReviewStatus, VehicleReviewStatus.approved);
      expect(ctrl.canAcceptRides, isTrue);
      expect(ctrl.hasPhone, isTrue);
    });

    testWidgets('留空代表清除號碼，不被必填擋下', (tester) async {
      // 司機不想公開號碼時要有辦法收回；乘客端隨之不顯示撥號按鈕。
      final api = _VehicleFakeApi()
        ..profile = const DriverProfile(
          driverId: 1,
          name: '測試司機',
          phone: '0912345678',
        );
      final ctrl = DriverController(
        storage: MemoryDriverAuthStore(),
        api: api,
        wsFactory: FleetWsClient.silent,
      );
      addTearDown(ctrl.dispose);
      // 走正式路徑載入 profile（login 後會 refreshProfile），欄位才會帶出既有號碼。
      await ctrl.init();
      await ctrl.login(lineUserId: 'U', password: 'pw');
      expect(ctrl.hasPhone, isTrue, reason: '前置：欄位應帶出既有號碼');

      await tester.pumpWidget(
        ChangeNotifierProvider<DriverController>.value(
          value: ctrl,
          child: const MaterialApp(home: DriverVehicleScreen()),
        ),
      );
      await tester.pump();

      await tester.enterText(
        find.widgetWithText(TextFormField, '電話（選填）'),
        '',
      );
      await tester.tap(find.text('儲存聯絡電話'));
      await tester.pumpAndSettle();

      expect(api.savedPhones, ['']);
      expect(ctrl.hasPhone, isFalse);
    });

    testWidgets('太短的號碼在本地就擋下，不送出', (tester) async {
      final api = _VehicleFakeApi();
      final ctrl = DriverController(
        storage: MemoryDriverAuthStore(),
        api: api,
        wsFactory: FleetWsClient.silent,
      );
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<DriverController>.value(
          value: ctrl,
          child: const MaterialApp(home: DriverVehicleScreen()),
        ),
      );
      await tester.pump();

      await tester.enterText(
        find.widgetWithText(TextFormField, '電話（選填）'),
        '12345',
      );
      await tester.tap(find.text('儲存聯絡電話'));
      await tester.pumpAndSettle();

      expect(find.text('電話長度不足'), findsOneWidget);
      expect(api.savedPhones, isEmpty);
    });
  });

  group('DriverVehicleScreen（強制情境）', () {
    testWidgets('強制情境沒有返回鍵，且顯示提示', (tester) async {
      final api = _VehicleFakeApi()
        ..vehicle = const DriverVehicle(
          vehicleType: '',
          plateNumber: '',
          hasVehicle: false,
        );
      final ctrl = DriverController(
        storage: MemoryDriverAuthStore(),
        api: api,
        wsFactory: FleetWsClient.silent,
      );
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<DriverController>.value(
          value: ctrl,
          child: const MaterialApp(home: DriverVehicleScreen(mandatory: true)),
        ),
      );
      await tester.pump();

      expect(find.text('請先填寫車種與車牌，填完才能開始接單。'), findsOneWidget);
      // 沒填車輛回首頁也無法接單（後端 O3 會 409），所以不給返回。
      expect(find.byType(BackButton), findsNothing);
    });

    testWidgets('未選車種時擋下儲存', (tester) async {
      final api = _VehicleFakeApi()
        ..vehicle = const DriverVehicle(
          vehicleType: '',
          plateNumber: '',
          hasVehicle: false,
        );
      final ctrl = DriverController(
        storage: MemoryDriverAuthStore(),
        api: api,
        wsFactory: FleetWsClient.silent,
      );
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(
        ChangeNotifierProvider<DriverController>.value(
          value: ctrl,
          child: const MaterialApp(home: DriverVehicleScreen(mandatory: true)),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('儲存車輛資訊'));
      await tester.pump();

      expect(find.text('請選擇車種'), findsOneWidget);
      expect(find.text('請輸入車牌'), findsOneWidget);
      expect(api.savedVehicles, isEmpty);
    });
  });
}

class _VehicleFakeApi extends FleetApiClient {
  _VehicleFakeApi() : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  DriverVehicle vehicle = const DriverVehicle(
    vehicleType: 'sedan',
    plateNumber: 'ABC-1234',
    hasVehicle: true,
  );
  DriverProfile profile = const DriverProfile(
    driverId: 1,
    name: '測試司機',
    phone: '',
  );
  ApiException? phoneError;
  final List<String> savedPhones = [];
  ApiException? vehicleError;
  final savedVehicles = <String>[];

  @override
  void setToken(String? token) {}

  @override
  Future<LoginResult> login({
    required String lineUserId,
    required String password,
  }) async =>
      const LoginResult(driverId: 7, token: 'tok-7', name: '阿明');

  @override
  Future<ActiveRide?> activeRide() async => null;

  @override
  Future<List<LostItemRequest>> fetchLostItems() async => const [];

  @override
  Future<DriverVehicle> fetchVehicle() async {
    if (vehicleError != null) throw vehicleError!;
    return vehicle;
  }

  // init()／login() 也會呼叫 fetchProfile，Fake 沒覆蓋就會打真網路卡死 FakeAsync。
  @override
  Future<DriverProfile> fetchProfile() async => profile;

  @override
  Future<DriverProfile> updatePhone(String phone) async {
    if (phoneError != null) throw phoneError!;
    savedPhones.add(phone);
    profile = DriverProfile(driverId: 1, name: '測試司機', phone: phone.trim());
    return profile;
  }

  @override
  Future<DriverVehicle> updateVehicle({
    required String vehicleType,
    required String plateNumber,
  }) async {
    if (vehicleError != null) throw vehicleError!;
    savedVehicles.add('$vehicleType/$plateNumber');
    vehicle = DriverVehicle(
      vehicleType: vehicleType,
      plateNumber: plateNumber.replaceAll(' ', '').toUpperCase(),
      hasVehicle: true,
    );
    return vehicle;
  }
}
