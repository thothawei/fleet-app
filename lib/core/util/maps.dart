import 'package:url_launcher/url_launcher.dart';

/// 組出 Google Maps 導航 deep link。
///
/// 有座標時以 `lat,lng` 為目標；地址字串在 Google Maps 上可能解析到同名的錯誤地點，
/// 座標才是後端 dropoff_point 的原始資料。無座標時退回地址搜尋。
Uri mapsNavigationUri(String address, {double? lat, double? lng}) {
  final query = (lat != null && lng != null) ? '$lat,$lng' : address;
  return Uri.parse(
    'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}',
  );
}

/// 開啟 Google Maps 導航。
Future<bool> openMapsNavigation(String address, {double? lat, double? lng}) {
  return launchUrl(
    mapsNavigationUri(address, lat: lat, lng: lng),
    mode: LaunchMode.externalApplication,
  );
}
