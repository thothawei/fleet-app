import 'package:flutter/material.dart';

import 'package:line_fleet_app/core/push/firebase_push_service.dart';
import 'package:line_fleet_app/driver/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final push = await createDriverPushService();
  runApp(DriverApp(pushService: push));
}
