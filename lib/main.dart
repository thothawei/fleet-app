import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:line_fleet_app/core/platform/web_unsupported.dart';
import 'package:line_fleet_app/core/push/firebase_push_service.dart';
import 'package:line_fleet_app/driver/app.dart';

/// 預設入口：司機端
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 司機端在瀏覽器不可能運作，先攔下來給明確訊息，別讓它在 dart:io 半路炸。
  if (kIsWeb) {
    runDriverWebUnsupportedApp();
    return;
  }

  final push = await createDriverPushService();
  runApp(DriverApp(pushService: push));
}
