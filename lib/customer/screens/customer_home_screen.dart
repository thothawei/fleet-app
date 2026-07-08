import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/models/models.dart';
import '../customer_controller.dart';
import 'map_picker_screen.dart';

class CustomerHomeScreen extends StatelessWidget {
  const CustomerHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CustomerController>();

    return Scaffold(
      appBar: AppBar(
        title: Text('你好，${ctrl.session?.name ?? '乘客'}'),
        actions: [
          IconButton(
            tooltip: '登出',
            onPressed: ctrl.loading ? null : () => ctrl.logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (ctrl.error != null) ...[
            Text(
              ctrl.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
          ],
          if (ctrl.completedSummary != null)
            _CompletedRideCard(ctrl: ctrl)
          else if (ctrl.activeRide != null)
            _ActiveRideCard(ctrl: ctrl)
          else
            _OrderForm(ctrl: ctrl),
        ],
      ),
    );
  }
}

class _OrderForm extends StatefulWidget {
  const _OrderForm({required this.ctrl});

  final CustomerController ctrl;

  @override
  State<_OrderForm> createState() => _OrderFormState();
}

class _OrderFormState extends State<_OrderForm> {
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('叫車', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '上車點以目前 GPS 定位；地址欄留空時自動帶入座標。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pickup,
              decoration: const InputDecoration(
                labelText: '上車地址（選填）',
                prefixIcon: Icon(Icons.my_location),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
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
              onPressed: ctrl.busy ? null : () => _pickOnMap(context),
              icon: const Icon(Icons.map),
              label: const Text('在地圖上選目的地'),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: ctrl.busy ? null : () => _submit(context),
              icon: const Icon(Icons.local_taxi),
              label: Text(ctrl.busy ? '定位並叫車中…' : '叫車'),
            ),
          ],
        ),
      ),
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

class _CompletedRideCard extends StatelessWidget {
  const _CompletedRideCard({required this.ctrl});

  final CustomerController ctrl;

  @override
  Widget build(BuildContext context) {
    final summary = ctrl.completedSummary!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
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
        ),
      ),
    );
  }
}

class _ActiveRideCard extends StatelessWidget {
  const _ActiveRideCard({required this.ctrl});

  final CustomerController ctrl;

  /// 司機前往上車點時的即時提示，優先用 driver.location 帶來的即時距離/ETA，
  /// 無即時值時退回訂單接單時的 ETA。
  String _approachText(CustomerController ctrl, CustomerRide ride) {
    final parts = <String>[];
    if (ctrl.liveDistM != null) parts.add('距您約 ${ctrl.liveDistM} 公尺');
    final eta = ctrl.liveEtaSec;
    if (eta != null && eta > 0) {
      parts.add('約 ${(eta / 60).ceil()} 分鐘抵達');
    } else if (ride.etaLabel.isNotEmpty) {
      parts.add(ride.etaLabel);
    }
    return parts.isEmpty ? '司機前往中' : '司機 ${parts.join(' · ')}';
  }

  String? _phaseHint(CustomerRide ride) {
    switch (ride.status) {
      case RideStatus.requested:
      case RideStatus.assigned:
        return '正在為您配對司機，請稍候';
      case RideStatus.accepted:
        if (ctrl.driverArrived) return '請盡快到上車點與司機會合';
        return _approachText(ctrl, ride);
      case RideStatus.pickedUp:
        return '行程進行中，祝您旅途愉快';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = ctrl.activeRide!;
    final phase = ride.phaseLabel(driverArrived: ctrl.driverArrived);
    final hint = _phaseHint(ride);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '行程 #${ride.rideId}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Icon(
                  ctrl.wsConnected ? Icons.wifi : Icons.wifi_off,
                  size: 16,
                  color: ctrl.wsConnected ? Colors.green : Colors.grey,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              phase,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(hint, style: Theme.of(context).textTheme.bodyMedium),
            ],
            if (ctrl.driverName != null) ...[
              const SizedBox(height: 4),
              Text('司機：${ctrl.driverName}'),
            ],
            if (ride.dropoffAddress != null) ...[
              const SizedBox(height: 4),
              Text('目的地：${ride.dropoffAddress}'),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: ctrl.busy ? null : () => ctrl.refreshActive(),
              icon: const Icon(Icons.refresh),
              label: const Text('更新狀態'),
            ),
            if (ride.cancellable) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: ctrl.busy ? null : () => ctrl.cancelOrder(),
                child: const Text('取消叫車'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
