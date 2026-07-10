import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../driver_controller.dart';

/// 新派單全螢幕接單卡：大字資訊＋大觸控目標（spec §3）
class OfferOverlay extends StatelessWidget {
  const OfferOverlay({required this.ctrl, super.key});

  final DriverController ctrl;

  @override
  Widget build(BuildContext context) {
    final offer = ctrl.pendingOffer!;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      color: scheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Text(
                '新派單',
                style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                '#${offer.rideId}',
                style: text.titleMedium?.copyWith(color: scheme.outline),
              ),
              const SizedBox(height: 24),
              _InfoBlock(
                icon: Icons.my_location,
                label: '上車點',
                value: offer.address,
              ),
              if (offer.dropoffAddress != null &&
                  offer.dropoffAddress!.isNotEmpty) ...[
                const SizedBox(height: 16),
                _InfoBlock(
                  icon: Icons.place,
                  label: '目的地',
                  value: offer.dropoffAddress!,
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  if (offer.distM != null)
                    Chip(label: Text('距離約 ${offer.distM} 公尺')),
                  if (offer.etaLabel.isNotEmpty)
                    Chip(label: Text('ETA ${offer.etaLabel}')),
                ],
              ),
              const Spacer(),
              FilledButton(
                onPressed: ctrl.loading ? null : ctrl.acceptOffer,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(kPrimaryActionHeight),
                  textStyle: text.titleLarge,
                ),
                child: const Text('接單'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: ctrl.loading ? null : ctrl.dismissOffer,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(kPrimaryActionHeight),
                ),
                child: const Text('略過'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: text.bodySmall),
              Text(value, style: text.titleLarge),
            ],
          ),
        ),
      ],
    );
  }
}
