import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/models/models.dart';
import '../../core/util/map_tiles.dart';
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
    final pickupLat = ride?.pickupLat ?? ctrl.lastPosition?.latitude;
    final pickupLng = ride?.pickupLng ?? ctrl.lastPosition?.longitude;
    if (ride != null && pickupLat != null && pickupLng != null) {
      markers.add(_pin(
        LatLng(pickupLat, pickupLng),
        Icons.location_on,
        Colors.red,
      ));
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
