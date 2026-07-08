import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../ws/fleet_ws_client.dart';
import 'driver_push_service.dart';
import 'fcm_background.dart';
import 'push_payload.dart';

/// 真實 FCM 實作：需 `android/app/google-services.json`（見 README）。
class FirebaseDriverPushService implements DriverPushService {
  FirebaseDriverPushService({FirebaseMessaging? messaging})
      : _messaging = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _messaging;
  final _events = StreamController<FleetWsEvent>.broadcast();
  StreamSubscription<String>? _tokenRefreshSub;
  bool _available = false;

  @override
  bool get isAvailable => _available;

  @override
  Stream<FleetWsEvent> get rideEvents => _events.stream;

  @override
  Future<bool> initialize() async {
    if (kIsWeb) return false;
    try {
      await Firebase.initializeApp();
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

      _tokenRefreshSub = _messaging.onTokenRefresh.listen((_) {});

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
    if (event != null && isRideOfferPush(event)) {
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
    await _events.close();
  }
}

/// 依環境建立推播服務：有 Firebase 設定則用 FCM，否則 no-op。
Future<DriverPushService> createDriverPushService() async {
  if (kIsWeb) return NoOpDriverPushService();
  final svc = FirebaseDriverPushService();
  if (await svc.initialize()) return svc;
  await svc.dispose();
  return NoOpDriverPushService();
}
