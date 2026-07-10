import 'package:flutter/material.dart';

import 'core/util/maps_js_loader.dart';
import 'customer/app.dart';

/// 乘客端進入點：登入後可叫車（帶目的地）並追蹤訂單狀態。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Web 版地圖需要 google.maps 先就位；未設 key 時為 no-op，不阻擋啟動。
  await ensureMapsJsLoaded();
  runApp(const CustomerApp());
}
