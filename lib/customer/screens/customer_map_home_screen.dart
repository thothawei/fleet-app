import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/models/models.dart';
import '../../core/util/map_tiles.dart';
import '../../core/util/route_stops.dart';
import '../customer_controller.dart';
import '../widgets/lost_item_banner.dart';
import '../widgets/ride_phase_content.dart';
import 'ride_history_screen.dart';
import 'scheduled_rides_screen.dart';

/// 地圖為底＋Bottom Sheet 主畫面（spec §2.1）。
/// 圖磚走 OpenStreetMap（flutter_map），不需任何 API key。
class CustomerMapHomeScreen extends StatefulWidget {
  const CustomerMapHomeScreen({super.key});

  @override
  State<CustomerMapHomeScreen> createState() => _CustomerMapHomeScreenState();
}

class _CustomerMapHomeScreenState extends State<CustomerMapHomeScreen> {
  final MapController _map = MapController();
  double? _lastDriverLat;
  double? _lastDriverLng;

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CustomerController>();
    _maybeFollowDriver(ctrl);
    _maybeShowError(ctrl);

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _initialTarget(ctrl),
              initialZoom: 15,
            ),
            children: [
              TileLayer(
                urlTemplate: osmTileUrl,
                userAgentPackageName: osmUserAgent,
              ),
              // 多停靠點行程畫出「司機→下一站→之後待處理站」的順序線；
              // 單點訂單沒有 stops → 空 list → 不畫（畫面與先前一致）。
              PolylineLayer(polylines: _routeLines(ctrl)),
              MarkerLayer(markers: _markers(ctrl)),
            ],
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 16,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'history',
                  tooltip: '我的行程',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const CustomerRideHistoryScreen(),
                    ),
                  ),
                  child: const Icon(Icons.receipt_long),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.small(
                  heroTag: 'schedules',
                  tooltip: '預約司機',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ScheduledRidesScreen(),
                    ),
                  ),
                  child: const Icon(Icons.event),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.small(
                  heroTag: 'logout',
                  tooltip: '登出',
                  onPressed: ctrl.loading ? null : () => ctrl.logout(),
                  child: const Icon(Icons.logout),
                ),
              ],
            ),
          ),
          DraggableScrollableSheet(
            initialChildSize: 0.42,
            minChildSize: 0.25,
            maxChildSize: 0.85,
            builder: (context, scrollCtrl) => DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                boxShadow: const [
                  BoxShadow(blurRadius: 12, color: Colors.black26),
                ],
              ),
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 進行中的遺失物協尋（WS 即時更新狀態）。
                  // 放在階段內容**之前**且不受行程狀態影響——協尋單掛在「已完成的上一趟」，
                  // 乘客可能同時已經在叫下一趟；而且完成卡一關掉就沒有別的入口了，
                  // 沒有這塊，司機標記「已尋獲」後乘客根本無處付處理費把東西拿回來。
                  for (final item in ctrl.lostItems) ...[
                    LostItemBanner(item: item),
                    const SizedBox(height: 12),
                  ],
                  // 即將到來的預約（只顯示最近一筆）。放在協尋之後、階段內容之前：
                  // 它是「等一下會發生的事」，比正在編輯的叫車表單優先度低，
                  // 但乘客一拉開 sheet 就該看得到。
                  if (ctrl.upcomingSchedules.isNotEmpty) ...[
                    _UpcomingScheduleTile(
                      schedule: ctrl.upcomingSchedules.first,
                    ),
                    const SizedBox(height: 12),
                  ],
                  _sheetContent(ctrl),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _maybeFollowDriver(CustomerController ctrl) {
    final lat = ctrl.liveDriverLat;
    final lng = ctrl.liveDriverLng;
    if (lat == null || lng == null) return;
    if (lat == _lastDriverLat && lng == _lastDriverLng) return;
    _lastDriverLat = lat;
    _lastDriverLng = lng;
    // build 期間不可直接動相機；排到下一影格，並容錯 map 尚未 ready。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _map.move(LatLng(lat, lng), _map.camera.zoom);
      } catch (_) {
        // 地圖尚未完成第一次 layout，忽略這次跟隨，下一筆座標再補。
      }
    });
  }

  /// 把 controller 的錯誤呈現出來。**沒有這段，叫車的每一種失敗都是靜默的**——
  /// 權限被拒、定位取不到、建單 API 失敗（含 token 失效、後端離線），
  /// 使用者按下「叫車」後畫面只會轉一下又回到原樣，完全不知道發生什麼事
  /// （2026-07-22 模擬器實跑重現：拒絕定位權限與停掉後端兩條路徑都零回饋）。
  ///
  /// 顯示後**清掉 error**：留著會讓「同一個錯誤第二次發生」被去重邏輯吃掉，
  /// 使用者再按一次又變回沒有回饋。
  void _maybeShowError(CustomerController ctrl) {
    final error = ctrl.error;
    if (error == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      ctrl.clearError();
    });
  }

  Widget _sheetContent(CustomerController ctrl) {
    if (ctrl.completedSummary != null) return CompletedContent(ctrl: ctrl);
    final ride = ctrl.activeRide;
    if (ride == null) return OrderFormContent(ctrl: ctrl);
    switch (ride.status) {
      case RideStatus.requested:
      case RideStatus.assigned:
        return SearchingContent(ctrl: ctrl);
      case RideStatus.accepted:
        return DriverEnRouteContent(ctrl: ctrl);
      case RideStatus.pickedUp:
        return OnTripContent(ctrl: ctrl);
      default:
        // 走到這裡代表「有一張還沒進終態的訂單，但狀態碼 App 不認得」——
        // 終態的訂單根本不會到這裡（controller 會把 activeRide 清成 null）。
        // **不可以退回叫車表單**：那會把進行中的訂單藏起來，還請乘客去按一個
        // 必定被「已有進行中訂單」擋下的按鈕。
        return UnknownPhaseContent(ctrl: ctrl);
    }
  }

  LatLng _initialTarget(CustomerController ctrl) {
    final pos = ctrl.lastPosition;
    if (pos != null) return LatLng(pos.latitude, pos.longitude);
    return const LatLng(25.0330, 121.5654);
  }

  List<Marker> _markers(CustomerController ctrl) {
    final markers = <Marker>[];
    final ride = ctrl.activeRide;
    // N8：多停靠點行程畫全程；單點訂單維持原本的「一支上車點紅釘」。
    if (ride != null && ride.hasStops) {
      markers.addAll(_stopMarkers(ride));
    } else {
      final pickupLat = ride?.pickupLat ?? ctrl.lastPosition?.latitude;
      final pickupLng = ride?.pickupLng ?? ctrl.lastPosition?.longitude;
      if (ride != null && pickupLat != null && pickupLng != null) {
        markers.add(
          _pin(LatLng(pickupLat, pickupLng), Icons.location_on, Colors.red),
        );
      }
    }
    if (ctrl.liveDriverLat != null && ctrl.liveDriverLng != null) {
      markers.add(
        _pin(
          LatLng(ctrl.liveDriverLat!, ctrl.liveDriverLng!),
          Icons.local_taxi,
          Colors.green,
        ),
      );
    }
    return markers;
  }

  List<Polyline> _routeLines(CustomerController ctrl) {
    final ride = ctrl.activeRide;
    if (ride == null || !ride.hasStops) return const [];
    final driver = (ctrl.liveDriverLat != null && ctrl.liveDriverLng != null)
        ? LatLng(ctrl.liveDriverLat!, ctrl.liveDriverLng!)
        : null;
    final points = routePolylinePoints(driver, ride.stops);
    if (points.isEmpty) return const [];
    return [Polyline(points: points, strokeWidth: 3, color: Colors.blueAccent)];
  }

  /// 多停靠點的標記：**下一站全彩醒目、之後的站半透明、已到達灰色、已跳過不畫**
  /// ——與司機端概覽地圖同一套規則（`route_stops.dart`），兩端看到的路線才會一致。
  List<Marker> _stopMarkers(CustomerRide ride) {
    final visible = visibleRouteStops(ride.stops);
    final next = nextPendingStop(ride.stops);
    return [
      for (final s in visible)
        _stopPin(s, isNext: next != null && next.id == s.id),
    ];
  }

  Marker _stopPin(RideStop s, {required bool isNext}) {
    final arrived = s.arrived;
    final color = arrived
        ? Colors.grey
        : (s.kind == StopKind.pickup ? Colors.red : Colors.blue);
    return Marker(
      point: LatLng(s.lat, s.lng),
      width: 64,
      height: 56,
      alignment: Alignment.topCenter,
      child: Opacity(
        // 之後的站淡一點：一眼看出「現在要去的是哪一個」。
        opacity: arrived || isNext ? 1 : 0.55,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              arrived ? Icons.check_circle : Icons.place,
              color: color,
              size: isNext ? 34 : 28,
            ),
            // 乘客標籤（A/B…）讓同行的人知道哪一站是自己的。
            Text(
              s.passengerLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isNext ? FontWeight.bold : FontWeight.normal,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Marker _pin(LatLng point, IconData icon, Color color) => Marker(
    point: point,
    width: 40,
    height: 40,
    alignment: Alignment.topCenter,
    child: Icon(icon, color: color, size: 36),
  );

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }
}

/// Bottom Sheet 裡的「即將到來的預約」列。
///
/// 只提醒下一趟是什麼時候，詳細操作在預約頁——sheet 的空間要留給正在進行的事。
class _UpcomingScheduleTile extends StatelessWidget {
  const _UpcomingScheduleTile({required this.schedule});

  final ScheduledRide schedule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.event),
        title: Text('已預約 ${formatScheduleTime(schedule.scheduledAt)}'),
        subtitle: Text(
          schedule.dropoffAddress == null
              ? schedule.pickupAddress
              : '${schedule.pickupAddress} → ${schedule.dropoffAddress}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ScheduledRidesScreen()),
        ),
      ),
    );
  }
}
