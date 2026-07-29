import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/fleet_api_client.dart';
import 'package:line_fleet_app/core/config/app_config.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/storage/token_storage.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/driver/driver_controller.dart';

/// 同一張派單會**同時**送給多位司機（後端 `dispatchRound` 一輪送給半徑內每一位待命司機），
/// 而同帳號的每一台裝置也都會收到（Hub 依 (角色, id) 扇出）。以下行為都是對真後端實測的：
///
/// - A、B 兩位司機同時收到 `ride.assigned`；
/// - A 接單成功後，**只有 A 的每一條連線**收到 `ride.accepted`，B 收到零個事件；
/// - B 打 accept 拿到的是 **HTTP 200** `{"message":"手慢了，這單已被其他司機接走"}`——不是錯誤碼。
///
/// 最後一條是這組測試的重點：App 若只看「有沒有丟例外」，沒搶到的司機會拿到一張
/// 完整但**假的**行程卡。
void main() {
  group('搶輸別人：後端回 200 但沒接到', () {
    test('不可顯示行程卡，接單卡要收掉，並把後端那句話說給司機聽', () async {
      final api = _OfferApi()
        ..acceptMessage = '手慢了，這單已被其他司機接走'
        ..activeAfterAccept = null; // 後端：這張單不是你的
      final ctrl = await _loggedIn(api);
      addTearDown(ctrl.dispose);

      ctrl.handleWsEventForTest(_assigned(11));
      expect(ctrl.pendingOffer?.rideId, 11);

      await ctrl.acceptOffer();

      expect(ctrl.activeRide, isNull,
          reason: '沒接到卻顯示行程卡＝司機會開去接一個不存在的乘客');
      expect(ctrl.pendingOffer, isNull, reason: '單已被接走，接單卡留著只會讓他再按一次');
      expect(ctrl.error, '手慢了，這單已被其他司機接走');
    });

    test('接單成功時以後端的 active 為準（樂觀 offer 缺的 stops 會被補齊）', () async {
      final api = _OfferApi()
        ..acceptMessage = '接單成功'
        ..activeAfterAccept = ActiveRide.fromBackendJson(const {
          'id': 11,
          'status': RideStatus.accepted,
          'pickup_address': '台北市信義區市府路1號',
          'stops': [
            {
              'id': 1,
              'ride_id': 11,
              'seq': 1,
              'kind': 'pickup',
              'passenger_label': 'A',
              'address': '台北101',
            },
          ],
        });
      final ctrl = await _loggedIn(api);
      addTearDown(ctrl.dispose);

      ctrl.handleWsEventForTest(_assigned(11));
      await ctrl.acceptOffer();

      expect(ctrl.activeRide?.rideId, 11);
      expect(ctrl.activeRide?.stops, hasLength(1));
      expect(ctrl.error, isNull);
    });

    test('重讀 active 失敗（網路）不可誤判成沒接到', () async {
      final api = _OfferApi()
        ..acceptMessage = '接單成功'
        ..activeError = ApiException('無法連線到伺服器，請檢查網路');
      final ctrl = await _loggedIn(api);
      addTearDown(ctrl.dispose);

      ctrl.handleWsEventForTest(_assigned(11));
      await ctrl.acceptOffer();

      expect(ctrl.activeRide?.rideId, 11,
          reason: '不知道就不要亂改——把剛接到的單清掉比留著更糟');
      expect(ctrl.error, isNull);
    });
  });

  group('同帳號多裝置', () {
    test('另一台裝置接走同一張單 → 接單卡消失，並自動帶出同一張行程', () async {
      final api = _OfferApi()
        ..activeAfterAccept = ActiveRide.fromBackendJson(const {
          'id': 11,
          'status': RideStatus.accepted,
          'pickup_address': '台北市信義區市府路1號',
        });
      final ctrl = await _loggedIn(api);
      addTearDown(ctrl.dispose);

      ctrl.handleWsEventForTest(_assigned(11));
      expect(ctrl.pendingOffer?.rideId, 11);

      // 後端對同一個 driver id 的每一條連線都送 ride.accepted（實測）。
      ctrl.handleWsEventForTest(
        FleetWsEvent(type: FleetEventTypes.rideAccepted, rideId: 11),
      );
      await Future<void>.delayed(Duration.zero);

      expect(ctrl.pendingOffer, isNull,
          reason: '全螢幕接單卡不收掉的話，這台裝置整個畫面都被蓋住');
      expect(ctrl.activeRide?.rideId, 11,
          reason: '司機正在跑這一趟，這台顯示「等待派單中」是另一種說謊');
    });

    test('另一台裝置接走、但後端說沒有進行中行程 → 只收卡片，不硬掰行程', () async {
      final api = _OfferApi()..activeAfterAccept = null;
      final ctrl = await _loggedIn(api);
      addTearDown(ctrl.dispose);

      ctrl.handleWsEventForTest(_assigned(11));
      ctrl.handleWsEventForTest(
        FleetWsEvent(type: FleetEventTypes.rideAccepted, rideId: 11),
      );
      await Future<void>.delayed(Duration.zero);

      expect(ctrl.pendingOffer, isNull);
      expect(ctrl.activeRide, isNull);
    });

    test('別張單的 ride.accepted 不會誤收掉手上的接單卡', () async {
      final api = _OfferApi();
      final ctrl = await _loggedIn(api);
      addTearDown(ctrl.dispose);

      ctrl.handleWsEventForTest(_assigned(11));
      ctrl.handleWsEventForTest(
        FleetWsEvent(type: FleetEventTypes.rideAccepted, rideId: 99),
      );

      expect(ctrl.pendingOffer?.rideId, 11);
    });
  });

  group('略過', () {
    test('要告訴後端（否則重派時會再送到同一位司機面前）', () async {
      final api = _OfferApi();
      final ctrl = await _loggedIn(api);
      addTearDown(ctrl.dispose);

      ctrl.handleWsEventForTest(_assigned(11));
      ctrl.dismissOffer();
      await Future<void>.delayed(Duration.zero);

      expect(ctrl.pendingOffer, isNull);
      expect(api.declinedRideIds, [11]);
    });

    test('後端拒單失敗也要把卡片關掉（附帶動作不可卡住畫面）', () async {
      final api = _OfferApi()..declineError = ApiException('無法連線到伺服器，請檢查網路');
      final ctrl = await _loggedIn(api);
      addTearDown(ctrl.dispose);

      ctrl.handleWsEventForTest(_assigned(11));
      ctrl.dismissOffer();
      await Future<void>.delayed(Duration.zero);

      expect(ctrl.pendingOffer, isNull);
      expect(ctrl.error, isNull, reason: '略過是他自己按的，失敗的是背景通知，不必打擾他');
    });
  });

  group('放棄此單：後端拒絕時同樣回 200', () {
    test('後端說「此訂單目前無法放棄」→ 行程卡要留著並說明原因', () async {
      final ride = ActiveRide.fromBackendJson(const {
        'id': 11,
        'status': RideStatus.accepted,
        'pickup_address': '台北市信義區市府路1號',
      });
      final api = _OfferApi()
        ..cancelMessage = '此訂單目前無法放棄'
        ..restoreRide = ride
        ..activeAfterAccept = ride; // 後端：這張單還是你的
      final ctrl = await _loggedIn(api);
      addTearDown(ctrl.dispose);
      expect(ctrl.activeRide?.rideId, 11, reason: '前置：手上有一張已接的單');

      await ctrl.abandonTrip();

      expect(ctrl.activeRide?.rideId, 11,
          reason: '沒放棄成功卻把卡片收掉＝司機以為脫手了，乘客還在等他');
      expect(ctrl.error, '此訂單目前無法放棄');
    });

    test('放棄成功（後端 active 不再有這張單）→ 收掉行程卡、不留錯誤', () async {
      final api = _OfferApi()
        ..cancelMessage = '已放棄此訂單'
        ..restoreRide = ActiveRide.fromBackendJson(const {
          'id': 11,
          'status': RideStatus.accepted,
          'pickup_address': '台北市信義區市府路1號',
        })
        ..activeAfterAccept = null;
      final ctrl = await _loggedIn(api);
      addTearDown(ctrl.dispose);

      await ctrl.abandonTrip();

      expect(ctrl.activeRide, isNull);
      expect(ctrl.error, isNull);
    });
  });
}

Future<DriverController> _loggedIn(_OfferApi api) async {
  final ctrl = DriverController(
    storage: MemoryDriverAuthStore()
      ..save(const AuthSession(driverId: 7, token: 'tok')),
    api: api,
    wsFactory: FleetWsClient.silent,
  );
  // init() 會用掉第一次 activeRide()（還原進行中行程），之後的呼叫才是動作後的重讀。
  await ctrl.init();
  return ctrl;
}

FleetWsEvent _assigned(int rideId) => FleetWsEvent(
      type: FleetEventTypes.rideAssigned,
      rideId: rideId,
      payload: const {
        'pickup_address': '台北市信義區市府路1號',
        'dropoff_address': '台北車站',
      },
    );

class _OfferApi extends FleetApiClient {
  _OfferApi() : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  /// init() 還原時回的行程；接單／放棄之後改回 [activeAfterAccept]。
  ActiveRide? restoreRide;
  ActiveRide? activeAfterAccept;
  ApiException? activeError;
  String acceptMessage = '接單成功';
  String cancelMessage = '已放棄此訂單';
  ApiException? declineError;
  final declinedRideIds = <int>[];
  int activeCallCount = 0;

  @override
  void setToken(String? token) {}

  @override
  Future<ActiveRide?> activeRide() async {
    if (activeError != null) throw activeError!;
    final first = activeCallCount == 0;
    activeCallCount++;
    return first ? restoreRide : activeAfterAccept;
  }

  @override
  Future<String> acceptRide(int rideId) async => acceptMessage;

  @override
  Future<String> cancelRide(int rideId) async => cancelMessage;

  @override
  Future<void> declineRide(int rideId) async {
    if (declineError != null) throw declineError!;
    declinedRideIds.add(rideId);
  }

  @override
  Future<List<LostItemRequest>> fetchLostItems() async => const [];

  @override
  Future<DriverVehicle> fetchVehicle() async => const DriverVehicle(
        vehicleType: 'sedan',
        plateNumber: 'ABC-1234',
        hasVehicle: true,
        reviewStatus: VehicleReviewStatus.approved,
        canAccept: true,
      );
}
