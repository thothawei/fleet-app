// 司機聯絡電話的端到端驗收：在真模擬器上跑真 App、打真後端。
//
// 為什麼需要這個檔：widget test 用的是 Fake API，證明不了「App 真的把電話寫進後端、
// 而且沒有把車輛審核狀態弄壞」；而系統層的合成點擊事件在本機 CI/agent 環境送不進
// 模擬器（見 docs/TODO.md 的說明），所以互動必須由 Flutter 自己派送。
//
// 前置：後端要跑在 --dart-define 指定的 API_BASE，且該司機帳號存在、車輛已核准。
// 跑法：
//   flutter test integration_test/driver_phone_test.dart \
//     -d <simulator-id> --flavor driver \
//     --dart-define=API_BASE=http://127.0.0.1:8080
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:line_fleet_app/core/api/fleet_api_client.dart';
import 'package:line_fleet_app/core/storage/token_storage.dart';
import 'package:line_fleet_app/core/ws/fleet_ws_client.dart';
import 'package:line_fleet_app/core/theme/app_theme.dart';
import 'package:line_fleet_app/driver/driver_controller.dart';
import 'package:line_fleet_app/driver/screens/driver_vehicle_screen.dart';
import 'package:provider/provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('司機填聯絡電話 → 真的寫進後端，且車輛審核狀態不受影響', (tester) async {
    final api = FleetApiClient();
    final ctrl = DriverController(
      storage: MemoryDriverAuthStore(),
      api: api,
      // 這個案子與派單無關，靜默 WS 免得測試被連線時序干擾。
      wsFactory: FleetWsClient.silent,
    );
    addTearDown(ctrl.dispose);

    await ctrl.init();
    await ctrl.login(lineUserId: 'sim-driver-001', password: 'password123');
    expect(ctrl.isLoggedIn, isTrue, reason: '前置：登入應成功（後端有跑嗎？）');
    expect(ctrl.canAcceptRides, isTrue, reason: '前置：這位司機的車輛應已核准');

    await tester.pumpWidget(
      ChangeNotifierProvider<DriverController>.value(
        value: ctrl,
        child: MaterialApp(
          theme: appLightTheme,
          home: const DriverVehicleScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 帶分隔符號輸入，順便驗後端正規化後有回填到欄位。
    await tester.enterText(
      find.widgetWithText(TextFormField, '電話（選填）'),
      '0988-123-456',
    );
    await tester.tap(find.text('儲存聯絡電話'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    expect(find.text('聯絡電話已儲存'), findsOneWidget, reason: 'SnackBar 應出現');
    expect(ctrl.error, isNull, reason: '不應有錯誤');

    // 以「重新向後端查一次」為準，而不是相信 controller 的記憶體狀態。
    final fresh = await api.fetchProfile();
    expect(fresh.phone, '0988123456', reason: '後端應存下正規化後的號碼');

    // 這是本功能存在的理由：改電話不可以把司機踢回審核中。
    final vehicle = await api.fetchVehicle();
    expect(vehicle.canAccept, isTrue, reason: '存電話後仍必須能接單');
    expect(vehicle.reviewStatus.name, 'approved');
  });
}
