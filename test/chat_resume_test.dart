import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/api/fleet_api_client.dart' show ApiException;
import 'package:line_fleet_app/core/models/models.dart';
import 'package:line_fleet_app/core/theme/app_theme.dart';
import 'package:line_fleet_app/shared/screens/ride_chat_screen.dart';

/// 聊天室的「WS 斷線保底」原本是**死路徑**：`_loadHistory` 的 afterId 增量補讀
/// 只有 `initState` 會呼叫（那時訊息還是空的，等於全量），`onAppResumed` 兩端都不碰聊天。
/// 所以聊天室開著切背景、或 WS 斷線的期間，對方送的訊息永遠不會出現——
/// **WS 重連不會補送漏掉的事件**（docs/TODO.md 第四輪已查證），而且連未讀角標都不會亮
/// （聊天室開著時本來就不累計未讀）。這組測試把「回前景要補讀」釘住。
void main() {
  testWidgets('回前景補讀斷線期間的訊息（且只要 afterId 之後的）', (tester) async {
    final api = _FakeChat(history: [_msg(1, '我在門口'), _msg(2, '好，馬上到')]);
    await tester.pumpWidget(_screen(api));
    await tester.pumpAndSettle();

    expect(find.text('好，馬上到'), findsOneWidget);
    expect(api.calls, [0], reason: '進場那次 afterId=0（等於全量）');

    // 切到背景；期間對方送了兩則，WS 早就斷了所以一則都沒進來。
    api.history = [_msg(3, '我到了，黑色轎車'), _msg(4, '車牌 ABC-1234')];
    _backgroundAndReturn(tester);
    await tester.pumpAndSettle();

    expect(api.calls, [0, 2], reason: '補讀要從手上最後一則的 id 之後開始，不是整份重抓');
    expect(find.text('我到了，黑色轎車'), findsOneWidget);
    expect(find.text('車牌 ABC-1234'), findsOneWidget);
    expect(find.text('好，馬上到'), findsOneWidget, reason: '既有訊息不能被補讀洗掉');
  });

  testWidgets('inactive 的短暫失焦不補讀（通知列下拉、來電橫幅）', (tester) async {
    final api = _FakeChat(history: [_msg(1, '我在門口')]);
    await tester.pumpWidget(_screen(api));
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(api.calls, [0], reason: '連線沒斷，多打一支 API 是白花的');
  });

  testWidgets('回前景補讀失敗要靜默——使用者沒按任何東西，不該冒錯誤橫幅', (tester) async {
    final api = _FakeChat(history: [_msg(1, '我在門口')]);
    await tester.pumpWidget(_screen(api));
    await tester.pumpAndSettle();

    api.failWith = ApiException('無法連線到伺服器，請檢查網路');
    _backgroundAndReturn(tester);
    await tester.pumpAndSettle();

    expect(api.calls, [0, 1], reason: '有去補讀');
    expect(find.text('無法連線到伺服器，請檢查網路'), findsNothing,
        reason: '背景動作的失敗不該蓋到使用者臉上（同 2026-07-28 修掉的那一族）');
    expect(find.text('我在門口'), findsOneWidget, reason: '補讀失敗不能弄掉已經在畫面上的訊息');
  });

  testWidgets('使用者自己按「重試」失敗時仍要顯示原因', (tester) async {
    final api = _FakeChat(history: const [])
      ..failWith = ApiException('無法連線到伺服器，請檢查網路');
    await tester.pumpWidget(_screen(api));
    await tester.pumpAndSettle();

    // 進場那次就失敗 → 橫幅出現（這條路徑本來就有，順帶擋住「把靜默做過頭」）。
    expect(find.text('無法連線到伺服器，請檢查網路'), findsOneWidget);

    await tester.tap(find.text('重試'));
    await tester.pumpAndSettle();
    expect(find.text('無法連線到伺服器，請檢查網路'), findsOneWidget);
    expect(api.calls.length, 2);
  });
}

/// 切到背景再回前景。**中間的每一階段都要走過**——測試 binding 會擋掉
/// 不合法的狀態轉換（resumed 直接跳 paused 會丟 Invalid state transition）。
void _backgroundAndReturn(WidgetTester tester) {
  for (final s in const [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
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

RideMessage _msg(int id, String body) => RideMessage(
      id: id,
      rideId: 9,
      senderRole: 'customer',
      senderId: 3,
      body: body,
    );

/// 假聊天後端：[history] 是「這次呼叫要回的訊息」，[calls] 記下每次帶的 afterId。
class _FakeChat {
  _FakeChat({required this.history});

  List<RideMessage> history;
  final calls = <int>[];
  final incoming = StreamController<RideMessage>.broadcast();
  ApiException? failWith;

  Future<List<RideMessage>> loadHistory(int rideId, {int afterId = 0}) async {
    calls.add(afterId);
    if (failWith != null) throw failWith!;
    return history.where((m) => m.id > afterId).toList();
  }

  Future<RideMessage> send(int rideId, String body) async =>
      _msg(99, body);
}
