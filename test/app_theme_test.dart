import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/theme/app_theme.dart';

void main() {
  test('亮暗主題以 LINE 綠為 seed、Material 3', () {
    expect(kBrandGreen, const Color(0xFF06C755));
    expect(appLightTheme.useMaterial3, isTrue);
    expect(appLightTheme.brightness, Brightness.light);
    expect(appDarkTheme.brightness, Brightness.dark);
    // 深色模式 primary 用提亮綠（spec §1.1）
    expect(appDarkTheme.colorScheme.primary, const Color(0xFF3DD675));
  });

  test('主行動按鈕高度 token 為 56', () {
    expect(kPrimaryActionHeight, 56.0);
  });
}
