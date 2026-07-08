import 'dart:io';

import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// 司機上線前確保定位與（Android 13+）通知權限，供前景服務常駐通知使用。
Future<bool> ensureDriverLocationPermissions() async {
  var perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) {
    perm = await Geolocator.requestPermission();
  }
  if (perm == LocationPermission.denied ||
      perm == LocationPermission.deniedForever) {
    return false;
  }

  if (Platform.isAndroid) {
    // 前景服務通知：Android 13+ 需 POST_NOTIFICATIONS，否則 FGS 可能無法啟動。
    final notif = await Permission.notification.status;
    if (notif.isDenied || notif.isLimited) {
      await Permission.notification.request();
    }
    // 有 whileInUse 即可搭配前景服務在切 App 時持續回報；always 為加分項。
    if (perm == LocationPermission.whileInUse) {
      final always = await Permission.locationAlways.status;
      if (always.isDenied) {
        await Permission.locationAlways.request();
      }
    }
  }

  perm = await Geolocator.checkPermission();
  return perm == LocationPermission.always ||
      perm == LocationPermission.whileInUse;
}
