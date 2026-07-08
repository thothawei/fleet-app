import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/config/app_config.dart';

/// 乘客端：司機前往上車點時的地圖追蹤（上車點 + 司機 marker）。
class CustomerTrackingMap extends StatefulWidget {
  const CustomerTrackingMap({
    super.key,
    required this.pickupLat,
    required this.pickupLng,
    this.driverLat,
    this.driverLng,
  });

  final double pickupLat;
  final double pickupLng;
  final double? driverLat;
  final double? driverLng;

  @override
  State<CustomerTrackingMap> createState() => _CustomerTrackingMapState();
}

class _CustomerTrackingMapState extends State<CustomerTrackingMap> {
  GoogleMapController? _mapController;

  @override
  void didUpdateWidget(CustomerTrackingMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.driverLat != oldWidget.driverLat ||
        widget.driverLng != oldWidget.driverLng) {
      _maybeFollowDriver();
    }
  }

  Future<void> _maybeFollowDriver() async {
    final lat = widget.driverLat;
    final lng = widget.driverLng;
    if (_mapController == null || lat == null || lng == null) return;
    await _mapController!.animateCamera(
      CameraUpdate.newLatLng(LatLng(lat, lng)),
    );
  }

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('pickup'),
        position: LatLng(widget.pickupLat, widget.pickupLng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: '上車點'),
      ),
    };
    final dLat = widget.driverLat;
    final dLng = widget.driverLng;
    if (dLat != null && dLng != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('driver'),
          position: LatLng(dLat, dLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: '司機'),
        ),
      );
    }
    return markers;
  }

  LatLng _initialTarget() {
    final dLat = widget.driverLat;
    final dLng = widget.driverLng;
    if (dLat != null && dLng != null) {
      return LatLng(
        (widget.pickupLat + dLat) / 2,
        (widget.pickupLng + dLng) / 2,
      );
    }
    return LatLng(widget.pickupLat, widget.pickupLng);
  }

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.mapsConfigured) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          '地圖追蹤需設定 Google Maps API key（見 README）',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 220,
        child: GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _initialTarget(),
            zoom: 14,
          ),
          markers: _buildMarkers(),
          myLocationEnabled: false,
          zoomControlsEnabled: false,
          onMapCreated: (c) {
            _mapController = c;
            _maybeFollowDriver();
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}
