import 'package:flutter/material.dart';

import '../driver_controller.dart';

/// 主畫面頂部大開關：一眼可讀上線狀態、一鍵切換（spec §3）
class OnlineHeroCard extends StatelessWidget {
  const OnlineHeroCard({required this.ctrl, super.key});

  final DriverController ctrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final online = ctrl.online;
    return Card(
      color: online ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(
              online ? Icons.local_taxi : Icons.power_settings_new,
              size: 40,
              color: online ? scheme.primary : scheme.outline,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    online ? '上線中' : '離線',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    online ? '等待派單中' : '目前不會收到派單',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            Transform.scale(
              scale: 1.3,
              child: Switch(
                value: online,
                onChanged: ctrl.loading ? null : (_) => ctrl.toggleOnline(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
