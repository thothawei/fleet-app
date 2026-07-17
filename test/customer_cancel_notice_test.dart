import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/customer_api_client.dart';
import 'package:line_fleet_app/core/config/app_config.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/customer/customer_controller.dart';
import 'package:line_fleet_app/customer/widgets/ride_phase_content.dart';

/// active 一律回 null（取消後行程不再屬 active）；費率固定回 2000（測試不打網路）。
class _FakeApi extends CustomerApiClient {
  _FakeApi() : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  @override
  Future<CustomerRide?> activeRide() async => null;

  @override
  Future<int> fetchPetCleaningFeeBps() async => 2000;
}

CustomerController _cancelledController({Map<String, dynamic>? payload}) {
  final ctrl = CustomerController(api: _FakeApi());
  ctrl.setSessionForTest(
    const CustomerSession(customerId: 1, token: 'tok', name: '小美'),
  );
  ctrl.setActiveRideForTest(
    const CustomerRide(rideId: 7, status: RideStatus.requested),
  );
  ctrl.handleWsEventForTest(
    FleetWsEvent(
      type: FleetEventTypes.rideCancelled,
      rideId: 7,
      payload: payload,
    ),
  );
  return ctrl;
}

/// 取消分支會非同步 refreshActive()；controller 測試要等它完成再 dispose，
/// 否則完成後的 notifyListeners 會打在已 dispose 的物件上。
/// （widget 測試不需要：pump 會推進 FakeAsync 讓它先完成。）
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('取消通知（P4 UI 呈現）— controller', () {
    test('no_vehicle_of_type → 帶車種名的文案＋建議改用不指定車種', () async {
      final ctrl = _cancelledController(payload: const {
        'cancel_reason': 'no_vehicle_of_type',
        'required_vehicle_type': 'pet',
      });
      await _settle();
      expect(ctrl.cancelNotice, contains('寵物用車'));
      expect(ctrl.suggestAnyVehicle, isTrue);
      ctrl.dispose();
    });

    test('payload 不帶 cancel_reason（乘客主動取消／司機放棄）→ 泛用文案、無快捷', () async {
      final ctrl = _cancelledController(payload: const {});
      await _settle();
      expect(ctrl.cancelNotice, '行程已取消。');
      expect(ctrl.suggestAnyVehicle, isFalse);
      ctrl.dispose();
    });

    test('dismissCancelNotice 後通知消失', () async {
      final ctrl = _cancelledController(payload: const {
        'cancel_reason': 'no_vehicle_of_type',
        'required_vehicle_type': 'pet',
      });
      await _settle();
      ctrl.dismissCancelNotice();
      expect(ctrl.cancelNotice, isNull);
      expect(ctrl.suggestAnyVehicle, isFalse);
      ctrl.dispose();
    });

    test('別的行程的取消事件不觸發通知', () {
      final ctrl = CustomerController(api: _FakeApi());
      ctrl.setSessionForTest(
        const CustomerSession(customerId: 1, token: 'tok', name: '小美'),
      );
      ctrl.setActiveRideForTest(
        const CustomerRide(rideId: 7, status: RideStatus.requested),
      );
      ctrl.handleWsEventForTest(
        FleetWsEvent(
          type: FleetEventTypes.rideCancelled,
          rideId: 999,
          payload: const {'cancel_reason': 'no_driver_available'},
        ),
      );
      expect(ctrl.cancelNotice, isNull);
      ctrl.dispose();
    });
  });

  group('取消通知（P4 UI 呈現）— 叫車表單 banner', () {
    Future<void> pumpForm(WidgetTester tester, CustomerController ctrl) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ListenableBuilder(
                listenable: ctrl,
                builder: (context, _) => OrderFormContent(ctrl: ctrl),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('指定車種找不到 → banner 顯示車種文案＋「改用不指定車種」快捷', (tester) async {
      final ctrl = _cancelledController(payload: const {
        'cancel_reason': 'no_vehicle_of_type',
        'required_vehicle_type': 'pet',
      });
      addTearDown(ctrl.dispose);
      await pumpForm(tester, ctrl);

      expect(find.textContaining('附近暫無寵物用車'), findsOneWidget);
      expect(find.text('改用不指定車種'), findsOneWidget);

      // 快捷：車種改回「不指定」並收起 banner，乘客只要再按一次「叫車」。
      await tester.tap(find.text('改用不指定車種'));
      await tester.pump();
      expect(ctrl.requiredVehicleType, isNull);
      expect(ctrl.cancelNotice, isNull);
      expect(find.textContaining('附近暫無寵物用車'), findsNothing);
    });

    testWidgets('泛用取消 → 只陳述事實、無快捷，按「知道了」收起', (tester) async {
      final ctrl = _cancelledController(payload: const {});
      addTearDown(ctrl.dispose);
      await pumpForm(tester, ctrl);

      expect(find.text('行程已取消。'), findsOneWidget);
      expect(find.text('改用不指定車種'), findsNothing);

      await tester.tap(find.text('知道了'));
      await tester.pump();
      expect(find.text('行程已取消。'), findsNothing);
    });

    testWidgets('沒有取消通知時表單不顯示 banner', (tester) async {
      final ctrl = CustomerController(api: _FakeApi());
      addTearDown(ctrl.dispose);
      await pumpForm(tester, ctrl);
      expect(find.text('知道了'), findsNothing);
    });
  });
}
