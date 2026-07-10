import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/models/models.dart';
import '../customer_controller.dart';
import '../screens/map_picker_screen.dart';

/// 配對中：進度動畫＋取消叫車。
class SearchingContent extends StatelessWidget {
  const SearchingContent({required this.ctrl, super.key});

  final CustomerController ctrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 16),
        Center(
          child: Text(
            '正在為您配對司機',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            '通常在 1 分鐘內完成',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: ctrl.busy ? null : () => ctrl.cancelOrder(),
          child: const Text('取消叫車'),
        ),
      ],
    );
  }
}

/// 司機途中／已抵達：司機名、ETA/距離 chip、取消。
class DriverEnRouteContent extends StatelessWidget {
  const DriverEnRouteContent({required this.ctrl, super.key});

  final CustomerController ctrl;

  List<Widget> _etaChips(BuildContext context, CustomerRide ride) {
    final chips = <Widget>[];
    if (ctrl.liveDistM != null) {
      chips.add(_chip(context, '距您約 ${ctrl.liveDistM} 公尺'));
    }
    final eta = ctrl.liveEtaSec;
    if (eta != null && eta > 0) {
      chips.add(_chip(context, '約 ${(eta / 60).ceil()} 分鐘抵達'));
    } else if (ride.etaLabel.isNotEmpty) {
      chips.add(_chip(context, ride.etaLabel));
    }
    return chips;
  }

  Widget _chip(BuildContext context, String label) {
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ride = ctrl.activeRide!;
    final arrived = ctrl.driverArrived;
    final chips = arrived ? <Widget>[] : _etaChips(context, ride);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ctrl.driverName != null) ...[
          Text(
            '司機：${ctrl.driverName}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
        ],
        if (arrived) ...[
          Text(
            '請與司機會合',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            '請盡快到上車點與司機會合',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ] else if (chips.isNotEmpty) ...[
          Wrap(spacing: 8, runSpacing: 4, children: chips),
        ] else ...[
          Text('司機前往中', style: Theme.of(context).textTheme.bodyMedium),
        ],
        if (ride.cancellable) ...[
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: ctrl.busy ? null : () => ctrl.cancelOrder(),
            child: const Text('取消叫車'),
          ),
        ],
      ],
    );
  }
}

/// 行程中：目的地、司機。
class OnTripContent extends StatelessWidget {
  const OnTripContent({required this.ctrl, super.key});

  final CustomerController ctrl;

  @override
  Widget build(BuildContext context) {
    final ride = ctrl.activeRide!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '行程進行中',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        if (ride.dropoffAddress != null) ...[
          Text('目的地：${ride.dropoffAddress}'),
          const SizedBox(height: 4),
        ],
        if (ctrl.driverName != null) Text('司機：${ctrl.driverName}'),
      ],
    );
  }
}

/// 完成卡：評分／費用 disabled 佔位＋再叫一輛。
class CompletedContent extends StatelessWidget {
  const CompletedContent({required this.ctrl, super.key});

  final CustomerController ctrl;

  @override
  Widget build(BuildContext context) {
    final summary = ctrl.completedSummary!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '行程已完成',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text('行程 #${summary.rideId}'),
        if (summary.driverName != null) ...[
          const SizedBox(height: 4),
          Text('司機：${summary.driverName}'),
        ],
        if (summary.dropoffAddress != null) ...[
          const SizedBox(height: 4),
          Text('目的地：${summary.dropoffAddress}'),
        ],
        const SizedBox(height: 12),
        Text(
          '評分與付款功能即將開放（後端 Phase C）。',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: null,
          icon: const Icon(Icons.star_outline),
          label: const Text('留下評分（即將開放）'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: null,
          icon: const Icon(Icons.receipt_long),
          label: const Text('查看費用（即將開放）'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => ctrl.dismissCompleted(),
          child: const Text('再叫一輛'),
        ),
      ],
    );
  }
}

/// 叫車表單：目的地優先（spec §2.1）。
class OrderFormContent extends StatefulWidget {
  const OrderFormContent({required this.ctrl, super.key});

  final CustomerController ctrl;

  @override
  State<OrderFormContent> createState() => _OrderFormContentState();
}

class _OrderFormContentState extends State<OrderFormContent> {
  final _pickup = TextEditingController();
  final _dropoff = TextEditingController();

  // 地圖選點得到的目的地座標；手動改地址即失效（避免地址與座標不一致）。
  double? _dropoffLat;
  double? _dropoffLng;

  @override
  void dispose() {
    _pickup.dispose();
    _dropoff.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.ctrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('要去哪裡？', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          '上車點以目前 GPS 定位；地址欄留空時自動帶入座標。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _dropoff,
          onChanged: (_) {
            // 手動編輯地址 → 丟棄地圖座標，改以地址下單
            if (_dropoffLat != null || _dropoffLng != null) {
              setState(() {
                _dropoffLat = null;
                _dropoffLng = null;
              });
            }
          },
          decoration: const InputDecoration(
            labelText: '目的地地址',
            prefixIcon: Icon(Icons.place),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: (ctrl.busy || !AppConfig.mapsConfigured)
              ? null
              : () => _pickOnMap(context),
          icon: const Icon(Icons.map),
          label: const Text('在地圖上選目的地'),
        ),
        if (!AppConfig.mapsConfigured) ...[
          const SizedBox(height: 4),
          Text(
            '地圖選點需設定 Google Maps API key（見 README），請直接輸入地址',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _pickup,
          decoration: const InputDecoration(
            labelText: '上車地址（選填）',
            prefixIcon: Icon(Icons.my_location),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: ctrl.busy ? null : () => _submit(context),
          icon: const Icon(Icons.local_taxi),
          label: Text(ctrl.busy ? '定位並叫車中…' : '叫車'),
        ),
      ],
    );
  }

  Future<void> _pickOnMap(BuildContext context) async {
    final pos = widget.ctrl.lastPosition;
    final picked = await Navigator.of(context).push<MapPickResult>(
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(
          initial: pos != null ? LatLng(pos.latitude, pos.longitude) : null,
        ),
      ),
    );
    if (picked != null && picked.address.isNotEmpty) {
      // 程式化設定 text 不會觸發 onChanged，故座標得以保留
      setState(() {
        _dropoff.text = picked.address;
        _dropoffLat = picked.lat;
        _dropoffLng = picked.lng;
      });
    }
  }

  Future<void> _submit(BuildContext context) async {
    if (_dropoff.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先輸入目的地地址')),
      );
      return;
    }
    await widget.ctrl.placeOrder(
      pickupAddress: _pickup.text,
      dropoffAddress: _dropoff.text,
      dropoffLat: _dropoffLat,
      dropoffLng: _dropoffLng,
    );
  }
}
