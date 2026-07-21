import 'dart:io' show Platform;

/// App 設定：API 位址可透過 --dart-define=API_BASE=... 覆寫。
/// 未覆寫時依平台給「模擬器連本機後端」的預設值：
/// Android 模擬器是 10.0.2.2，iOS／macOS 模擬器是 127.0.0.1（10.0.2.2 只有 Android 模擬器認得）。
/// 真機一律請帶 --dart-define=API_BASE=http://<電腦區網 IP>:8080。
class AppConfig {
  static const _apiBaseOverride = String.fromEnvironment('API_BASE');

  static String get apiBase {
    if (_apiBaseOverride.isNotEmpty) return _apiBaseOverride;
    return (Platform.isIOS || Platform.isMacOS)
        ? 'http://127.0.0.1:8080'
        : 'http://10.0.2.2:8080';
  }

  static String get wsBase {
    final uri = Uri.parse(apiBase);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final port = uri.hasPort ? uri.port : (scheme == 'wss' ? 443 : 80);
    return '$scheme://${uri.host}:$port';
  }

  /// 司機位置回報間隔（與後端模擬器預設 8s 對齊）
  static const locationIntervalSec = 8;
}

/// WebSocket 事件型別（對齊後端 internal/events/event.go）
class FleetEventTypes {
  static const rideAssigned = 'ride.assigned';
  static const rideAccepted = 'ride.accepted';
  static const driverLocation = 'driver.location';
  static const driverArrived = 'driver.arrived';
  static const ridePickedUp = 'ride.picked_up';
  static const rideCompleted = 'ride.completed';
  static const rideCancelled = 'ride.cancelled';

  /// 司機標記到達／跳過某一站（N8）。payload 帶**整趟** stops，收到直接覆蓋即可。
  static const rideStopUpdated = 'ride.stop_updated';
  static const chatMessage = 'chat.message';
  static const lostItemCreated = 'lost_item.created';
  static const lostItemUpdated = 'lost_item.updated';
}

/// 行程階段（司機端 UI 狀態）
enum DriverRidePhase {
  idle,
  offered,
  enRouteToPickup,
  onTrip,
}
