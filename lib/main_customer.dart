import 'package:flutter/material.dart';

import 'package:line_fleet_app/core/push/firebase_push_service.dart';

import 'customer/app.dart';

/// 乘客端進入點：登入後可叫車（帶目的地）並追蹤訂單狀態。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 沒有 Firebase 設定的裝置會拿到 NoOp——App 照常可用，只是少了推播喚醒。
  final push = await createCustomerPushService();
  runApp(CustomerApp(pushService: push));
}
