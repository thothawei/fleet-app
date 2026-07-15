import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  late HttpServer server;
  late Uri wsUri;

  setUp(() async {
    // 起一個本機 WebSocket 伺服器（可達、握手立即完成），避免測試依賴真後端或卡在連線逾時。
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    wsUri = Uri.parse('ws://${server.address.host}:${server.port}/ws');
    server.transform(WebSocketTransformer()).listen((socket) {
      // 只需接受連線；不主動送訊息。
      socket.listen((_) {}, onError: (_) {}, cancelOnError: false);
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('登出（disconnect）後重新登入（connect）仍會重新連上', () async {
    final events = <bool>[];
    final client = FleetWsClient(
      onEvent: (_) {},
      onConnectionChanged: events.add,
      // 忽略 _open 依 AppConfig 組出的 uri，一律連本機測試伺服器。
      connector: (_) => WebSocketChannel.connect(wsUri),
    );
    addTearDown(client.disconnect);

    // 首次登入
    await client.connect('token-1');
    expect(events, contains(true), reason: '首次 connect 應連上並回報 connected=true');

    // 登出：斷線並停止舊 token 的自動重連
    await client.disconnect();
    expect(events.last, isFalse, reason: 'disconnect 後應回報 connected=false');

    // 重新登入（同一個 client instance）：
    // 修正前 disconnect() 設的 _disposed=true 未被重置，_open() 會早退、不再連線；
    // 修正後 connect() 會重置 _disposed 並重新連上。
    events.clear();
    await client.connect('token-2');
    expect(
      events,
      contains(true),
      reason: '重新登入後應重置 _disposed 並重新連上（回報 connected=true）',
    );
  });
}
