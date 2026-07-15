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

  bool get isConnected => _channel != null;

  Future<void> connect(String token) async {
    _token = token;
    // 允許「登出→重新登入」復用同一個 client：disconnect() 會設 _disposed=true
    // 擋掉舊 token 的自動重連，若不在明確重連時重置，_open()／_scheduleReconnect()
    // 會永遠早退，導致重新登入後 WebSocket 一直連不上（只有冷啟動重建 client 才會通）。
    _disposed = false;
    _reconnectTimer?.cancel();
    await _open();
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
    await _sub?.cancel();
    await _channel?.sink.close();

    final uri = Uri.parse('${AppConfig.wsBase}/ws').replace(
      queryParameters: {'token': _token},
    );
    try {
      _channel = _connector(uri);
      onConnectionChanged?.call(true);
      _sub = _channel!.stream.listen(
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
      _scheduleReconnect();
    }
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
