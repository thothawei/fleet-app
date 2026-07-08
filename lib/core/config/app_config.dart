/// App 設定：API 位址可透過 --dart-define=API_BASE=... 覆寫。
/// Android 模擬器連本機後端用 10.0.2.2；真機請改為電腦區網 IP。
class AppConfig {
  static const apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://10.0.2.2:8080',
  );

  static String get wsBase {
    final uri = Uri.parse(apiBase);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final port = uri.hasPort ? uri.port : (scheme == 'wss' ? 443 : 80);
    return '$scheme://${uri.host}:$port';
  }

  /// 司機位置回報間隔（與後端模擬器預設 8s 對齊）
  static const locationIntervalSec = 8;

  /// Google Maps SDK 金鑰（`--dart-define=GOOGLE_MAPS_API_KEY=...`）。
  /// Android 另需在 `android/local.properties` 設定同名 key 供原生 SDK。
  static const googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: '',
  );

  /// Dart 層是否已設定 Maps key（未設定時地圖追蹤優雅降級為文字）。
  static bool get mapsConfigured =>
      googleMapsApiKey.isNotEmpty && !googleMapsApiKey.contains('YOUR_');
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
}

/// 行程階段（司機端 UI 狀態）
enum DriverRidePhase {
  idle,
  offered,
  enRouteToPickup,
  onTrip,
}
