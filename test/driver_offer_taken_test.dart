import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/fleet_api_client.dart';
import 'package:line_fleet_app/core/config/app_config.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/storage/token_storage.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/driver/driver_controller.dart';

/// 同一張單會**同時**推給半徑內每一位待命司機（後端 `dispatchRound` 一輪 `pushOffer` 全部），
/// 只有一位搶得到。先前沒搶到的人**沒有任何事件收得掉那張全螢幕接單卡**：
/// `ride.accepted` 只送給接到的那位，逾時取消也只通知乘客。
/// 他得自己按下去、拿到「手慢了，這單已被其他司機接走」才會消失——期間卡片蓋著整個畫面。
///
/// 後端補送 `ride.taken`（給沒接到的人）與 `ride.cancelled`（取消時給所有收過 offer 的人）後，
/// 這一側負責把卡片收掉。
void main() {
  group('司機端：沒搶到的接單卡要自己消失', () {
    test('ride.taken → 收掉接單卡，且不報錯（他什麼都沒做）', () async {
      final ctrl = await _loggedIn();
      addTearDown(ctrl.dispose);
      ctrl.handleWsEventForTest(_assigned(21));
      expect(ctrl.pendingOffer?.rideId, 21, reason: '前置：畫面上有一張接單卡');

      ctrl.handleWsEventForTest(
        FleetWsEvent(type: FleetEventTypes.rideTaken, rideId: 21),
      );

      expect(ctrl.pendingOffer, isNull);
      expect(ctrl.error, isNull, reason: '沒搶到不是錯誤，跳紅字只會干擾他開車');
      expect(ctrl.activeRide, isNull, reason: '沒接到就不該有行程');
    });

    test('別張單的 ride.taken 不動自己的接單卡', () async {
      final ctrl = await _loggedIn();
      addTearDown(ctrl.dispose);
      ctrl.handleWsEventForTest(_assigned(22));

      ctrl.handleWsEventForTest(
        FleetWsEvent(type: FleetEventTypes.rideTaken, rideId: 99),
      );

      expect(ctrl.pendingOffer?.rideId, 22);
    });

    test('逾時／乘客取消時的 ride.cancelled 一樣收掉接單卡', () async {
      final ctrl = await _loggedIn();
      addTearDown(ctrl.dispose);
      ctrl.handleWsEventForTest(_assigned(23));

      ctrl.handleWsEventForTest(
        FleetWsEvent(type: FleetEventTypes.rideCancelled, rideId: 23),
      );

      expect(ctrl.pendingOffer, isNull);
      expect(
        ctrl.error,
        isNull,
        reason: '他手上沒有行程，只有一張還沒按的邀請——不必跟他解釋什麼',
      );
    });
  });
}

Future<DriverController> _loggedIn() async {
  final ctrl = DriverController(
    storage: MemoryDriverAuthStore()
      ..save(const AuthSession(driverId: 7, token: 'tok')),
    api: _Api(),
    wsFactory: FleetWsClient.silent,
  );
  await ctrl.init();
  return ctrl;
}

FleetWsEvent _assigned(int rideId) => FleetWsEvent(
      type: FleetEventTypes.rideAssigned,
      rideId: rideId,
      payload: const {
        'address': '台北市信義區市府路1號',
        'dropoff_address': '台北車站',
      },
    );

class _Api extends FleetApiClient {
  _Api() : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  @override
  void setToken(String? token) {}

  @override
  Future<ActiveRide?> activeRide() async => null;

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
