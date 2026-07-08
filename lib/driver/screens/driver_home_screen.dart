import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/util/maps.dart';
import '../driver_controller.dart';

class DriverHomeScreen extends StatelessWidget {
  const DriverHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DriverController>();

    return Scaffold(
      appBar: AppBar(
        title: Text('你好，${ctrl.session?.name ?? '司機'}'),
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
          _StatusCard(ctrl: ctrl),
          const SizedBox(height: 16),
          if (ctrl.activeRide != null) _ActiveRideCard(ctrl: ctrl),
          if (ctrl.pendingOffer != null) _OfferCard(ctrl: ctrl),
          if (ctrl.activeRide == null && ctrl.pendingOffer == null)
            _IdleHint(),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.ctrl});

  final DriverController ctrl;

  @override
  Widget build(BuildContext context) {
    final pos = ctrl.lastPosition;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  ctrl.online ? Icons.circle : Icons.circle_outlined,
                  color: ctrl.online ? Colors.green : Colors.grey,
                  size: 14,
                ),
                const SizedBox(width: 8),
                Text(
                  ctrl.online ? '上線中' : '離線',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                Switch(
                  value: ctrl.online,
                  onChanged: ctrl.loading ? null : (_) => ctrl.toggleOnline(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _InfoRow(
              label: 'WebSocket',
              value: ctrl.wsConnected ? '已連線' : '未連線',
            ),
            _InfoRow(label: 'API', value: AppConfig.apiBase),
            if (pos != null)
              _InfoRow(
                label: '位置',
                value:
                    '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}',
              ),
            if (ctrl.error != null) ...[
              const SizedBox(height: 8),
              Text(
                ctrl.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.ctrl});

  final DriverController ctrl;

  @override
  Widget build(BuildContext context) {
    final offer = ctrl.pendingOffer!;
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '新派單 #${offer.rideId}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text('上車點：${offer.address}'),
            if (offer.distM != null) Text('距離約 ${offer.distM} 公尺'),
            if (offer.etaLabel.isNotEmpty) Text('ETA ${offer.etaLabel}'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: ctrl.loading ? null : ctrl.dismissOffer,
                    child: const Text('略過'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: ctrl.loading ? null : ctrl.acceptOffer,
                    child: const Text('接單'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveRideCard extends StatelessWidget {
  const _ActiveRideCard({required this.ctrl});

  final DriverController ctrl;

  @override
  Widget build(BuildContext context) {
    final ride = ctrl.activeRide!;
    final phaseLabel = switch (ride.phase) {
      DriverRidePhase.enRouteToPickup => '前往上車點',
      DriverRidePhase.onTrip => '行程中',
      _ => '進行中',
    };

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
            Text(phaseLabel),
            const SizedBox(height: 4),
            Text('上車點：${ride.address}'),
            const SizedBox(height: 16),
            if (ride.phase == DriverRidePhase.enRouteToPickup) ...[
              FilledButton.icon(
                onPressed: () => openMapsNavigation(ride.address),
                icon: const Icon(Icons.navigation),
                label: const Text('Google Maps 導航'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: ctrl.loading ? null : ctrl.pickUpPassenger,
                child: const Text('乘客已上車'),
              ),
            ],
            if (ride.phase == DriverRidePhase.onTrip) ...[
              if (ride.dropoffAddress != null &&
                  ride.dropoffAddress!.isNotEmpty) ...[
                Text('目的地：${ride.dropoffAddress}'),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => openMapsNavigation(ride.dropoffAddress!),
                  icon: const Icon(Icons.navigation),
                  label: const Text('導航去目的地'),
                ),
                const SizedBox(height: 8),
              ],
              FilledButton(
                onPressed: ctrl.loading ? null : ctrl.completeTrip,
                child: const Text('完成行程'),
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: ctrl.loading ? null : ctrl.abandonTrip,
              child: const Text('放棄此單'),
            ),
          ],
        ),
      ),
    );
  }
}

class _IdleHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          '開啟「上線」後會每 ${AppConfig.locationIntervalSec} 秒回報 GPS，'
          '並透過 WebSocket 接收派單通知。',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
