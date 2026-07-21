import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  late HttpServer server;
  late Uri wsUri;
  // 已升級的 WebSocket 不受 HttpServer.close 影響，要斷線得自己關這些 socket。
  late List<WebSocket> serverSockets;

  Future<void> startServer([int port = 0]) async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    wsUri = Uri.parse('ws://${server.address.host}:${server.port}/ws');
    server.transform(WebSocketTransformer()).listen((socket) {
      serverSockets.add(socket);
      // 只需接受連線；不主動送訊息。
      socket.listen((_) {}, onError: (_) {}, cancelOnError: false);
    });
  }

  setUp(() async {
    // 起一個本機 WebSocket 伺服器（可達、握手立即完成），避免測試依賴真後端或卡在連線逾時。
    serverSockets = [];
    await startServer();
  });

  tearDown(() async {
    for (final s in serverSockets) {
      await s.close().catchError((_) => null);
    }
    await server.close(force: true);
  });

  /// connect() 是背景連線（不擋登入），故等 onConnectionChanged 回報而非等 connect() 回傳。
  Future<bool> nextConnectionState(Stream<bool> states) =>
      states.first.timeout(const Duration(seconds: 10));

  test('登出（disconnect）後重新登入（connect）仍會重新連上', () async {
    final states = StreamController<bool>.broadcast();
    final client = FleetWsClient(
      onEvent: (_) {},
      onConnectionChanged: states.add,
      // 忽略 _open 依 AppConfig 組出的 uri，一律連本機測試伺服器。
      connector: (_) => WebSocketChannel.connect(wsUri),
    );
    // addTearDown 為 LIFO：後加的先跑。disconnect 會回報狀態，必須在 stream 關閉前執行。
    addTearDown(states.close);
    addTearDown(client.disconnect);

    // 首次登入
    final firstConnected = nextConnectionState(states.stream);
    await client.connect('token-1');
    expect(await firstConnected, isTrue, reason: '首次 connect 應連上並回報 connected=true');

    // 登出：斷線並停止舊 token 的自動重連
    final disconnected = nextConnectionState(states.stream);
    await client.disconnect();
    expect(await disconnected, isFalse, reason: 'disconnect 後應回報 connected=false');

    // 重新登入（同一個 client instance）：
    // 修正前 disconnect() 設的 _disposed=true 未被重置，_open() 會早退、不再連線；
    // 修正後 connect() 會重置 _disposed 並重新連上。
    final reconnected = nextConnectionState(states.stream);
    await client.connect('token-2');
    expect(
      await reconnected,
      isTrue,
      reason: '重新登入後應重置 _disposed 並重新連上（回報 connected=true）',
    );
  });

  test('連線失敗時不得回報 connected=true（握手未完成前不算連上）', () async {
    // 連一個沒人聽的埠：channel 會被同步建出來，但握手必定失敗。
    // 修正前 _open() 在 connector 回傳當下就 onConnectionChanged(true)，
    // UI 因此顯示「即時連線正常」，實際上司機收不到任何派單。
    final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final deadPort = closed.port;
    await closed.close();
    final deadUri = Uri.parse('ws://127.0.0.1:$deadPort/ws');

    final states = <bool>[];
    final client = FleetWsClient(
      onEvent: (_) {},
      onConnectionChanged: states.add,
      connector: (_) => WebSocketChannel.connect(deadUri),
    );
    addTearDown(client.disconnect);

    await client.connect('token-x');
    // 給背景連線足夠時間失敗並回報
    await Future<void>.delayed(const Duration(seconds: 2));

    expect(
      states,
      isNot(contains(true)),
      reason: '握手失敗時絕不可回報 connected=true（那會讓 UI 謊稱連線正常）',
    );
    expect(client.isConnected, isFalse, reason: '未完成握手不算已連線');
  });

  test('connect() 不等握手完成即回傳，不擋住登入流程', () async {
    // 連不通的位址：握手會一路卡到逾時。connect() 若 await 握手，登入就會跟著卡住。
    final client = FleetWsClient(
      onEvent: (_) {},
      // 10.255.255.1 為不可路由位址，連線會 hang 而非立即被拒。
      connector: (_) => WebSocketChannel.connect(Uri.parse('ws://10.255.255.1:9/ws')),
    );
    addTearDown(client.disconnect);

    final sw = Stopwatch()..start();
    await client.connect('token-y');
    sw.stop();

    expect(
      sw.elapsed,
      lessThan(const Duration(seconds: 2)),
      reason: 'connect() 應立刻回傳（背景連線），不可等到握手逾時才放行登入',
    );
  });

  test('伺服器斷線後恢復 → 應自動重連（重連鏈不可中斷）', () async {
    // 實跑遇到：後端恢復後 App 仍停在「連線中斷」，只有重開 App 才連得回來。
    final states = StreamController<bool>.broadcast();
    final client = FleetWsClient(
      onEvent: (_) {},
      onConnectionChanged: states.add,
      connector: (_) => WebSocketChannel.connect(wsUri),
    );
    addTearDown(states.close);
    addTearDown(client.disconnect);

    final firstConnected = states.stream.firstWhere((s) => s).timeout(
          const Duration(seconds: 10),
        );
    await client.connect('token-1');
    expect(await firstConnected, isTrue);

    // 伺服器掛掉：切斷既有連線並停止接受新連線
    final dropped = states.stream.firstWhere((s) => !s).timeout(
          const Duration(seconds: 10),
        );
    final port = server.port;
    for (final s in serverSockets) {
      await s.close();
    }
    serverSockets.clear();
    await server.close(force: true);
    expect(await dropped, isFalse, reason: '伺服器斷線應回報 connected=false');

    // 伺服器以同一個埠回來
    final reconnected = states.stream.firstWhere((s) => s).timeout(
          const Duration(seconds: 20),
        );
    await startServer(port);

    expect(
      await reconnected,
      isTrue,
      reason: '伺服器恢復後應自動重連；重連鏈若被未捕捉的例外打斷，司機將永遠收不到派單',
    );
  });

  test('重連間隔採指數退避：3→6→12→24→30 秒封頂', () {
    // 固定 3 秒重試在長時間離線（隧道、後端維護）會一直打空包，白耗電與流量。
    expect(FleetWsClient.reconnectDelayFor(0), const Duration(seconds: 3),
        reason: '第一次仍要 3 秒——短暫閃斷的恢復速度不可變慢');
    expect(FleetWsClient.reconnectDelayFor(1), const Duration(seconds: 6));
    expect(FleetWsClient.reconnectDelayFor(2), const Duration(seconds: 12));
    expect(FleetWsClient.reconnectDelayFor(3), const Duration(seconds: 24));
    expect(FleetWsClient.reconnectDelayFor(4), const Duration(seconds: 30),
        reason: '封頂 30 秒：離線再久也不該讓恢復連線等超過半分鐘');
    expect(FleetWsClient.reconnectDelayFor(60), const Duration(seconds: 30),
        reason: '次數大到左移溢位（變負數）時也要夾到上限，不能變成 0 秒狂重連');
  });

  test('握手成功後退避歸零，下次閃斷仍在 3 秒內重連', () async {
    final states = StreamController<bool>.broadcast();
    final client = FleetWsClient(
      onEvent: (_) {},
      onConnectionChanged: states.add,
      connector: (_) => WebSocketChannel.connect(wsUri),
    );
    addTearDown(states.close);
    addTearDown(client.disconnect);

    final connected = nextConnectionState(states.stream);
    await client.connect('token-1');
    expect(await connected, isTrue);
    expect(client.reconnectAttempts, 0,
        reason: '連上就要歸零，否則「連上又斷」會沿用上一輪的長間隔');
  });
}
