import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/app_config.dart';

typedef FleetEventHandler = void Function(FleetWsEvent event);

/// WebSocket 即時事件（對齊後端 events.Event JSON）
class FleetWsEvent {
  FleetWsEvent({
    required this.type,
    this.rideId,
    this.payload,
  });

  final String type;
  final int? rideId;
  final Map<String, dynamic>? payload;

  factory FleetWsEvent.fromJson(Map<String, dynamic> json) {
    return FleetWsEvent(
      type: json['type'] as String,
      rideId: (json['ride_id'] as num?)?.toInt(),
      payload: json['payload'] != null
          ? Map<String, dynamic>.from(json['payload'] as Map)
          : null,
    );
  }
}

typedef FleetWsClientFactory = FleetWsClient Function({
  required FleetEventHandler onEvent,
  void Function(bool connected)? onConnectionChanged,
});

/// 連線 /ws?token=...，自動重連。
class FleetWsClient {
  FleetWsClient({
    required this.onEvent,
    this.onConnectionChanged,
    @visibleForTesting WebSocketChannel Function(Uri uri)? connector,
  }) : _connector = connector ?? WebSocketChannel.connect;

  final FleetEventHandler onEvent;
  final void Function(bool connected)? onConnectionChanged;

  /// 建立底層 WebSocket 連線的注入點（測試可換成連本機測試伺服器，避免依賴真實後端）。
  final WebSocketChannel Function(Uri uri) _connector;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  String? _token;
  bool _disposed = false;
  Timer? _reconnectTimer;

  /// 握手逾時；超過就放棄這次連線並排重連（系統 TCP 逾時太久，等它會讓司機長時間收不到派單）。
  static const _readyTimeout = Duration(seconds: 15);

  /// 關閉舊連線的等待上限（對端已消失時 close handshake 不會回來）。
  static const _closeTimeout = Duration(seconds: 2);

  /// 已完成握手才算連線（`_channel` 只在 `ready` 後才設）。
  bool get isConnected => _channel != null;

  Future<void> connect(String token) async {
    _token = token;
    // 允許「登出→重新登入」復用同一個 client：disconnect() 會設 _disposed=true
    // 擋掉舊 token 的自動重連，若不在明確重連時重置，_open()／_scheduleReconnect()
    // 會永遠早退，導致重新登入後 WebSocket 一直連不上（只有冷啟動重建 client 才會通）。
    _disposed = false;
    _reconnectTimer?.cancel();
    // 握手要等 `ready`，網路不通時可能卡到 TCP 逾時；不能讓登入流程陪它一起卡住。
    // 連線在背景進行，狀態一律由 onConnectionChanged 回報。
    unawaited(_open());
  }

  Future<void> disconnect() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    await _sub?.cancel();
    await _channel?.sink.close();
    _channel = null;
    onConnectionChanged?.call(false);
  }

  Future<void> _open() async {
    if (_disposed || _token == null) return;
    // 清掉上一條連線再重連。這裡的清理**絕不能無限等待**：硬斷線（伺服器被砍、網路消失）
    // 時 sink.close() 會等 close handshake 而可能永不完成，`_open()` 就卡死在這行，
    // 重連鏈默默停擺、也不會有任何例外——App 從此停在「連線中斷」直到重開。
    try {
      await _sub?.cancel();
    } catch (_) {}
    _sub = null;
    await _closeQuietly(_channel);
    _channel = null;

    final uri = Uri.parse('${AppConfig.wsBase}/ws').replace(
      queryParameters: {'token': _token},
    );
    WebSocketChannel? channel;
    try {
      // `WebSocketChannel.connect` 同步回傳 channel，但握手是非同步的——在這裡就報
      // connected=true 是在說謊：連線可能稍後才逾時失敗，UI 卻已顯示「即時連線正常」。
      // 必須等 `ready`（完成才代表真的連上），它失敗時也會在此拋出，
      // 順帶避免連線錯誤變成 unhandled exception。
      channel = _connector(uri);
      // 自訂逾時：系統 TCP 逾時可能長達數分鐘，那段期間不會有任何重連嘗試。
      await channel.ready.timeout(_readyTimeout);
      // 等待期間可能已登出（disconnect）；此時不可回報連線，也不該留著 channel。
      if (_disposed) {
        await _closeQuietly(channel);
        return;
      }
      _channel = channel;
      onConnectionChanged?.call(true);
      _sub = channel.stream.listen(
        (raw) {
          try {
            final json = jsonDecode(raw as String) as Map<String, dynamic>;
            onEvent(FleetWsEvent.fromJson(json));
          } catch (_) {}
        },
        onDone: _scheduleReconnect,
        onError: (_, _) => _scheduleReconnect(),
        cancelOnError: true,
      );
    } catch (_) {
      // 握手失敗／連線逾時／被拒：維持 disconnected 並排重連。
      await _closeQuietly(channel);
      _channel = null;
      _scheduleReconnect();
    }
  }

  /// 關閉 channel：可能再拋，也可能因對端已消失而永不完成——兩者都不可拖住重連。
  Future<void> _closeQuietly(WebSocketChannel? channel) async {
    if (channel == null) return;
    try {
      await channel.sink.close().timeout(_closeTimeout);
    } catch (_) {}
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    onConnectionChanged?.call(false);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), _open);
  }

  /// 測試替身：不開真實 WebSocket，只更新連線旗標。
  static FleetWsClient silent({
    required FleetEventHandler onEvent,
    void Function(bool connected)? onConnectionChanged,
  }) =>
      _SilentWsClient(
        onEvent: onEvent,
        onConnectionChanged: onConnectionChanged,
      );
}

class _SilentWsClient extends FleetWsClient {
  _SilentWsClient({required super.onEvent, super.onConnectionChanged});

  @override
  Future<void> connect(String token) async {
    onConnectionChanged?.call(true);
  }

  @override
  Future<void> disconnect() async {
    onConnectionChanged?.call(false);
  }
}
