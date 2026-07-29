import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:line_fleet_app/core/api/api_error.dart';
import 'package:line_fleet_app/core/api/customer_api_client.dart';
import 'package:line_fleet_app/core/api/fleet_api_client.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/storage/customer_token_storage.dart';
import 'package:line_fleet_app/core/storage/token_storage.dart';
import 'package:line_fleet_app/core/theme/app_theme.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/customer/customer_controller.dart';
import 'package:line_fleet_app/customer/screens/customer_login_screen.dart';
import 'package:line_fleet_app/driver/driver_controller.dart';
import 'package:provider/provider.dart';

/// 後端 JWT 預設 72 小時（dispatch `JWT_EXPIRY_HOURS`），過期後**每一支**帶 token 的
/// API 都回 401 `{"error":"token 無效或已過期"}`（已用過期 token 對真後端實測）。
/// 這組測試釘住「App 收到它之後要做什麼」：清掉 session、回登入頁、說人話。
void main() {
  group('API client：401 ＝ session 失效', () {
    test('帶 token 的請求收到 401 → 觸發 onUnauthorized，訊息換成可行動的一句話', () async {
      var called = 0;
      final api = FleetApiClient(dio: _dio(_ExpiredAdapter()))
        ..onUnauthorized = () => called++;

      await expectLater(
        api.fetchVehicle(),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', sessionExpiredMessage)
            .having((e) => e.statusCode, 'statusCode', 401)),
      );
      expect(called, 1);
      // 後端原文是給開發者看的，不可原樣丟到司機畫面上。
      expect(sessionExpiredMessage, isNot(contains('token')));
    });

    test('登入端點的 401 ＝ 帳號或密碼錯誤，不可當成 session 失效', () async {
      var called = 0;
      final api = FleetApiClient(
        dio: _dio(_ExpiredAdapter(body: {'error': '帳號或密碼錯誤'})),
      )..onUnauthorized = () => called++;

      await expectLater(
        api.login(lineUserId: 'u', password: 'bad'),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', '帳號或密碼錯誤')),
      );
      // 打錯密碼被「登出」等於把使用者踢出一個他本來就沒進去的地方。
      expect(called, 0);
    });

    test('乘客端同一條規則', () async {
      var called = 0;
      final api = CustomerApiClient(dio: _dio(_ExpiredAdapter()))
        ..onUnauthorized = () => called++;

      await expectLater(api.activeRide(), throwsA(isA<ApiException>()));
      expect(called, 1);

      called = 0;
      await expectLater(
        api.register(lineUserId: 'u', name: 'n', password: 'p'),
        throwsA(isA<ApiException>()),
      );
      expect(called, 0);
    });

    test('401 以外的錯誤不動 session（409 業務錯誤照常顯示後端文案）', () async {
      var called = 0;
      final api = FleetApiClient(
        dio: _dio(_ExpiredAdapter(status: 409, body: {'error': '此行程已完成'})),
      )..onUnauthorized = () => called++;

      await expectLater(
        api.completeRide(1),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', '此行程已完成')),
      );
      expect(called, 0);
    });
  });

  group('司機端：token 過期後不能繼續假裝已登入', () {
    test('冷啟動還原到過期 session → 落回登入頁並說明原因', () async {
      final storage = MemoryDriverAuthStore()
        ..save(const AuthSession(driverId: 7, token: 'expired', name: '阿明'));
      final adapter = _ExpiredAdapter();
      final ctrl = DriverController(
        storage: storage,
        api: FleetApiClient(dio: _dio(adapter)),
        wsFactory: FleetWsClient.silent,
      );
      addTearDown(ctrl.dispose);

      await ctrl.init();
      await _settle();

      expect(ctrl.isLoggedIn, isFalse, reason: 'session 失效就不該再顯示首頁');
      expect(ctrl.error, sessionExpiredMessage);
      expect(await storage.read(), isNull, reason: '過期的 token 留著只會下次再失敗一輪');
      // 車輛狀態屬於上一個 session：留著會讓下一個登入的司機先看到別人的審核狀態。
      expect(ctrl.vehicleChecked, isFalse);
      expect(ctrl.vehicleLoadFailed, isFalse);
      // token 已失效，註銷推播 token 只會再換一個 401 回來。
      expect(adapter.paths.where((p) => p.contains('device-token')), isEmpty);
    });

    // 這是最容易被忽略的一種：token 是在 App 執行期間過期的，還原時一切正常，
    // 之後才開始每一次位置回報都被擋下——而畫面照樣顯示「上線中／等待派單中」。
    test('上線後 token 過期：位置回報 401 → 下線並登出，不留在「等待派單中」', () async {
      final storage = MemoryDriverAuthStore()
        ..save(const AuthSession(driverId: 7, token: 'about-to-expire'));
      // 還原路徑全部正常，只有位置回報吃到 401（token 剛好在上線後過期）。
      final adapter = _RoutedAdapter(
        routes: {
          '/driver/rides/active': _Res(200, const {}),
          '/driver/lost-items': _Res(200, const {'lost_items': []}),
          '/driver/vehicle': _Res(200, const {
            'vehicle_type': 'sedan',
            'plate_number': 'ABC-1234',
            'has_vehicle': true,
            'review_status': 'approved',
            'can_accept': true,
          }),
        },
      );
      final ctrl = DriverController(
        storage: storage,
        api: FleetApiClient(dio: _dio(adapter)),
        wsFactory: FleetWsClient.silent,
      );
      addTearDown(ctrl.dispose);

      await ctrl.init();
      await _settle();
      expect(ctrl.isLoggedIn, isTrue, reason: '還原當下 token 還有效');
      expect(ctrl.vehicleChecked, isTrue);

      ctrl.setOnlineForTest(true);
      await ctrl.reportPositionForTest(_fakePosition());
      await _settle();

      expect(ctrl.isLoggedIn, isFalse);
      expect(ctrl.online, isFalse, reason: '沒被後端收下的位置＝不在派單池，不可繼續顯示上線中');
      expect(ctrl.error, sessionExpiredMessage);
    });

    test('並發 401 只清一次 session（輪番失敗不重入）', () async {
      final storage = MemoryDriverAuthStore()
        ..save(const AuthSession(driverId: 7, token: 'expired'));
      final adapter = _ExpiredAdapter();
      final ctrl = DriverController(
        storage: storage,
        api: FleetApiClient(dio: _dio(adapter)),
        wsFactory: FleetWsClient.silent,
      );
      addTearDown(ctrl.dispose);

      await ctrl.init();
      await _settle();

      final afterInit = adapter.paths.length;
      // 已登出後再打，一律早退，不會再送任何請求。
      await ctrl.refreshVehicle();
      await ctrl.refreshLostItems();
      await _settle();
      expect(adapter.paths.length, afterInit);
      expect(ctrl.error, sessionExpiredMessage);
    });
  });

  group('乘客端：token 過期後不能停在叫車畫面', () {
    test('冷啟動還原到過期 session → 落回登入頁並說明原因', () async {
      final storage = _MemoryCustomerStorage()
        ..save(const CustomerSession(customerId: 3, token: 'expired'));
      final ctrl = CustomerController(
        storage: storage,
        api: CustomerApiClient(dio: _dio(_ExpiredAdapter())),
        wsFactory: FleetWsClient.silent,
      );
      addTearDown(ctrl.dispose);

      await ctrl.init();
      await _settle();

      expect(ctrl.isLoggedIn, isFalse);
      expect(ctrl.error, sessionExpiredMessage);
      expect(await storage.read(), isNull);
    });

    // 清掉 session 只做對了一半：使用者要在**看得到的地方**知道發生什麼事。
    // 登入頁本來就會顯示 controller 的 error，這裡釘住那條接線不被拆掉。
    testWidgets('過期後的登入頁把原因顯示出來（不是設了沒人讀）', (tester) async {
      // 這裡用覆寫方法的 fake（行為與真 client 在 401 時完全相同，見上方 client 層測試）：
      // 真 Dio 的逾時 timer 在 testWidgets 的 fake async 下不會前進，會讓測試掛住。
      final ctrl = CustomerController(
        storage: _MemoryCustomerStorage()
          ..save(const CustomerSession(customerId: 3, token: 'expired')),
        api: _ExpiredCustomerApi(),
        wsFactory: FleetWsClient.silent,
      );
      addTearDown(ctrl.dispose);

      await ctrl.init();

      await tester.pumpWidget(
        ChangeNotifierProvider<CustomerController>.value(
          value: ctrl,
          child: MaterialApp(
            theme: appLightTheme,
            home: const CustomerLoginScreen(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text(sessionExpiredMessage), findsOneWidget);
    });

    test('登出清掉歷史行程（換人登入不該先看到上一位乘客的行程）', () async {
      final ctrl = CustomerController(
        storage: _MemoryCustomerStorage(),
        api: _HistoryApi(),
        wsFactory: FleetWsClient.silent,
      );
      addTearDown(ctrl.dispose);

      await ctrl.login(lineUserId: 'u', password: 'p');
      await ctrl.loadRideHistory();
      expect(ctrl.rideHistory, hasLength(1));

      await ctrl.logout();
      expect(ctrl.rideHistory, isEmpty);
    });
  });
}

Dio _dio(HttpClientAdapter adapter) => Dio(
      BaseOptions(baseUrl: 'http://test.invalid/api'),
    )..httpClientAdapter = adapter;

/// 讓事件迴圈跑完：session 失效的清理是 unawaited 的背景鏈（回呼由 dio 同步觸發，
/// 清理本身要 await storage／WS）。
Future<void> _settle() => Future<void>.delayed(Duration.zero);

/// 固定回同一個狀態碼的假後端；預設模仿真後端過期 token 的回應
/// （實測：`{"error":"token 無效或已過期"}` + 401）。
class _ExpiredAdapter implements HttpClientAdapter {
  _ExpiredAdapter({
    this.status = 401,
    this.body = const {'error': 'token 無效或已過期'},
  });

  final int status;
  final Map<String, dynamic> body;
  final paths = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 依路徑分流的假後端：列出來的路徑照常回應，其餘一律 401（模擬「token 在
/// 使用期間過期」——還原時拿到的資料是有效的，之後的每一次呼叫才開始被擋）。
class _RoutedAdapter implements HttpClientAdapter {
  _RoutedAdapter({required this.routes});

  final Map<String, _Res> routes;
  final paths = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    final res = routes[options.path] ??
        _Res(401, const {'error': 'token 無效或已過期'});
    return ResponseBody.fromString(
      jsonEncode(res.body),
      res.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _Res {
  const _Res(this.status, this.body);

  final int status;
  final Map<String, dynamic> body;
}

Position _fakePosition() => Position(
      latitude: 25.03,
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

/// 還原 session 時就撞上 401 的 fake：複製真 client 在 401 的兩個動作
/// （通知 controller ＋ 換成可行動的訊息）。
class _ExpiredCustomerApi extends CustomerApiClient {
  _ExpiredCustomerApi()
      : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  @override
  void setToken(String? token) {}

  @override
  Future<CustomerRide?> activeRide() async {
    onUnauthorized?.call();
    throw ApiException(sessionExpiredMessage, statusCode: 401);
  }

  @override
  Future<List<LostItemRequest>> fetchLostItems() async => const [];
}

class _HistoryApi extends CustomerApiClient {
  _HistoryApi() : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  @override
  void setToken(String? token) {}

  @override
  Future<CustomerLoginResult> login({
    required String lineUserId,
    required String password,
  }) async =>
      const CustomerLoginResult(customerId: 3, token: 'tok', name: '小美');

  @override
  Future<CustomerRide?> activeRide() async => null;

  @override
  Future<List<LostItemRequest>> fetchLostItems() async => const [];

  @override
  Future<List<CustomerRideSummary>> fetchRideHistory({int limit = 20}) async => [
        CustomerRideSummary.fromJson(const {
          'id': 9,
          'status': 4,
          'fare_amount_cents': 21200,
          'driver_name': '阿明',
        }),
      ];
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
