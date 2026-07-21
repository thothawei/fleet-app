import 'package:latlong2/latlong.dart';

import '../models/models.dart';

/// 多停靠點行程在地圖上的共用規則（司機端概覽地圖與乘客端追蹤地圖都吃這一份）。
///
/// 放在 core 而不是各自複製：兩端對「哪些站要畫、下一站是哪個」的判斷若各寫一套，
/// 遲早會出現司機看到 A、乘客看到 B 的情況。

/// 地圖上要顯示的停靠點：**已跳過的不畫**——乘客沒出現、司機不會再去，
/// 畫出來只會誤導路線；清單仍以刪除線保留紀錄。
List<RideStop> visibleRouteStops(List<RideStop> stops) =>
    stops.where((s) => !s.skipped).toList();

/// 下一個待處理的停靠點（與 ActiveRide.nextStop 同語意；stops 已依 seq 排序）。
RideStop? nextPendingStop(List<RideStop> stops) {
  for (final s in stops) {
    if (s.pending) return s;
  }
  return null;
}

/// 路線折線的點序：司機 → 下一站 → 之後的待處理站。
///
/// 已到達的站在身後，畫進線裡會讓路線看起來要走回頭路，故只串待處理的站；
/// 不足兩點（無線可畫）回空 list。
List<LatLng> routePolylinePoints(LatLng? driver, List<RideStop> stops) {
  final points = <LatLng>[
    ?driver,
    for (final s in stops)
      if (s.pending) LatLng(s.lat, s.lng),
  ];
  return points.length < 2 ? const [] : points;
}
