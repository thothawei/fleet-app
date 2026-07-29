import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../ws/fleet_ws_client.dart';
import 'fleet_push_service.dart';
import 'fcm_background.dart';
import 'pending_push_replay.dart';
import 'push_payload.dart';

/// 真實 FCM 實作：需 `android/app/google-services.json`（見 README）。
///
/// [accepts] 決定哪些推播要往上送——司機端只要派單邀請，乘客端要行程狀態變化。
/// **管線兩端共用**，只有這個過濾器不同（見檔尾的兩支工廠）。
class FirebaseFleetPushService implements FleetPushService {
  FirebaseFleetPushService({
    required this.accepts,
    FirebaseMessaging? messaging,
  }) : _injectedMessaging = messaging;

  /// 這一端關心的推播事件。
  final bool Function(FleetWsEvent event) accepts;

  /// 測試注入用；正式路徑等 [Firebase.initializeApp] 後才取 instance——
  /// 在建構子取會在沒有 google-services.json 的裝置上直接拋 [core/no-app]。
  final FirebaseMessaging? _injectedMessaging;
  late final FirebaseMessaging _messaging;
  /// **不是普通的 broadcast controller**：冷啟動時 `getInitialMessage()` 發出事件的當下
  /// （`runApp` 之前）還沒有任何訂閱者，普通廣播串流會把它丟掉。見 [PendingReplaySink]。
  final _events = PendingReplaySink<FleetWsEvent>();
  final _tokenRefresh = StreamController<String>.broadcast();
  StreamSubscription<String>? _tokenRefreshSub;
  bool _available = false;

  @override
  bool get isAvailable => _available;

  @override
  Stream<FleetWsEvent> get rideEvents => _events.stream;

  @override
  Stream<String> get tokenRefresh => _tokenRefresh.stream;

  @override
  Future<bool> initialize() async {
    if (kIsWeb) return false;
    try {
      await Firebase.initializeApp();
      _messaging = _injectedMessaging ?? FirebaseMessaging.instance;
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final allowed = settings.authorizationStatus ==
              AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      if (!allowed && defaultTargetPlatform == TargetPlatform.iOS) {
        return false;
      }

      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_onOpenedMessage);

      final initial = await _messaging.getInitialMessage();
      if (initial != null) _onOpenedMessage(initial);

      _tokenRefreshSub = _messaging.onTokenRefresh.listen(_tokenRefresh.add);

      _available = true;
      return true;
    } catch (e) {
      debugPrint('FCM 初始化失敗（可略過，仍可用 WS）: $e');
      return false;
    }
  }

  void _onForegroundMessage(RemoteMessage message) {
    _emitFromMessage(message);
  }

  void _onOpenedMessage(RemoteMessage message) {
    _emitFromMessage(message);
  }

  void _emitFromMessage(RemoteMessage message) {
    final event = fleetEventFromPushData(message.data);
    if (event != null && accepts(event)) {
      _events.add(event);
    }
  }

  @override
  Future<String?> getToken() async {
    if (!_available) return null;
    try {
      return await _messaging.getToken();
    } catch (e) {
      debugPrint('取得 FCM token 失敗: $e');
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    await _tokenRefreshSub?.cancel();
    await _tokenRefresh.close();
    await _events.close();
  }
}

/// 司機端：只收派單邀請（喚醒後要顯示接單卡）。
Future<FleetPushService> createDriverPushService() =>
    _create(isRideOfferPush);

/// 乘客端：收行程狀態變化。
///
/// **推播只當作「去跟後端對一次帳」的訊號**，payload 不直接套用到畫面——
/// FCM data 的值全是字串又稀疏（見 pitfall-fcm-data-all-strings），
/// 直接灌進 `_handleWsEvent` 會把司機姓名／車牌之類的欄位洗成空的。
Future<FleetPushService> createCustomerPushService() =>
    _create(isCustomerRidePush);

/// 依環境建立推播服務：有 Firebase 設定則用 FCM，否則 no-op
/// （**沒有 `google-services.json` 的裝置照樣能用 App，只是少了推播喚醒**）。
Future<FleetPushService> _create(bool Function(FleetWsEvent) accepts) async {
  if (kIsWeb) return NoOpFleetPushService();
  final svc = FirebaseFleetPushService(accepts: accepts);
  if (await svc.initialize()) return svc;
  await svc.dispose();
  return NoOpFleetPushService();
}
