import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/customer_api_client.dart';
import 'package:line_fleet_app/core/api/fleet_api_client.dart' show ApiException;
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/customer/customer_controller.dart';

/// 建一個已登入的 controller（沿用既有測試的 setSessionForTest 慣例）。
CustomerController loggedInController(CustomerApiClient api) {
  final ctrl = CustomerController(api: api);
  ctrl.setSessionForTest(
    const CustomerSession(customerId: 1, token: 'tok', name: '小美'),
  );
  return ctrl;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('預約行程', () {
    test('載入清單後 upcoming 只留 pending，已轉單／取消／失敗都不算', () async {
      final api = _ScheduleApi(rides: [
        _schedule(1, ScheduledRideStatus.pending, hours: 3),
        _schedule(2, ScheduledRideStatus.dispatched, hours: 1, rideId: 77),
        _schedule(3, ScheduledRideStatus.cancelled, hours: 5),
        _schedule(4, ScheduledRideStatus.failed, hours: -2),
      ]);
      final ctrl = loggedInController(api);

      await ctrl.loadScheduledRides();

      expect(ctrl.scheduledRides.length, 4);
      expect(ctrl.upcomingSchedules.map((s) => s.id), [1]);
      // lead_minutes 要從後端來，不能是 App 寫死的——後端改了 App 才不會說謊。
      expect(ctrl.scheduleLeadMinutes, 15);
    });

    test('清單依約定時間由近到遠排序', () async {
      final api = _ScheduleApi(rides: [
        _schedule(1, ScheduledRideStatus.pending, hours: 8),
        _schedule(2, ScheduledRideStatus.pending, hours: 2),
        _schedule(3, ScheduledRideStatus.pending, hours: 5),
      ]);
      final ctrl = loggedInController(api);
      await ctrl.loadScheduledRides();

      // 後端已排好序，但建立新預約後 controller 會自己重排——這裡驗的是那條排序約定。
      await ctrl.createScheduledRide(
        scheduledAt: DateTime.now().add(const Duration(hours: 3)),
        pickupLat: 25.03,
        pickupLng: 121.56,
        pickupAddress: '台北車站',
      );

      final times = ctrl.scheduledRides.map((s) => s.scheduledAt).toList();
      for (var i = 1; i < times.length; i++) {
        expect(
          times[i].isBefore(times[i - 1]),
          isFalse,
          reason: '第 $i 筆比前一筆早，排序壞了：$times',
        );
      }
    });

    test('取消成功後那筆變成 cancelled，且不再出現在 upcoming', () async {
      final api = _ScheduleApi(rides: [
        _schedule(1, ScheduledRideStatus.pending, hours: 3),
      ]);
      final ctrl = loggedInController(api);
      await ctrl.loadScheduledRides();
      expect(ctrl.upcomingSchedules, hasLength(1));

      final error = await ctrl.cancelScheduledRide(1);

      expect(error, isNull);
      expect(ctrl.scheduledRides.single.isCancelled, isTrue);
      expect(ctrl.upcomingSchedules, isEmpty);
    });

    test('取消時已被轉成訂單（409）→ 不能宣稱失敗，畫面要換成「已派車」', () async {
      // 這是這條流程最要命的一種壞法：排程器搶在取消前發動，App 卻只丟一句
      // 「取消失敗，請稍後再試」——乘客會一直按取消，而車照樣開過來。
      final api = _ScheduleApi(
        rides: [_schedule(1, ScheduledRideStatus.pending, hours: 1)],
        cancelConflictWith:
            _schedule(1, ScheduledRideStatus.dispatched, hours: 1, rideId: 42),
      );
      final ctrl = loggedInController(api);
      await ctrl.loadScheduledRides();

      final message = await ctrl.cancelScheduledRide(1);

      // 要回一句說得出下一步的話，而不是「請稍後再試」。
      expect(message, isNotNull);
      expect(message, contains('已經為你派車'));
      expect(message, contains('行程頁'));
      // 而且狀態必須就地更新成 dispatched，不能還停在 pending。
      final after = ctrl.scheduledRides.single;
      expect(after.isDispatched, isTrue);
      expect(after.rideId, 42);
      expect(after.cancellable, isFalse);
      expect(ctrl.upcomingSchedules, isEmpty);
    });

    test('取消逾時但後端其實已取消 → 重讀對帳後不報錯', () async {
      // 回應在路上掉了。若直接把逾時訊息丟給乘客，他會再按一次取消，
      // 然後撞上「已無法取消」而更困惑——其實第一次就成功了。
      final api = _ScheduleApi(
        rides: [_schedule(1, ScheduledRideStatus.pending, hours: 3)],
        cancelThrows: ApiException('連線逾時'),
        reloadAfterCancel: [_schedule(1, ScheduledRideStatus.cancelled, hours: 3)],
      );
      final ctrl = loggedInController(api);
      await ctrl.loadScheduledRides();

      final error = await ctrl.cancelScheduledRide(1);

      expect(error, isNull, reason: '後端已經取消了，不該還告訴乘客失敗');
      expect(ctrl.scheduledRides.single.isCancelled, isTrue);
    });

    test('取消逾時且後端確實沒取消 → 要如實回報失敗', () async {
      // 上一條的負向對照：沒有這條，「逾時一律回 null」也會讓上一條變綠。
      final api = _ScheduleApi(
        rides: [_schedule(1, ScheduledRideStatus.pending, hours: 3)],
        cancelThrows: ApiException('連線逾時'),
        reloadAfterCancel: [_schedule(1, ScheduledRideStatus.pending, hours: 3)],
      );
      final ctrl = loggedInController(api);
      await ctrl.loadScheduledRides();

      final error = await ctrl.cancelScheduledRide(1);

      expect(error, '連線逾時');
      expect(ctrl.scheduledRides.single.isPending, isTrue);
    });

    test('載入失敗時 silent 不設錯誤（叫車主流程不該被輔助功能打斷）', () async {
      final api = _ScheduleApi(listThrows: ApiException('伺服器忙碌'));
      final ctrl = loggedInController(api);

      await ctrl.loadScheduledRides(silent: true);
      expect(ctrl.schedulesError, isNull);

      await ctrl.loadScheduledRides();
      expect(ctrl.schedulesError, '伺服器忙碌');
    });
  });

  group('ScheduledRide 解析', () {
    test('後端 RFC3339 帶時區 → 轉成本地時間', () {
      final s = ScheduledRide.fromJson({
        'id': 9,
        'scheduled_at': '2026-08-01T02:30:00Z',
        'pickup_point': {'lat': 25.03, 'lng': 121.56},
        'pickup_address': '台北車站',
        'status': 'pending',
      });
      expect(s.scheduledAt.isUtc, isFalse);
      expect(
        s.scheduledAt.toUtc(),
        DateTime.utc(2026, 8, 1, 2, 30),
      );
    });

    test('缺 dropoff 時為 null，不是空字串', () {
      final s = ScheduledRide.fromJson({
        'id': 9,
        'scheduled_at': '2026-08-01T02:30:00Z',
        'pickup_point': {'lat': 25.03, 'lng': 121.56},
        'pickup_address': '台北車站',
        'dropoff_address': '',
        'status': 'pending',
      });
      expect(s.dropoffAddress, isNull);
      expect(s.dropoffLat, isNull);
    });
  });
}

Map<String, dynamic> _scheduleJson(
  int id,
  String status, {
  required int hours,
  int? rideId,
}) =>
    {
      'id': id,
      'scheduled_at':
          DateTime.now().add(Duration(hours: hours)).toUtc().toIso8601String(),
      'pickup_point': {'lat': 25.0261, 'lng': 121.5435},
      'pickup_address': '住家',
      'dropoff_point': {'lat': 25.0797, 'lng': 121.5750},
      'dropoff_address': '公司',
      'status': status,
      'ride_id': rideId,
      'last_error': status == ScheduledRideStatus.failed ? '已有進行中的訂單' : '',
    };

ScheduledRide _schedule(
  int id,
  String status, {
  required int hours,
  int? rideId,
}) =>
    ScheduledRide.fromJson(
        _scheduleJson(id, status, hours: hours, rideId: rideId));

class _ScheduleApi extends CustomerApiClient {
  _ScheduleApi({
    this.rides = const [],
    this.cancelConflictWith,
    this.cancelThrows,
    this.reloadAfterCancel,
    this.listThrows,
  }) : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  List<ScheduledRide> rides;
  final ScheduledRide? cancelConflictWith;
  final ApiException? cancelThrows;
  final List<ScheduledRide>? reloadAfterCancel;
  final ApiException? listThrows;
  bool _cancelled = false;

  @override
  void setToken(String? token) {}

  @override
  Future<CustomerRide?> activeRide() async => null;

  @override
  Future<List<LostItemRequest>> fetchLostItems() async => <LostItemRequest>[];

  @override
  Future<List<SavedPlace>> fetchSavedPlaces() async => const [];

  @override
  Future<ScheduledRidesResult> fetchScheduledRides({
    bool upcomingOnly = false,
  }) async {
    if (listThrows != null) throw listThrows!;
    final rows = _cancelled && reloadAfterCancel != null
        ? reloadAfterCancel!
        : rides;
    return ScheduledRidesResult(rides: rows, leadMinutes: 15);
  }

  @override
  Future<ScheduledRide> createScheduledRide({
    required DateTime scheduledAt,
    required double pickupLat,
    required double pickupLng,
    required String pickupAddress,
    String? dropoffAddress,
    double? dropoffLat,
    double? dropoffLng,
    String? requiredVehicleType,
    String note = '',
  }) async {
    return ScheduledRide(
      id: 999,
      scheduledAt: scheduledAt,
      pickupAddress: pickupAddress,
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      status: ScheduledRideStatus.pending,
    );
  }

  @override
  Future<ScheduledRide> cancelScheduledRide(int id) async {
    _cancelled = true;
    if (cancelConflictWith != null) {
      throw ScheduledRideConflict(cancelConflictWith!, '此預約已無法取消');
    }
    if (cancelThrows != null) throw cancelThrows!;
    final target = rides.firstWhere((s) => s.id == id);
    final cancelled = ScheduledRide(
      id: target.id,
      scheduledAt: target.scheduledAt,
      pickupAddress: target.pickupAddress,
      pickupLat: target.pickupLat,
      pickupLng: target.pickupLng,
      dropoffAddress: target.dropoffAddress,
      status: ScheduledRideStatus.cancelled,
    );
    rides = [
      for (final s in rides)
        if (s.id == id) cancelled else s,
    ];
    return cancelled;
  }
}
