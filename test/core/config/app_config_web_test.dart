@TestOn('browser')
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/config/app_config.dart';

/// 這支測試必須在瀏覽器裡跑才有意義：
///
/// ```bash
/// flutter test --platform chrome test/core/config/app_config_web_test.dart
/// ```
///
/// 一般的 `flutter test` 跑在 Dart VM 上，`kIsWeb` 恆為 false，
/// 把 AppConfig 裡的 kIsWeb 防線整條拔掉也不會紅——那種測試等於沒有。
/// `@TestOn('browser')` 讓 VM 執行時直接跳過，不會偽裝成通過。
void main() {
  test('確認真的跑在 web 上，否則本檔的斷言沒有意義', () {
    expect(kIsWeb, isTrue);
  });

  test('沒帶 --dart-define=API_BASE 時，apiBase 不會碰到 dart:io', () {
    // 防線被拔掉的話，這裡會噴
    // 「Unsupported operation: Platform._operatingSystem」。
    expect(AppConfig.apiBase, 'http://localhost:8080');
  });

  test('wsBase 由 apiBase 推導，同樣不得碰到 dart:io', () {
    expect(AppConfig.wsBase, 'ws://localhost:8080');
  });
}
