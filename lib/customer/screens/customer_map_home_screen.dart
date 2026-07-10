import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/models/models.dart';
import '../customer_controller.dart';
import '../widgets/ride_phase_content.dart';

/// 地圖為底＋Bottom Sheet 主畫面（spec §2.1）；
/// 僅在 AppConfig.mapsConfigured 時使用，否則走 CustomerHomeScreen 卡片版。
class CustomerMapHomeScreen extends StatefulWidget {
  const CustomerMapHomeScreen({super.key});

  @override
  State<CustomerMapHomeScreen> createState() => _CustomerMapHomeScreenState();
}

class _CustomerMapHomeScreenState extends State<CustomerMapHomeScreen> {
  GoogleMapController? _map;
  double? _lastDriverLat;
  double? _lastDriverLng;

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CustomerController>();
    _maybeFollowDriver(ctrl);

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _initialTarget(ctrl),
              zoom: 15,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            onMapCreated: (c) => _map = c,
            markers: _markers(ctrl),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 16,
            child: FloatingActionButton.small(
              heroTag: 'logout',
              onPressed: ctrl.loading ? null : () => ctrl.logout(),
              child: const Icon(Icons.logout),
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
    _map?.animateCamera(CameraUpdate.newLatLng(LatLng(lat, lng)));
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

  Set<Marker> _markers(CustomerController ctrl) {
    final markers = <Marker>{};
    final ride = ctrl.activeRide;
    final pickupLat = ride?.pickupLat ?? ctrl.lastPosition?.latitude;
    final pickupLng = ride?.pickupLng ?? ctrl.lastPosition?.longitude;
    if (ride != null && pickupLat != null && pickupLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('pickup'),
        position: LatLng(pickupLat, pickupLng),
      ));
    }
    if (ctrl.liveDriverLat != null && ctrl.liveDriverLng != null) {
      markers.add(Marker(
        markerId: const MarkerId('driver'),
        position: LatLng(ctrl.liveDriverLat!, ctrl.liveDriverLng!),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ));
    }
    return markers;
  }
}
