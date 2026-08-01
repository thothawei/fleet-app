import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/customer_api_client.dart';
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/customer/customer_controller.dart';
import 'package:line_fleet_app/customer/screens/saved_places_screen.dart';
import 'package:line_fleet_app/shared/screens/ride_chat_screen.dart';
import 'package:line_fleet_app/shared/widgets/rune_limit.dart';
import 'package:line_fleet_app/core/theme/app_theme.dart';
import 'package:provider/provider.dart';

/// ZWJ 家庭 emoji：1 個 grapheme cluster、**7 個 rune**。
/// 後端的每一支上限數的都是 rune，Flutter 的 `maxLength` 數的是 cluster——
/// 這一整份測試釘的就是這個落差。
const _family = '👨‍👩‍👧‍👦';
const _flag = '🇹🇼'; // 1 cluster / 2 runes

TextEditingValue _v(String text) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: text.length),
);

void main() {
  group('RuneLimitingTextInputFormatter', () {
    test('前提：cluster 數與 rune 數真的不同（不同就沒有這個 bug）', () {
      expect(_family.characters.length, 1);
      expect(_family.runes.length, 7);
      expect(_flag.characters.length, 1);
      expect(_flag.runes.length, 2);
      // ASCII 與中文兩者相同——所以這個坑平常不會被踩到，只在 emoji 上炸。
      expect('你好abc'.characters.length, '你好abc'.runes.length);
    });

    test('ASCII／中文：與一般長度限制行為相同', () {
      const f = RuneLimitingTextInputFormatter(5);
      expect(f.formatEditUpdate(_v(''), _v('你好嗎')).text, '你好嗎');
      expect(f.formatEditUpdate(_v(''), _v('12345')).text, '12345');
      expect(f.formatEditUpdate(_v(''), _v('123456')).text, '12345');
    });

    test('emoji：擋在 rune 上，不是擋在 cluster 上', () {
      const f = RuneLimitingTextInputFormatter(20);
      // 6 個家庭 emoji ＝ 42 runes。Flutter 的 maxLength: 20 會全部放行（6 clusters）。
      final out = f.formatEditUpdate(_v(''), _v(_family * 6)).text;
      expect(out.runes.length, lessThanOrEqualTo(20));
      // 20 runes 裝得下 2 個家庭（14），第 3 個會超過 → 只留 2 個。
      expect(out, _family * 2);
    });

    test('裁切落在 cluster 邊界，不會切出半個 emoji', () {
      const f = RuneLimitingTextInputFormatter(10);
      final out = f.formatEditUpdate(_v(''), _v(_family * 3)).text;
      // 10 runes 只裝得下 1 個家庭（7）；剩下 3 個 rune 不足以再放一個，
      // **不可以**切一半留下孤立的修飾符／ZWJ 尾巴。
      expect(out, _family);
      expect(out.characters.length, 1, reason: '輸出必須是完整的 cluster');
    });

    test('沒超過就原樣放行（不動 selection／composing）', () {
      const f = RuneLimitingTextInputFormatter(50);
      const value = TextEditingValue(
        text: '打到一半',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 4),
      );
      expect(f.formatEditUpdate(_v(''), value), value);
    });

    test('runeCount 與後端同一單位', () {
      expect(runeCount(_family), 7);
      expect(runeCount('你好'), 2);
      expect(runeCount(''), 0);
    });
  });

  group('真實畫面', () {
    testWidgets('聊天輸入框：超過 500 rune 的 emoji 貼不進去（先前完全沒有上限）', (tester) async {
      final controller = StreamController<RideMessage>.broadcast();
      addTearDown(controller.close);
      await tester.pumpWidget(
        MaterialApp(
          theme: appLightTheme,
          home: RideChatScreen(
            rideId: 1,
            selfRole: 'customer',
            title: '聯絡司機',
            loadHistory: (rideId, {int afterId = 0}) async => const [],
            send: (rideId, body, {String? clientMsgId}) async => RideMessage(
              id: 1,
              rideId: rideId,
              senderRole: 'customer',
              senderId: 1,
              body: body,
            ),
            incoming: controller.stream,
            onVisibilityChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 100 個家庭 emoji ＝ 700 runes。cluster 數只有 100，所以 maxLength 那套
      // 會整段放行，然後被後端以 400「訊息長度超過上限」擋下。
      await tester.enterText(find.byType(TextField), _family * 100);
      await tester.pump();

      final text = tester
          .widget<TextField>(find.byType(TextField))
          .controller!
          .text;
      expect(
        text.runes.length,
        lessThanOrEqualTo(500),
        reason: '要擋在送出之前，不是讓後端回 400',
      );
      expect(text.characters.length, 71, reason: '500 ÷ 7 ＝ 71 個完整的家庭 emoji');
    });

    testWidgets('計數器數的是 rune：一個家庭 emoji 顯示 7/200 而不是 1/200', (tester) async {
      final ctrl = TextEditingController();
      addTearDown(ctrl.dispose);
      // 直接驗 runeCounter 這支 builder 產出的文字——它就是評分／協尋／預約
      // 三個畫面共用的那一支。
      await tester.pumpWidget(
        MaterialApp(
          theme: appLightTheme,
          home: Scaffold(
            body: TextField(
              controller: ctrl,
              inputFormatters: const [RuneLimitingTextInputFormatter(200)],
              maxLength: 200,
              maxLengthEnforcement: MaxLengthEnforcement.none,
              buildCounter: runeCounter(200, ctrl),
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), _family);
      await tester.pump();
      expect(
        find.text('7/200'),
        findsOneWidget,
        reason: '顯示 1/200 就等於畫面說沒超過、後端卻擋下',
      );
      expect(find.text('1/200'), findsNothing);
    });

    testWidgets('常用地點「名稱」：真的接上去了，而且擋在 40 rune（先前完全沒有上限）', (tester) async {
      final ctrl = CustomerController(api: _EmptyPlacesApi());
      addTearDown(ctrl.dispose);
      ctrl.setSessionForTest(
        const CustomerSession(customerId: 1, token: 'tok', name: '小美'),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: appLightTheme,
          home: ChangeNotifierProvider<CustomerController>.value(
            value: ctrl,
            child: const SavedPlacesScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 開新增地點的編輯表單——這一步是為了驗**真畫面有沒有接上**，
      // 不是只驗共用元件本身（共用元件在上面已經單獨驗過了）。
      await tester.tap(find.widgetWithText(FloatingActionButton, '新增地點'));
      await tester.pumpAndSettle();

      final label = find.widgetWithText(TextField, '名稱');
      expect(label, findsOneWidget, reason: '前置條件：編輯表單有打開');
      await tester.enterText(label, _flag * 30); // 30 clusters ＝ 60 runes
      await tester.pump();

      final text = tester.widget<TextField>(label).controller!.text;
      expect(
        text.runes.length,
        lessThanOrEqualTo(40),
        reason: '後端 maxPlaceLabelRunes 是 40，要擋在送出之前',
      );
      expect(text.characters.length, 20, reason: '40 ÷ 2 ＝ 20 面完整的旗子');
      expect(find.text('40/40'), findsOneWidget, reason: '計數器要說出 rune 數');
    });
  });
}

/// 只回空清單的常用地點 API（本檔只驗輸入限制，不驗清單內容）。
class _EmptyPlacesApi extends CustomerApiClient {
  _EmptyPlacesApi()
    : super(dio: Dio(BaseOptions(baseUrl: 'http://test.invalid/api')));

  @override
  Future<List<SavedPlace>> fetchSavedPlaces() async => const [];
}
