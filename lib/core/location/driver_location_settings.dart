import 'dart:io';

import 'package:geolocator/geolocator.dart';

import '../config/app_config.dart';

/// 司機上線時的定位設定：Android 啟用前景服務常駐通知，切到導航/鎖屏仍回報 GPS。
LocationSettings driverLocationSettings() {
  if (Platform.isAndroid) {
    return AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
      intervalDuration: Duration(seconds: AppConfig.locationIntervalSec),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: '派車服務 — 司機上線中',
        notificationText: '切到導航或鎖屏仍會持續回報位置',
        notificationChannelName: '司機定位回報',
        enableWakeLock: true,
        setOngoing: true,
      ),
    );
  }
  if (Platform.isIOS) {
    return AppleSettings(
      accuracy: LocationAccuracy.high,
      activityType: ActivityType.automotiveNavigation,
      pauseLocationUpdatesAutomatically: false,
      showBackgroundLocationIndicator: true,
    );
  }
  return const LocationSettings(accuracy: LocationAccuracy.high);
}
