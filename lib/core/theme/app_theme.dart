import 'package:flutter/material.dart';

/// LINE 綠品牌主色（spec §1.1，三端統一）
const kBrandGreen = Color(0xFF06C755);

/// 深色模式提亮綠——深底上維持對比
const kBrandGreenDark = Color(0xFF3DD675);

/// 主行動按鈕最小高度（駕駛情境大觸控目標，spec §3）
const kPrimaryActionHeight = 56.0;

/// 卡片統一圓角
const kCardRadius = 12.0;

ThemeData _base(Brightness brightness) {
  var scheme = ColorScheme.fromSeed(
    seedColor: kBrandGreen,
    brightness: brightness,
  );
  if (brightness == Brightness.dark) {
    scheme = scheme.copyWith(primary: kBrandGreenDark);
  }
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    cardTheme: CardThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kCardRadius),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kCardRadius),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kCardRadius),
        ),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
  );
}

final appLightTheme = _base(Brightness.light);
final appDarkTheme = _base(Brightness.dark);
