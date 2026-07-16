import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/util/map_tiles.dart';

/// 乘客端：司機前往上車點時的地圖追蹤（上車點 + 司機 marker）。
/// 圖磚走 OpenStreetMap（flutter_map），不需 API key。
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
  final MapController _map = MapController();

  @override
  void didUpdateWidget(CustomerTrackingMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.driverLat != oldWidget.driverLat ||
        widget.driverLng != oldWidget.driverLng) {
      _maybeFollowDriver();
    }
  }

  void _maybeFollowDriver() {
    final lat = widget.driverLat;
    final lng = widget.driverLng;
    if (lat == null || lng == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _map.move(LatLng(lat, lng), _map.camera.zoom);
      } catch (_) {
        // 地圖尚未 layout，忽略這次跟隨。
      }
    });
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[
      _pin(LatLng(widget.pickupLat, widget.pickupLng), Icons.location_on,
          Colors.green),
    ];
    final dLat = widget.driverLat;
    final dLng = widget.driverLng;
    if (dLat != null && dLng != null) {
      markers.add(_pin(LatLng(dLat, dLng), Icons.local_taxi, Colors.blue));
    }
    return markers;
  }

  Marker _pin(LatLng point, IconData icon, Color color) => Marker(
        point: point,
        width: 40,
        height: 40,
        alignment: Alignment.topCenter,
        child: Icon(icon, color: color, size: 32),
      );

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
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 220,
        child: FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: _initialTarget(),
            initialZoom: 14,
          ),
          children: [
            TileLayer(
              urlTemplate: osmTileUrl,
              userAgentPackageName: osmUserAgent,
            ),
            MarkerLayer(markers: _buildMarkers()),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }
}
