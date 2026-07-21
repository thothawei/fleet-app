import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/models/models.dart';
import '../../core/util/map_tiles.dart';
import '../../core/util/route_stops.dart';
import '../customer_controller.dart';
import '../widgets/ride_phase_content.dart';
import 'ride_history_screen.dart';

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
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
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
        return OrderFormContent(ctrl: ctrl);
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
        markers.add(_pin(
          LatLng(pickupLat, pickupLng),
          Icons.location_on,
          Colors.red,
        ));
      }
    }
    if (ctrl.liveDriverLat != null && ctrl.liveDriverLng != null) {
      markers.add(_pin(
        LatLng(ctrl.liveDriverLat!, ctrl.liveDriverLng!),
        Icons.local_taxi,
        Colors.green,
      ));
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
    return [
      Polyline(points: points, strokeWidth: 3, color: Colors.blueAccent),
    ];
  }

  /// 多停靠點的標記：**下一站全彩醒目、之後的站半透明、已到達灰色、已跳過不畫**
  /// ——與司機端概覽地圖同一套規則（`route_stops.dart`），兩端看到的路線才會一致。
  List<Marker> _stopMarkers(CustomerRide ride) {
    final visible = visibleRouteStops(ride.stops);
    final next = nextPendingStop(ride.stops);
    return [
      for (final s in visible)
        _stopPin(
          s,
          isNext: next != null && next.id == s.id,
        ),
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
