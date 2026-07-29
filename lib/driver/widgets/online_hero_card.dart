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
    // 上線但 WS 斷線＝實際收不到派單。若照樣顯示「等待派單中」，司機會以為自己在接單，
    // 其實派單根本進不來（實跑遇過：WS Connection timed out，畫面卻一切正常）。
    final offlineDespiteOnline = online && !ctrl.wsConnected;
    // 弱網（連得上但通不了）：WS 看起來還連著（凍結的後端不會送 FIN），可是位置回報
    // 已經超過後端的鮮度窗——他早就不是派單候選了。這時仍寫「等待派單中」，
    // 就是把「上線」與「收得到單」混為一談，和 WS 斷線同一種謊。
    final staleLocation = online && ctrl.locationStale;
    final degraded = offlineDespiteOnline || staleLocation;
    return Card(
      color: degraded
          ? scheme.errorContainer
          : (online ? scheme.primaryContainer : scheme.surfaceContainerHighest),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(
              degraded
                  ? Icons.cloud_off
                  : (online ? Icons.local_taxi : Icons.power_settings_new),
              size: 40,
              color: degraded
                  ? scheme.error
                  : (online ? scheme.primary : scheme.outline),
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
                    offlineDespiteOnline
                        ? '連線中斷，暫時收不到派單'
                        : staleLocation
                            ? '位置回報失敗，暫時收不到派單'
                            : (online ? '等待派單中' : '目前不會收到派單'),
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
