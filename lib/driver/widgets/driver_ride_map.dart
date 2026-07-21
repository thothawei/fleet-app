import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/models/models.dart';
import '../../core/util/map_tiles.dart';
import '../../core/util/route_stops.dart';

/// 司機端行程概覽地圖（OSM 圖磚，免 API key）。
///
/// 只做「看位置」：標出司機自己與目標，並畫線示意相對位置。**不做導航**——
/// turn-by-turn 交給外部導航 App（行程卡的導航按鈕），這裡只讓司機一眼看出方向與距離。
///
/// 兩種模式：
/// - 單點訂單：目標點一個（前往上車點＝上車點；行程中＝目的地）。
/// - 多停靠點（N，`stops` 非空）：依序畫出全程停靠點並以折線串起，
///   **下一站全彩醒目、之後的站半透明、已到達的灰色**——與 RideStopsList
///   「一次一件事」同一原則，司機掃一眼就知道現在要去哪。
class DriverRideMap extends StatefulWidget {
  const DriverRideMap({
    super.key,
    this.targetLat,
    this.targetLng,
    this.targetLabel = '',
    this.targetIsPickup = false,
    this.stops = const [],
    this.driverLat,
    this.driverLng,
  });

  /// 單點模式的目標點（上車點或目的地）座標；多停靠點模式下不使用。
  /// 呼叫端保證：stops 為空時必須帶目標座標（無目標也無 stops ＝ 沒東西可標）。
  final double? targetLat;
  final double? targetLng;

  /// 目標點說明（無障礙標籤用）。
  final String targetLabel;

  /// true＝目標是上車點（紅釘）；false＝目的地（藍旗）。
  final bool targetIsPickup;

  /// 多停靠點行程的全程（依 seq 排序）；空 ＝ 單點模式。
  final List<RideStop> stops;

  /// 司機自己的即時位置；尚未取得 GPS fix 時為 null。
  final double? driverLat;
  final double? driverLng;

  @override
  State<DriverRideMap> createState() => _DriverRideMapState();
}

class _DriverRideMapState extends State<DriverRideMap> {
  final MapController _map = MapController();

  bool get _multiStop => widget.stops.isNotEmpty;

  List<RideStop> get _visibleStops => visibleRouteStops(widget.stops);

  LatLng? get _target => (widget.targetLat != null && widget.targetLng != null)
      ? LatLng(widget.targetLat!, widget.targetLng!)
      : null;

  LatLng? get _driver => (widget.driverLat != null && widget.driverLng != null)
      ? LatLng(widget.driverLat!, widget.driverLng!)
      : null;

  /// 停靠點的「狀態指紋」：到站／跳過標記後要重新框景。
  String _stopsKey(List<RideStop> stops) =>
      stops.map((s) => '${s.id}:${s.arrived}:${s.skipped}').join(',');

  @override
  void didUpdateWidget(DriverRideMap old) {
    super.didUpdateWidget(old);
    // 目標換了（上車點→目的地）、司機移動或停靠點狀態變了 → 重新框景。
    if (widget.targetLat != old.targetLat ||
        widget.targetLng != old.targetLng ||
        widget.driverLat != old.driverLat ||
        widget.driverLng != old.driverLng ||
        _stopsKey(widget.stops) != _stopsKey(old.stops)) {
      _fit();
    }
  }

  /// 框住司機與所有目標點；只有一點時置中該點。build 期間不可動相機，排到下一影格。
  void _fit() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final points = <LatLng>[
        ?_driver,
        if (_multiStop)
          ..._visibleStops.map((s) => LatLng(s.lat, s.lng))
        else
          ?_target,
      ];
      if (points.isEmpty) return;
      try {
        if (points.length == 1) {
          _map.move(points.single, 15);
          return;
        }
        _map.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(points),
            padding: const EdgeInsets.all(40),
            maxZoom: 16,
          ),
        );
      } catch (_) {
        // 地圖尚未 layout，忽略；下次座標更新再框。
      }
    });
  }

  /// 多停靠點模式的停靠點 marker：下一站全彩、之後半透明、已到達灰色。
  List<Marker> _stopMarkers(BuildContext context) {
    final next = nextPendingStop(widget.stops);
    return [
      for (final s in _visibleStops)
        Marker(
          point: LatLng(s.lat, s.lng),
          width: 44,
          height: 52,
          alignment: Alignment.topCenter,
          child: _StopMarker(
            stop: s,
            isNext: next != null && s.id == next.id,
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final driver = _driver;
    final polyPoints = _multiStop
        ? routePolylinePoints(driver, widget.stops)
        : (driver != null && _target != null
            ? [driver, _target!]
            : const <LatLng>[]);
    final initialCenter = driver ??
        (_multiStop && _visibleStops.isNotEmpty
            ? LatLng(_visibleStops.first.lat, _visibleStops.first.lng)
            : _target ?? const LatLng(0, 0));
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 200,
        child: FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: initialCenter,
            initialZoom: 14,
            onMapReady: _fit,
          ),
          children: [
            TileLayer(
              urlTemplate: osmTileUrl,
              userAgentPackageName: osmUserAgent,
            ),
            if (polyPoints.isNotEmpty)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: polyPoints,
                    color: Theme.of(context).colorScheme.primary.withValues(
                          alpha: 0.6,
                        ),
                    strokeWidth: 3,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                if (_multiStop)
                  ..._stopMarkers(context)
                else if (_target != null)
                  Marker(
                    point: _target!,
                    width: 40,
                    height: 40,
                    alignment: Alignment.topCenter,
                    child: Semantics(
                      label: widget.targetLabel,
                      child: Icon(
                        widget.targetIsPickup
                            ? Icons.person_pin_circle
                            : Icons.flag,
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

/// 單一停靠點的 marker：圖示依上／下車，狀態決定顏色與大小，下方帶乘客標籤。
class _StopMarker extends StatelessWidget {
  const _StopMarker({required this.stop, required this.isNext});

  final RideStop stop;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final isPickup = stop.kind == StopKind.pickup;
    final baseColor = isPickup ? Colors.red : Colors.blue;
    // 已到達＝灰色（處理完）；下一站＝全彩；之後的站＝半透明（還沒輪到）。
    final color = stop.arrived
        ? Colors.grey
        : (isNext ? baseColor : baseColor.withValues(alpha: 0.45));
    final status = stop.arrived ? '已完成' : (isNext ? '下一站' : '');
    return Semantics(
      label: '$status${stop.title}'.trim(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isPickup ? Icons.person_pin_circle : Icons.flag,
            color: color,
            size: isNext ? 34 : 26,
          ),
          if (stop.passengerLabel.isNotEmpty)
            Text(
              stop.passengerLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
        ],
      ),
    );
  }
}
