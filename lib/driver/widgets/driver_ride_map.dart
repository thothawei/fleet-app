import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/util/map_tiles.dart';

/// 司機端行程概覽地圖（OSM 圖磚，免 API key）。
///
/// 只做「看位置」：標出司機自己與目標點（前往上車點時＝上車點；行程中＝目的地），
/// 並畫一條直線示意相對位置。**不做導航**——turn-by-turn 交給外部導航 App
/// （行程卡的導航按鈕），這裡只讓司機一眼看出方向與距離。
class DriverRideMap extends StatefulWidget {
  const DriverRideMap({
    super.key,
    required this.targetLat,
    required this.targetLng,
    required this.targetLabel,
    required this.targetIsPickup,
    this.driverLat,
    this.driverLng,
  });

  /// 目標點（上車點或目的地）座標。
  final double targetLat;
  final double targetLng;

  /// 目標點說明（無障礙標籤用）。
  final String targetLabel;

  /// true＝目標是上車點（紅釘）；false＝目的地（藍旗）。
  final bool targetIsPickup;

  /// 司機自己的即時位置；尚未取得 GPS fix 時為 null。
  final double? driverLat;
  final double? driverLng;

  @override
  State<DriverRideMap> createState() => _DriverRideMapState();
}

class _DriverRideMapState extends State<DriverRideMap> {
  final MapController _map = MapController();

  LatLng get _target => LatLng(widget.targetLat, widget.targetLng);

  LatLng? get _driver => (widget.driverLat != null && widget.driverLng != null)
      ? LatLng(widget.driverLat!, widget.driverLng!)
      : null;

  @override
  void didUpdateWidget(DriverRideMap old) {
    super.didUpdateWidget(old);
    // 目標換了（上車點→目的地）或司機移動 → 重新框住兩點。
    if (widget.targetLat != old.targetLat ||
        widget.targetLng != old.targetLng ||
        widget.driverLat != old.driverLat ||
        widget.driverLng != old.driverLng) {
      _fit();
    }
  }

  /// 同時框住司機與目標；只有一點時置中該點。build 期間不可動相機，排到下一影格。
  void _fit() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final driver = _driver;
      try {
        if (driver == null) {
          _map.move(_target, 15);
          return;
        }
        _map.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints([driver, _target]),
            padding: const EdgeInsets.all(40),
            maxZoom: 16,
          ),
        );
      } catch (_) {
        // 地圖尚未 layout，忽略；下次座標更新再框。
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final driver = _driver;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 200,
        child: FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: driver ?? _target,
            initialZoom: 14,
            onMapReady: _fit,
          ),
          children: [
            TileLayer(
              urlTemplate: osmTileUrl,
              userAgentPackageName: osmUserAgent,
            ),
            if (driver != null)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [driver, _target],
                    color: Theme.of(context).colorScheme.primary.withValues(
                          alpha: 0.6,
                        ),
                    strokeWidth: 3,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                Marker(
                  point: _target,
                  width: 40,
                  height: 40,
                  alignment: Alignment.topCenter,
                  child: Semantics(
                    label: widget.targetLabel,
                    child: Icon(
                      widget.targetIsPickup ? Icons.person_pin_circle : Icons.flag,
                      color: widget.targetIsPickup ? Colors.red : Colors.blue,
                      size: 36,
                    ),
                  ),
                ),
                if (driver != null)
                  Marker(
                    point: driver,
                    width: 40,
                    height: 40,
                    child: Semantics(
                      label: '我的位置',
                      child: const Icon(
                        Icons.local_taxi,
                        color: Colors.green,
                        size: 32,
                      ),
                    ),
                  ),
              ],
            ),
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
