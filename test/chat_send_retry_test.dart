import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/fleet_api_client.dart' show ApiException;
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/theme/app_theme.dart';
import 'package:line_fleet_app/shared/screens/ride_chat_screen.dart';

/// 聊天送出逾時：後端可能其實收到了、只是回應遺失。
///
/// **這條路徑不能像其他寫入那樣「查一次狀態」對帳**——訊息在後端沒有唯一狀態，
/// 「同內容再送一次」本來就是合法行為。所以改由客戶端產生冪等鍵
/// （後端 dispatch #68 據此去重），逾時後補讀比對那個鍵：
/// 找到 ＝ 上一次其實送出了；找不到 ＝ 留著內容與**同一個鍵**讓他重試（重送不會多一則）。
void main() {
  testWidgets('逾時後補讀發現其實送出了 → 泡泡出現、輸入框清空、沒有錯誤', (tester) async {
    final api = _FakeChat();
    await tester.pumpWidget(_screen(api));
    await tester.pumpAndSettle();

    // 送出逾時，但後端其實寫進去了（帶著我們那個鍵）。
    api.sendFailure = ApiException('請求逾時，請稍後再試');
    api.landedAsIfSent = true;
    await tester.enterText(find.byType(TextField), '我在門口了');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(find.text('我在門口了'), findsOneWidget, reason: '訊息其實在後端了，畫面就該有它');
    expect(find.text('請求逾時，請稍後再試'), findsNothing,
        reason: '送出成功卻說逾時＝畫面在說謊（同第十五輪那個病）');
    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, '',
        reason: '已經送出去了，輸入框不該還留著那句話');
  });

  testWidgets('逾時後補讀發現真的沒送出 → 留著錯誤與內容，重試沿用同一個鍵', (tester) async {
    final api = _FakeChat();
    await tester.pumpWidget(_screen(api));
    await tester.pumpAndSettle();

    api.sendFailure = ApiException('請求逾時，請稍後再試');
    api.landedAsIfSent = false;
    await tester.enterText(find.byType(TextField), '我在門口了');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(find.text('請求逾時，請稍後再試'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text,
        '我在門口了',
        reason: '沒送出去就要留著內容，不然使用者得重打一次');

    // 使用者按送出重試——後端能不能去重，全看這次帶的鍵跟上次是不是同一個。
    api.sendFailure = null;
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(api.sentKeys.length, 2);
    expect(api.sentKeys[0], api.sentKeys[1],
        reason: '重試換了新鍵的話，後端會認成兩則不同的訊息——對方看到同一句話兩次');
    expect(find.text('我在門口了'), findsOneWidget);
  });

  testWidgets('送出成功後，下一則要用新的鍵', (tester) async {
    final api = _FakeChat();
    await tester.pumpWidget(_screen(api));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '第一句');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '第二句');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(api.sentKeys.length, 2);
    expect(api.sentKeys[0], isNot(api.sentKeys[1]),
        reason: '沿用同一個鍵會讓第二句被後端當成第一句的重送而吃掉');
  });

  testWidgets('對帳補讀時，對方同時說的話也要顯示', (tester) async {
    final api = _FakeChat();
    await tester.pumpWidget(_screen(api));
    await tester.pumpAndSettle();

    api.sendFailure = ApiException('請求逾時，請稍後再試');
    api.landedAsIfSent = true;
    api.othersDuringReconcile = [_incoming(41, '我快到了')];
    await tester.enterText(find.byType(TextField), '好，我等你');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(find.text('好，我等你'), findsOneWidget);
    expect(find.text('我快到了'), findsOneWidget,
        reason: '既然為了對帳問了一次，補讀到的訊息就不該丟掉');
  });

  testWidgets('後端明確拒絕（有狀態碼）時不對帳——它本來就沒收下這則', (tester) async {
    final api = _FakeChat();
    await tester.pumpWidget(_screen(api));
    await tester.pumpAndSettle();
    final historyCallsBefore = api.historyCalls;

    api.sendFailure = ApiException('訊息長度超過上限', statusCode: 400);
    await tester.enterText(find.byType(TextField), '很長的訊息');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(api.historyCalls, historyCallsBefore, reason: '400 不是「不知道成不成功」');
    expect(find.text('訊息長度超過上限'), findsOneWidget);
  });
}

Widget _screen(_FakeChat api) => MaterialApp(
      theme: appLightTheme,
      home: RideChatScreen(
        rideId: 9,
        selfRole: 'driver',
        title: '聯絡乘客（行程 #9）',
        loadHistory: api.loadHistory,
        send: api.send,
        incoming: api.incoming.stream,
      ),
    );

RideMessage _incoming(int id, String body) => RideMessage(
      id: id,
      rideId: 9,
      senderRole: 'customer',
      senderId: 3,
      body: body,
    );

/// 假聊天後端。
///
/// [sendFailure] 設了就讓送出失敗；[landedAsIfSent] ＝「後端其實寫進去了」——
/// 補讀時就會回一則帶著那個鍵的訊息（模擬回應遺失的正向競態）。
class _FakeChat {
  final incoming = StreamController<RideMessage>.broadcast();
  final sentKeys = <String?>[];

  ApiException? sendFailure;
  bool landedAsIfSent = false;
  List<RideMessage> othersDuringReconcile = const [];
  int historyCalls = 0;

  String? _lastBody;
  int _nextId = 100;

  Future<List<RideMessage>> loadHistory(int rideId, {int afterId = 0}) async {
    historyCalls++;
    final rows = <RideMessage>[...othersDuringReconcile];
    if (landedAsIfSent && sentKeys.isNotEmpty) {
      rows.add(RideMessage(
        id: _nextId++,
        rideId: 9,
        senderRole: 'driver',
        senderId: 7,
        body: _lastBody ?? '',
        clientMsgId: sentKeys.last,
      ));
    }
    return rows.where((m) => m.id > afterId).toList();
  }

  Future<RideMessage> send(int rideId, String body,
      {String? clientMsgId}) async {
    sentKeys.add(clientMsgId);
    _lastBody = body;
    if (sendFailure != null) throw sendFailure!;
    return RideMessage(
      id: _nextId++,
      rideId: 9,
      senderRole: 'driver',
      senderId: 7,
      body: body,
      clientMsgId: clientMsgId,
    );
  }
}
