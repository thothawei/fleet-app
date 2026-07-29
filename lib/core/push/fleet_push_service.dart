import '../ws/fleet_ws_client.dart';

/// 推播抽象（**兩端共用**）：取得 FCM token、訂閱推播事件、接住 token 輪替。
///
/// 先前這支叫 `DriverPushService`——乘客端要接推播時**原地改名而不是再抄一份**：
/// 兩端的管線完全一樣（初始化 Firebase → 要權限 → 監聽前景／點擊 → token 輪替），
/// 只有「哪些事件要往上送」不同，所以那一點做成參數
/// （見 `createDriverPushService`／`createCustomerPushService`）。
/// 各抄一份是本專案踩過的根因（遺失物 banner 只長在卡片版首頁，換版時就掉了）。
abstract class FleetPushService {
  /// 初始化（Firebase 等）；失敗回 false，不阻擋 App 啟動。
  Future<bool> initialize();

  bool get isAvailable;

  /// 目前 FCM token；未設定 Firebase 時為 null。
  Future<String?> getToken();

  /// 前景／點擊通知喚醒後的事件（與 WS 同型別）。
  Stream<FleetWsEvent> get rideEvents;

  /// FCM token 輪替（新 token）；訂閱者應向後端重新註冊。
  Stream<String> get tokenRefresh;

  Future<void> dispose();
}

/// 測試與未設定 Firebase 時的 no-op 實作。
class NoOpFleetPushService implements FleetPushService {
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
