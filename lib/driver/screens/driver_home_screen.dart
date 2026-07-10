import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/ride_status_colors.dart';
import '../../core/util/maps.dart';
import '../driver_controller.dart';
import '../widgets/connection_details_tile.dart';
import '../widgets/offer_overlay.dart';
import '../widgets/online_hero_card.dart';

class DriverHomeScreen extends StatelessWidget {
  const DriverHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DriverController>();

    return Stack(
      children: [
        Scaffold(
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
              OnlineHeroCard(ctrl: ctrl),
              const SizedBox(height: 12),
              if (ctrl.error != null) _ErrorBanner(message: ctrl.error!),
              if (ctrl.activeRide != null) _ActiveRideCard(ctrl: ctrl),
              if (ctrl.activeRide == null && ctrl.pendingOffer == null)
                _IdleHint(),
              const SizedBox(height: 12),
              ConnectionDetailsTile(ctrl: ctrl),
            ],
          ),
        ),
        if (ctrl.pendingOffer != null) OfferOverlay(ctrl: ctrl),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: scheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            message,
            style: TextStyle(color: scheme.onErrorContainer),
          ),
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
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final phaseLabel = switch (ride.phase) {
      DriverRidePhase.enRouteToPickup => '前往上車點',
      DriverRidePhase.onTrip => '行程中',
      _ => '進行中',
    };
    final primaryStyle = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(kPrimaryActionHeight),
      textStyle: text.titleMedium,
    );
    final secondaryStyle = OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(kPrimaryActionHeight),
    );

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
                    style: text.titleLarge,
                  ),
                ),
                Chip(
                  label: Text(phaseLabel),
                  backgroundColor:
                      driverPhaseColor(context, ride.phase).withValues(alpha: 0.15),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('上車點：${ride.address}'),
            const SizedBox(height: 16),
            if (ride.phase == DriverRidePhase.enRouteToPickup) ...[
              OutlinedButton.icon(
                onPressed: () => openMapsNavigation(ride.address),
                style: secondaryStyle,
                icon: const Icon(Icons.navigation),
                label: const Text('Google Maps 導航'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: ctrl.loading ? null : ctrl.pickUpPassenger,
                style: primaryStyle,
                child: const Text('乘客已上車'),
              ),
            ],
            if (ride.phase == DriverRidePhase.onTrip) ...[
              if (ride.dropoffAddress != null &&
                  ride.dropoffAddress!.isNotEmpty) ...[
                Text('目的地：${ride.dropoffAddress}'),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => openMapsNavigation(ride.dropoffAddress!),
                  style: secondaryStyle,
                  icon: const Icon(Icons.navigation),
                  label: const Text('導航去目的地'),
                ),
                const SizedBox(height: 8),
              ],
              FilledButton(
                onPressed: ctrl.loading ? null : ctrl.completeTrip,
                style: primaryStyle,
                child: const Text('完成行程'),
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: scheme.error),
              onPressed: ctrl.loading
                  ? null
                  : () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dialogCtx) => AlertDialog(
                          title: const Text('確定放棄這筆訂單？'),
                          content: const Text('放棄後這筆訂單會回到派單池。'),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogCtx).pop(false),
                              child: const Text('返回'),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.of(dialogCtx).pop(true),
                              child: const Text('確定放棄'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) await ctrl.abandonTrip();
                    },
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
          '上線後將自動回報位置並接收派單。',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
