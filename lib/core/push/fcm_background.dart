import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'push_payload.dart';

/// FCM 背景 isolate 入口（App 被殺時仍須註冊 handler）。
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // 背景僅記錄；使用者點通知後由 onMessageOpenedApp / getInitialMessage 處理。
  final event = fleetEventFromPushData(message.data);
  if (event != null) {
    // ignore: avoid_print
    print('FCM background: ${event.type} ride=${event.rideId}');
  }
}
