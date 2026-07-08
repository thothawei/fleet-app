import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../customer_controller.dart';

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
          if (ctrl.activeRide != null)
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
              decoration: const InputDecoration(
                labelText: '目的地地址',
                prefixIcon: Icon(Icons.place),
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
        ),
      ),
    );
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
    );
  }
}

class _ActiveRideCard extends StatelessWidget {
  const _ActiveRideCard({required this.ctrl});

  final CustomerController ctrl;

  @override
  Widget build(BuildContext context) {
    final ride = ctrl.activeRide!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '行程 #${ride.rideId}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(ride.statusLabel),
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
