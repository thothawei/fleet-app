import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/customer_api_client.dart';
import 'package:line_fleet_app/core/config/app_config.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/customer/customer_controller.dart';
import 'package:line_fleet_app/driver/driver_controller.dart';

FleetWsEvent _chatEvent({
  required int id,
  required int rideId,
  required String senderRole,
  String body = 'hello',
}) {
  return FleetWsEvent(
    type: FleetEventTypes.chatMessage,
    rideId: rideId,
    payload: {
      'id': id,
      'ride_id': rideId,
      'sender_role': senderRole,
      'sender_id': 1,
      'body': body,
      'created_at': '2026-07-13T10:00:00Z',
    },
  );
}

FleetWsEvent _lostItemEvent(String type, {required String status}) {
  return FleetWsEvent(
    type: type,
    rideId: 5,
    payload: {
      'id': 3,
      'ride_id': 5,
      'customer_id': 1,
      'driver_id': 7,
      'description': '黑色錢包',
      'fee_cents': 1000,
      'fee_bps': 1000,
      'status': status,
      'paid_at': null,
      'created_at': '2026-07-13T10:00:00Z',
    },
  );
}

void main() {
  group('模型解析', () {
    test('RideMessage.fromJson 解析 WS/REST payload', () {
      final msg = RideMessage.fromJson({
        'id': 12,
        'ride_id': 5,
        'sender_role': 'driver',
        'sender_id': 7,
        'body': '好的，馬上到',
        'created_at': '2026-07-13T10:00:00Z',
      });
      expect(msg.id, 12);
      expect(msg.rideId, 5);
      expect(msg.senderRole, 'driver');
      expect(msg.body, '好的，馬上到');
      expect(msg.createdAt, isNotNull);
    });

    test('LostItemRequest.fromJson 與狀態標籤', () {
      final item = LostItemRequest.fromJson({
        'id': 3,
        'ride_id': 5,
        'customer_id': 1,
        'driver_id': 7,
        'description': '黑色錢包',
        'fee_cents': 1000,
        'fee_bps': 1000,
        'status': 'found',
        'paid_at': null,
        'created_at': '2026-07-13T10:00:00Z',
      });
      expect(item.feeCents, 1000);
      expect(item.isActive, isTrue);
      expect(item.statusLabel, '司機已尋獲，待支付處理費');
      expect(LostItemStatus.isActive('returned'), isFalse);
      expect(LostItemStatus.isActive('closed'), isFalse);
    });
  });

  group('DriverController 聊天與遺失物 WS 行為', () {
    late DriverController ctrl;

    setUp(() {
      ctrl = DriverController(wsFactory: FleetWsClient.silent);
    });

    tearDown(() => ctrl.dispose());

    test('乘客訊息→未讀+1 並上 chatStream；自己回聲不計未讀', () async {
      final received = <RideMessage>[];
      final sub = ctrl.chatStream.listen(received.add);

      ctrl.handleWsEventForTest(
        _chatEvent(id: 1, rideId: 5, senderRole: 'customer'),
      );
      ctrl.handleWsEventForTest(
        _chatEvent(id: 2, rideId: 5, senderRole: 'driver'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(ctrl.unreadChat, 1); // 只有乘客那則
      expect(received.length, 2); // 串流兩則都到（聊天室自己去重/呈現）
      await sub.cancel();
    });

    test('聊天室開啟→清未讀且不再累計；關閉後恢復累計', () {
      ctrl.handleWsEventForTest(
        _chatEvent(id: 1, rideId: 5, senderRole: 'customer'),
      );
      expect(ctrl.unreadChat, 1);

      ctrl.setChatVisible(true);
      expect(ctrl.unreadChat, 0);
      ctrl.handleWsEventForTest(
        _chatEvent(id: 2, rideId: 5, senderRole: 'customer'),
      );
      expect(ctrl.unreadChat, 0); // 開著聊天室不累計

      ctrl.setChatVisible(false);
      ctrl.handleWsEventForTest(
        _chatEvent(id: 3, rideId: 5, senderRole: 'customer'),
      );
      expect(ctrl.unreadChat, 1);
    });

    test('lost_item.created 加入工作清單；updated 至終態即移除', () {
      ctrl.handleWsEventForTest(
        _lostItemEvent(FleetEventTypes.lostItemCreated, status: 'open'),
      );
      expect(ctrl.lostItems.length, 1);
      expect(ctrl.lostItems.first.description, '黑色錢包');

      ctrl.handleWsEventForTest(
        _lostItemEvent(FleetEventTypes.lostItemUpdated, status: 'found'),
      );
      expect(ctrl.lostItems.single.status, 'found'); // 同 id 更新非新增

      ctrl.handleWsEventForTest(
        _lostItemEvent(FleetEventTypes.lostItemUpdated, status: 'returned'),
      );
      expect(ctrl.lostItems, isEmpty);
    });
  });

  group('CustomerController 遺失物操作', () {
    late _FakeCustomerApi api;
    late CustomerController ctrl;

    setUp(() {
      api = _FakeCustomerApi();
      ctrl = CustomerController(api: api);
      ctrl.setSessionForTest(
        const CustomerSession(customerId: 1, token: 'tok', name: '小美'),
      );
    });

    tearDown(() => ctrl.dispose());

    test('reportLostItem→清單出現含處理費快照的協尋單', () async {
      final item = await ctrl.reportLostItem(5, '黑色錢包');
      expect(item.feeCents, 1000);
      expect(ctrl.lostItems.single.id, item.id);
    });

    test('payLostItem→狀態變 paid；WS 通知結案即從清單移除', () async {
      await ctrl.reportLostItem(5, '黑色錢包');
      api.status = 'paid';
      await ctrl.payLostItem(3);
      expect(ctrl.lostItems.single.status, 'paid');

      ctrl.handleWsEventForTest(
        _lostItemEvent(FleetEventTypes.lostItemUpdated, status: 'returned'),
      );
      expect(ctrl.lostItems, isEmpty);
    });
  });
}

class _FakeCustomerApi extends CustomerApiClient {
  _FakeCustomerApi()
      : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  String status = 'open';

  LostItemRequest _item() => LostItemRequest.fromJson({
        'id': 3,
        'ride_id': 5,
        'customer_id': 1,
        'driver_id': 7,
        'description': '黑色錢包',
        'fee_cents': 1000,
        'fee_bps': 1000,
        'status': status,
        'created_at': '2026-07-13T10:00:00Z',
      });

  @override
  Future<LostItemRequest> createLostItem(int rideId, String description) async =>
      _item();

  @override
  Future<LostItemRequest> payLostItem(int itemId) async => _item();

  @override
  Future<List<LostItemRequest>> fetchLostItems() async => [];
}
