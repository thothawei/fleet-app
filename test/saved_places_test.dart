import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/customer_api_client.dart';
import 'package:line_fleet_app/core/api/fleet_api_client.dart' show ApiException;
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/customer/customer_controller.dart';

CustomerController _loggedIn(CustomerApiClient api) {
  final ctrl = CustomerController(api: api);
  ctrl.setSessionForTest(
    const CustomerSession(customerId: 1, token: 'tok', name: '小美'),
  );
  return ctrl;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  _logoutLeakTests();
  _loginLoadsTests();

  group('常用地點', () {
    test('homePlace／workPlace 依 kind 取，不依 label', () async {
      // 乘客把住家改名成「家」之後，任何比對 label 的寫法都會無聲失效。
      final api = _PlacesApi(places: [
        _place(1, SavedPlaceKind.home, '家'),
        _place(2, SavedPlaceKind.work, '辦公室'),
        _place(3, SavedPlaceKind.custom, '住家'),
      ]);
      final ctrl = _loggedIn(api);
      await ctrl.loadSavedPlaces();

      expect(ctrl.homePlace?.id, 1);
      expect(ctrl.workPlace?.id, 2);
      // 名字叫「住家」的自訂地點不該被當成住家插槽。
      expect(ctrl.homePlace?.label, '家');
    });

    test('沒設過住家時 homePlace 為 null（UI 才知道要顯示「設定」）', () async {
      final ctrl = _loggedIn(_PlacesApi(places: []));
      await ctrl.loadSavedPlaces();
      expect(ctrl.homePlace, isNull);
      expect(ctrl.workPlace, isNull);
    });

    test('重設住家是覆蓋，不會變成兩筆 home', () async {
      // 後端對 home/work 是 upsert，回來的是**新的 id**（原本沒有住家）。
      // 若合併只比 id，清單就會同時出現兩筆 kind=home。
      final api = _PlacesApi(places: [
        _place(1, SavedPlaceKind.home, '住家', address: '舊家'),
        _place(2, SavedPlaceKind.custom, '健身房'),
      ]);
      final ctrl = _loggedIn(api);
      await ctrl.loadSavedPlaces();

      api.nextCreated = _place(1, SavedPlaceKind.home, '住家', address: '新家');
      final error = await ctrl.savePlace(
        kind: SavedPlaceKind.home,
        label: '住家',
        address: '新家',
        lat: 25.01,
        lng: 121.46,
      );

      expect(error, isNull);
      final homes = ctrl.savedPlaces.where((p) => p.isHome).toList();
      expect(homes, hasLength(1), reason: '住家只能有一筆');
      expect(homes.single.address, '新家');
      expect(ctrl.savedPlaces, hasLength(2));
    });

    test('別台裝置改過住家（後端回不同 id）→ 本地仍只留一筆', () async {
      // 這條才是「比 kind 不只比 id」真正守著的情境：
      // 這台的清單還記得住家是 id=1，但另一台裝置已經把它刪掉重建成 id=7。
      // 只比 id 的話，合併後清單會同時出現兩筆 kind=home，
      // 叫車頁的快捷列就會冒出兩顆「住家」。
      final api = _PlacesApi(places: [
        _place(1, SavedPlaceKind.home, '住家', address: '本地記得的舊家'),
        _place(2, SavedPlaceKind.custom, '健身房'),
      ]);
      final ctrl = _loggedIn(api);
      await ctrl.loadSavedPlaces();

      api.nextCreated = _place(7, SavedPlaceKind.home, '住家', address: '新家');
      await ctrl.savePlace(
        kind: SavedPlaceKind.home,
        label: '住家',
        address: '新家',
        lat: 25.01,
        lng: 121.46,
      );

      final homes = ctrl.savedPlaces.where((p) => p.isHome).toList();
      expect(homes, hasLength(1), reason: '住家只能有一筆，即使後端換了 id');
      expect(homes.single.id, 7);
      expect(homes.single.address, '新家');
      expect(ctrl.savedPlaces, hasLength(2));
    });

    test('後端給新 id 的住家也只留一筆（先前沒有住家的情況）', () async {
      final api = _PlacesApi(places: [
        _place(5, SavedPlaceKind.custom, '健身房'),
      ]);
      final ctrl = _loggedIn(api);
      await ctrl.loadSavedPlaces();

      api.nextCreated = _place(9, SavedPlaceKind.home, '住家', address: '新家');
      await ctrl.savePlace(
        kind: SavedPlaceKind.home,
        label: '住家',
        address: '新家',
        lat: 25.01,
        lng: 121.46,
      );

      expect(ctrl.savedPlaces.where((p) => p.isHome), hasLength(1));
      expect(ctrl.homePlace?.id, 9);
    });

    test('清單排序：住家 → 公司 → 其他', () async {
      final api = _PlacesApi(places: [
        _place(1, SavedPlaceKind.custom, '健身房'),
      ]);
      final ctrl = _loggedIn(api);
      await ctrl.loadSavedPlaces();

      api.nextCreated = _place(2, SavedPlaceKind.work, '公司');
      await ctrl.savePlace(
        kind: SavedPlaceKind.work,
        label: '公司',
        address: '內湖',
        lat: 25.07,
        lng: 121.57,
      );
      api.nextCreated = _place(3, SavedPlaceKind.home, '住家');
      await ctrl.savePlace(
        kind: SavedPlaceKind.home,
        label: '住家',
        address: '大安',
        lat: 25.02,
        lng: 121.54,
      );

      expect(
        ctrl.savedPlaces.map((p) => p.kind),
        [SavedPlaceKind.home, SavedPlaceKind.work, SavedPlaceKind.custom],
      );
    });

    test('刪除後從清單移除', () async {
      final api = _PlacesApi(places: [
        _place(1, SavedPlaceKind.home, '住家'),
        _place(2, SavedPlaceKind.custom, '健身房'),
      ]);
      final ctrl = _loggedIn(api);
      await ctrl.loadSavedPlaces();

      final error = await ctrl.deleteSavedPlace(2);

      expect(error, isNull);
      expect(ctrl.savedPlaces.map((p) => p.id), [1]);
    });

    test('新增失敗要把訊息回給表單，清單不動', () async {
      final api = _PlacesApi(
        places: [_place(1, SavedPlaceKind.home, '住家')],
        createThrows: ApiException('地址不可為空'),
      );
      final ctrl = _loggedIn(api);
      await ctrl.loadSavedPlaces();

      final error = await ctrl.savePlace(
        kind: SavedPlaceKind.custom,
        label: '健身房',
        address: '',
        lat: 25.0,
        lng: 121.5,
      );

      expect(error, '地址不可為空');
      expect(ctrl.savedPlaces, hasLength(1));
    });

    test('silent 載入失敗不設錯誤（叫車頁的快捷鈕載不出來不該擋叫車）', () async {
      final api = _PlacesApi(listThrows: ApiException('伺服器忙碌'));
      final ctrl = _loggedIn(api);

      await ctrl.loadSavedPlaces(silent: true);
      expect(ctrl.placesError, isNull);

      await ctrl.loadSavedPlaces();
      expect(ctrl.placesError, '伺服器忙碌');
    });
  });

  group('SavedPlace 解析', () {
    test('point 巢狀座標與 isSlot', () {
      final home = SavedPlace.fromJson(const {
        'id': 1,
        'kind': 'home',
        'label': '住家',
        'address': '台北市大安區',
        'point': {'lat': 25.0261, 'lng': 121.5435},
      });
      expect(home.lat, 25.0261);
      expect(home.lng, 121.5435);
      expect(home.isHome, isTrue);
      expect(home.isSlot, isTrue);

      final custom = SavedPlace.fromJson(const {
        'id': 2,
        'kind': 'custom',
        'label': '健身房',
        'address': '信義區',
        'point': {'lat': 25.04, 'lng': 121.56},
      });
      expect(custom.isSlot, isFalse);
    });

    test('kind 缺席時退回 custom（不能誤判成插槽）', () {
      final p = SavedPlace.fromJson(const {
        'id': 3,
        'label': '某處',
        'address': '某地址',
        'point': {'lat': 25.0, 'lng': 121.5},
      });
      expect(p.kind, SavedPlaceKind.custom);
      expect(p.isSlot, isFalse);
    });
  });
}

SavedPlace _place(int id, String kind, String label, {String address = '地址'}) =>
    SavedPlace(
      id: id,
      kind: kind,
      label: label,
      address: address,
      lat: 25.0,
      lng: 121.5,
    );

class _PlacesApi extends CustomerApiClient {
  _PlacesApi({
    this.places = const [],
    this.createThrows,
    this.listThrows,
  }) : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  List<SavedPlace> places;
  final ApiException? createThrows;
  final ApiException? listThrows;
  SavedPlace? nextCreated;

  @override
  void setToken(String? token) {}

  @override
  Future<CustomerRide?> activeRide() async => null;

  @override
  Future<List<LostItemRequest>> fetchLostItems() async => <LostItemRequest>[];

  @override
  Future<ScheduledRidesResult> fetchScheduledRides({
    bool upcomingOnly = false,
  }) async =>
      const ScheduledRidesResult(rides: [], leadMinutes: 15);

  @override
  Future<List<SavedPlace>> fetchSavedPlaces() async {
    if (listThrows != null) throw listThrows!;
    return places;
  }

  @override
  Future<SavedPlace> createSavedPlace({
    required String kind,
    required String label,
    required String address,
    required double lat,
    required double lng,
  }) async {
    if (createThrows != null) throw createThrows!;
    return nextCreated ??
        SavedPlace(
          id: 100,
          kind: kind,
          label: label,
          address: address,
          lat: lat,
          lng: lng,
        );
  }

  @override
  Future<void> deleteSavedPlace(int id) async {}

  @override
  Future<CustomerLoginResult> login({
    required String lineUserId,
    required String password,
  }) async =>
      const CustomerLoginResult(customerId: 1, token: 'tok', name: '示範乘客');
}

/// 登出後的殘留檢查。
///
/// 住家與公司是**實體位置**，預約則是行程計畫——兩者都比行程歷史更敏感，
/// 而 `_clearSession` 早就因為同樣的理由在清行程歷史了（見該處註解）。
/// 換人登入後如果沒清，下一位乘客一打開叫車頁就會看到上一位的住家地址。
void _logoutLeakTests() {
  group('登出殘留', () {
    setUp(() {
      // logout() 會清 secure storage；測試環境沒有那個 plugin，
      // 不 mock 的話會在 MissingPluginException 就中斷，根本走不到要驗的清理邏輯。
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async => null,
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        null,
      );
    });

    test('登出後不留下上一位乘客的常用地點與預約', () async {
      final api = _PlacesApi(places: [
        _place(1, SavedPlaceKind.home, '住家', address: '台北市大安區和平東路'),
        _place(2, SavedPlaceKind.work, '公司', address: '內湖瑞光路'),
      ]);
      final ctrl = _loggedIn(api);
      await ctrl.loadSavedPlaces();
      await ctrl.loadScheduledRides();

      expect(ctrl.savedPlaces, isNotEmpty, reason: '前置條件：載進來了');

      await ctrl.logout();

      expect(
        ctrl.savedPlaces,
        isEmpty,
        reason: '住家地址是實體位置，換人登入不能還看得到',
      );
      expect(ctrl.homePlace, isNull);
      expect(ctrl.workPlace, isNull);
      expect(ctrl.scheduledRides, isEmpty);
      expect(ctrl.upcomingSchedules, isEmpty);
    });
  });
}

/// 登入之後也要把常用地點與預約帶出來。
///
/// `init()`（冷啟動還原 session）有載，登入路徑卻沒有——乘客剛登入完，
/// 叫車頁的快捷列是空的、首頁也看不到自己的預約，要等下次冷啟動才會出現。
/// **這是模擬器實跑才抓到的**：單元測試都用 setSessionForTest 再手動呼叫 load，
/// 永遠走不到登入那條路徑。
void _loginLoadsTests() {
  group('登入後的載入', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async => null,
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        null,
      );
    });

    test('登入成功 → 常用地點與預約都帶出來（比照 init()）', () async {
      final api = _PlacesApi(places: [
        _place(1, SavedPlaceKind.home, '住家'),
        _place(2, SavedPlaceKind.work, '公司'),
      ]);
      final ctrl = CustomerController(api: api);

      await ctrl.login(lineUserId: 'demo-customer-1', password: 'demo123456');

      expect(ctrl.isLoggedIn, isTrue, reason: '前置條件：登入要成功');
      expect(
        ctrl.savedPlaces,
        isNotEmpty,
        reason: '登入完叫車頁的快捷列就該有東西，不該等下次冷啟動',
      );
      expect(ctrl.homePlace, isNotNull);
    });
  });
}
