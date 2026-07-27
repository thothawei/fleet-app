import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/customer_api_client.dart';
import 'package:line_fleet_app/core/api/fleet_api_client.dart' show ApiException;
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/theme/app_theme.dart';
import 'package:line_fleet_app/customer/customer_controller.dart';
import 'package:line_fleet_app/customer/screens/ride_history_screen.dart';
import 'package:line_fleet_app/customer/widgets/ride_phase_content.dart';
import 'package:provider/provider.dart';

class _FakeApi extends CustomerApiClient {
  _FakeApi() : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  List<CustomerRideSummary> history = const [];
  ApiException? rateError;
  int rateCalls = 0;
  int? lastRideId;
  int? lastScore;
  String? lastComment;

  @override
  Future<List<CustomerRideSummary>> fetchRideHistory({int limit = 20}) async =>
      history;

  @override
  Future<RideRating> rateRide(
    int rideId, {
    required int score,
    String comment = '',
  }) async {
    rateCalls++;
    lastRideId = rideId;
    lastScore = score;
    lastComment = comment;
    if (rateError != null) throw rateError!;
    return RideRating(rideId: rideId, score: score, comment: comment);
  }
}

CustomerController _loggedIn(_FakeApi api) {
  final ctrl = CustomerController(api: api);
  ctrl.setSessionForTest(
    const CustomerSession(customerId: 1, token: 'tok', name: '小美'),
  );
  return ctrl;
}

CustomerRideSummary _summary({
  int rideId = 42,
  int status = 4,
  int? driverId = 7,
  int? ratingScore,
}) =>
    CustomerRideSummary(
      rideId: rideId,
      status: status,
      pickupAddress: '台北101',
      dropoffAddress: '台北車站',
      fareAmountCents: 21500,
      driverId: driverId,
      driverName: '阿明',
      ratingScore: ratingScore,
    );

void main() {
  group('B5 評分模型', () {
    test('RideRating 解析後端回應；缺 comment 為空字串', () {
      final r = RideRating.fromJson(const {
        'ride_id': 42,
        'score': 5,
        'comment': '司機很準時',
      });
      expect(r.rideId, 42);
      expect(r.score, 5);
      expect(r.comment, '司機很準時');
      expect(RideRating.fromJson(const {'ride_id': 1, 'score': 3}).comment, '');
    });

    test('歷史列 rating_score 解析：有值＝已評、缺鍵＝未評', () {
      final rated = CustomerRideSummary.fromJson(const {
        'id': 42,
        'status': 4,
        'pickup_address': '台北101',
        'driver_id': 7,
        'rating_score': 4,
      });
      expect(rated.isRated, isTrue);
      expect(rated.ratingScore, 4);
      expect(rated.canRate, isFalse, reason: '評過就不該再給評分入口');

      final unrated = CustomerRideSummary.fromJson(const {
        'id': 43,
        'status': 4,
        'pickup_address': '台北101',
        'driver_id': 7,
      });
      expect(unrated.isRated, isFalse);
      expect(unrated.canRate, isTrue);
    });

    test('canRate 三個條件缺一不可：未完成／無司機都不能評', () {
      expect(_summary(status: 3).canRate, isFalse, reason: '行程中沒有可評的服務');
      expect(_summary(status: 9).canRate, isFalse, reason: '已取消沒有服務可評');
      expect(_summary(driverId: null).canRate, isFalse,
          reason: '派單前取消沒有評分對象');
      expect(_summary().canRate, isTrue);
    });
  });

  group('B5 評分送出（controller）', () {
    late _FakeApi api;
    late CustomerController ctrl;

    setUp(() {
      api = _FakeApi();
      ctrl = _loggedIn(api);
    });

    tearDown(() => ctrl.dispose());

    test('成功 → 完成卡顯示星等、歷史列就地更新為已評分', () async {
      ctrl.markCompletedForTest(rideId: 42, fareAmountCents: 21500);
      api.history = [_summary(rideId: 42)];
      await ctrl.loadRideHistory();
      expect(ctrl.rideHistory.single.canRate, isTrue);

      final err = await ctrl.submitRating(42, score: 5, comment: ' 很棒 ');
      expect(err, isNull);
      expect(api.lastRideId, 42);
      expect(api.lastScore, 5);
      expect(ctrl.completedRatingScore, 5);
      expect(ctrl.rideHistory.single.ratingScore, 5,
          reason: '成功後清單那一列要就地翻成已評分，不必重打 API');
      expect(ctrl.rideHistory.single.canRate, isFalse);
    });

    test('失敗 → 回錯誤訊息、狀態不變、且不寫進全域 error', () async {
      ctrl.markCompletedForTest(rideId: 42);
      api.rateError = ApiException('此行程已評分過');

      final err = await ctrl.submitRating(42, score: 4);
      expect(err, '此行程已評分過');
      expect(ctrl.completedRatingScore, isNull, reason: '沒送出去就不能顯示成已評分');
      expect(ctrl.error, isNull,
          reason: '評分錯誤屬於對話框，丟到全域 error 會變成關掉對話框才看到的 SnackBar');
      expect(ctrl.ratingSubmitting, isFalse);
    });

    test('未登入不打 API', () async {
      final anon = CustomerController(api: api);
      addTearDown(anon.dispose);
      expect(await anon.submitRating(42, score: 5), isNotNull);
      expect(api.rateCalls, 0);
    });

    test('星等綁 rideId：換一趟完成卡不會顯示上一趟的星等', () async {
      ctrl.markCompletedForTest(rideId: 42);
      await ctrl.submitRating(42, score: 5);
      expect(ctrl.completedRatingScore, 5);

      // 下一趟完成（同一次 app 執行內）——評分入口必須回到未評狀態。
      ctrl.markCompletedForTest(rideId: 43);
      expect(ctrl.completedRatingScore, isNull);
    });
  });

  group('B5 評分 UI', () {
    testWidgets('完成卡：未評顯示可按的「留下評分」，評完只剩星等', (tester) async {
      final api = _FakeApi();
      final ctrl = _loggedIn(api);
      addTearDown(ctrl.dispose);
      ctrl.markCompletedForTest(
        rideId: 42,
        driverName: '阿明',
        fareAmountCents: 21500,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: appLightTheme,
          home: ChangeNotifierProvider<CustomerController>.value(
            value: ctrl,
            // 用 Consumer 重建，比照 production：完成卡的宿主畫面是
            // `context.watch<CustomerController>()`，不是拿固定實例硬渲染。
            child: Consumer<CustomerController>(
              builder: (_, c, _) => Scaffold(
                body: SingleChildScrollView(child: CompletedContent(ctrl: c)),
              ),
            ),
          ),
        ),
      );

      final button = find.widgetWithText(FilledButton, '留下評分');
      expect(button, findsOneWidget);
      expect(
        tester.widget<FilledButton>(button).onPressed,
        isNotNull,
        reason: '評分已上線，按鈕不可再是 disabled 佔位',
      );
      expect(find.textContaining('即將開放'), findsNothing);

      await ctrl.submitRating(42, score: 4);
      await tester.pump();
      expect(find.widgetWithText(FilledButton, '留下評分'), findsNothing);
      expect(find.text('已評分'), findsOneWidget);
    });

    testWidgets('歷史清單：未評的完成行程給「評分」，已評的顯示星等', (tester) async {
      final api = _FakeApi();
      final ctrl = _loggedIn(api);
      addTearDown(ctrl.dispose);
      api.history = [
        _summary(rideId: 42),
        _summary(rideId: 41, ratingScore: 5),
        _summary(rideId: 40, driverId: null), // 派單前取消：無對象可評也無對話
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: appLightTheme,
          home: ChangeNotifierProvider<CustomerController>.value(
            value: ctrl,
            child: const CustomerRideHistoryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, '評分'), findsOneWidget);
      expect(find.text('已評分'), findsOneWidget);
    });
  });
}
