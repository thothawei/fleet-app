import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/models.dart';
import '../customer_controller.dart';
import '../widgets/lost_item_banner.dart';
import '../widgets/customer_tracking_map.dart';
import '../widgets/ride_phase_content.dart';
import 'scheduled_rides_screen.dart';

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  String? _lastShownError;

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CustomerController>();
    _maybeShowErrorSnackBar(context, ctrl.error);

    return Scaffold(
      appBar: AppBar(
        title: Text('你好，${ctrl.session?.name ?? '乘客'}'),
        actions: [
          IconButton(
            tooltip: '預約司機',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ScheduledRidesScreen()),
            ),
            icon: const Icon(Icons.event),
          ),
          IconButton(
            tooltip: '登出',
            onPressed: ctrl.loading ? null : () => ctrl.logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await ctrl.refreshActive();
          await ctrl.refreshLostItems();
          await ctrl.loadScheduledRides(silent: true);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (ctrl.completedSummary != null)
              _CompletedRideCard(ctrl: ctrl)
            else if (ctrl.activeRide != null)
              _ActiveRideCard(ctrl: ctrl)
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: OrderFormContent(ctrl: ctrl),
                ),
              ),
            // 即將到來的預約。**只顯示最近一筆**——首頁是「現在要做什麼」的地方，
            // 把整份預約清單攤在這裡會把叫車表單推到看不見的位置。
            if (ctrl.upcomingSchedules.isNotEmpty) ...[
              const SizedBox(height: 12),
              _UpcomingScheduleCard(schedule: ctrl.upcomingSchedules.first),
            ],
            // 進行中的遺失物協尋（WS 即時更新狀態）
            for (final item in ctrl.lostItems) ...[
              const SizedBox(height: 12),
              LostItemBanner(item: item),
            ],
          ],
        ),
      ),
    );
  }

  void _maybeShowErrorSnackBar(BuildContext context, String? error) {
    if (error == null) {
      _lastShownError = null;
      return;
    }
    if (error == _lastShownError) return;
    _lastShownError = error;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    });
  }
}


class _CompletedRideCard extends StatelessWidget {
  const _CompletedRideCard({required this.ctrl});

  final CustomerController ctrl;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: CompletedContent(ctrl: ctrl),
      ),
    );
  }
}

class _ActiveRideCard extends StatelessWidget {
  const _ActiveRideCard({required this.ctrl});

  final CustomerController ctrl;

  bool _showTrackingMap(CustomerRide ride, CustomerController ctrl) {
    if (ride.status != RideStatus.accepted || ctrl.driverArrived) return false;
    final hasPickup = (ride.pickupLat != null && ride.pickupLng != null) ||
        ctrl.lastPosition != null;
    return hasPickup;
  }

  Widget _phaseWidget(CustomerRide ride) {
    switch (ride.status) {
      case RideStatus.requested:
      case RideStatus.assigned:
        return SearchingContent(ctrl: ctrl);
      case RideStatus.accepted:
        return DriverEnRouteContent(ctrl: ctrl);
      case RideStatus.pickedUp:
        return OnTripContent(ctrl: ctrl);
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = ctrl.activeRide!;
    final phase = ride.phaseLabel(driverArrived: ctrl.driverArrived);
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
            const SizedBox(height: 12),
            _phaseWidget(ride),
            if (_showTrackingMap(ride, ctrl)) ...[
              const SizedBox(height: 12),
              CustomerTrackingMap(
                pickupLat: ride.pickupLat ?? ctrl.lastPosition!.latitude,
                pickupLng: ride.pickupLng ?? ctrl.lastPosition!.longitude,
                driverLat: ctrl.liveDriverLat,
                driverLng: ctrl.liveDriverLng,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 首頁的「即將到來的預約」卡：只提醒下一趟是什麼時候，詳細操作在預約頁。
class _UpcomingScheduleCard extends StatelessWidget {
  const _UpcomingScheduleCard({required this.schedule});

  final ScheduledRide schedule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.event),
        title: Text('已預約 ${formatScheduleTime(schedule.scheduledAt)}'),
        subtitle: Text(
          schedule.dropoffAddress == null
              ? schedule.pickupAddress
              : '${schedule.pickupAddress} → ${schedule.dropoffAddress}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ScheduledRidesScreen()),
        ),
      ),
    );
  }
}
