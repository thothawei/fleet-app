import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/config/app_config.dart';

/// 地圖選點結果：目的地地址（反查或座標字串）與精確座標。
class MapPickResult {
  const MapPickResult({
    required this.address,
    required this.lat,
    required this.lng,
  });

  final String address;
  final double lat;
  final double lng;
}

/// 地圖選點：拖動地圖點一下放釘、反查地址，確定後回傳地址與座標。
///
/// 需在原生層填入 Google Maps API key（AndroidManifest / iOS AppDelegate）才會
/// 顯示地圖；key 留空時本畫面地圖為空白，屬預期，叫車表單的文字輸入仍可用。
class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({super.key, this.initial});

  /// 進場時地圖中心（通常帶乘客目前 GPS 位置）；未提供時預設台北車站。
  final LatLng? initial;

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  static const _fallbackCenter = LatLng(25.0478, 121.5170); // 台北車站

  LatLng? _picked;
  String? _address;
  bool _geocoding = false;

  LatLng get _center => widget.initial ?? _fallbackCenter;

  Future<void> _onTap(LatLng pos) async {
    setState(() {
      _picked = pos;
      _geocoding = true;
      _address = null;
    });
    String label = _coordLabel(pos);
    try {
      final marks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (marks.isNotEmpty) {
        final resolved = _formatPlacemark(marks.first);
        if (resolved.isNotEmpty) label = resolved;
      }
    } catch (_) {
      // 反查失敗就退回座標字串
    }
    if (!mounted) return;
    setState(() {
      _address = label;
      _geocoding = false;
    });
  }

  String _coordLabel(LatLng p) =>
      '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}';

  String _formatPlacemark(Placemark m) {
    final parts = [
      m.administrativeArea,
      m.locality,
      m.subLocality,
      m.thoroughfare,
      m.subThoroughfare,
    ].where((s) => s != null && s.isNotEmpty).toList();
    return parts.join('');
  }

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.mapsConfigured) {
      return Scaffold(
        appBar: AppBar(title: const Text('選擇目的地')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              '地圖選點需設定 Google Maps API key（見 README），請返回改用地址輸入',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('選擇目的地')),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _center, zoom: 15),
            onTap: _onTap,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            markers: {
              if (_picked != null)
                Marker(
                  markerId: const MarkerId('dropoff'),
                  position: _picked!,
                ),
            },
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_picked == null)
                      const Text('在地圖上點一下選擇目的地')
                    else if (_geocoding)
                      const Text('查詢地址中…')
                    else
                      Text('目的地：${_address ?? _coordLabel(_picked!)}'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: (_picked == null || _geocoding)
                          ? null
                          : () => Navigator.of(context).pop(
                                MapPickResult(
                                  address: _address ?? _coordLabel(_picked!),
                                  lat: _picked!.latitude,
                                  lng: _picked!.longitude,
                                ),
                              ),
                      child: const Text('確定'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
