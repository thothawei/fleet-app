import 'dart:async';
import 'dart:convert';

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

/// 連線 /ws?token=...，自動重連。
class FleetWsClient {
  FleetWsClient({required this.onEvent, this.onConnectionChanged});

  final FleetEventHandler onEvent;
  final void Function(bool connected)? onConnectionChanged;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  String? _token;
  bool _disposed = false;
  Timer? _reconnectTimer;

  bool get isConnected => _channel != null;

  Future<void> connect(String token) async {
    _token = token;
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
      _channel = WebSocketChannel.connect(uri);
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
}
