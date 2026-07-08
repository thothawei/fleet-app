import '../ws/fleet_ws_client.dart';

/// 司機端推播抽象：取得 FCM token、訂閱派單事件。
abstract class DriverPushService {
  /// 初始化（Firebase 等）；失敗回 false，不阻擋 App 啟動。
  Future<bool> initialize();

  bool get isAvailable;

  /// 目前 FCM token；未設定 Firebase 時為 null。
  Future<String?> getToken();

  /// 前景／點擊通知喚醒後的派單事件（與 WS 同型別）。
  Stream<FleetWsEvent> get rideEvents;

  /// FCM token 輪替（新 token）；訂閱者應向後端重新註冊。
  Stream<String> get tokenRefresh;

  Future<void> dispose();
}

/// 測試與未設定 Firebase 時的 no-op 實作。
class NoOpDriverPushService implements DriverPushService {
  @override
  Future<bool> initialize() async => false;

  @override
  bool get isAvailable => false;

  @override
  Future<String?> getToken() async => null;

  @override
  Stream<FleetWsEvent> get rideEvents => const Stream.empty();

  @override
  Stream<String> get tokenRefresh => const Stream.empty();

  @override
  Future<void> dispose() async {}
}
