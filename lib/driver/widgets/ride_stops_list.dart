import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../core/util/maps.dart';
import '../driver_controller.dart';

/// 行程卡的停靠點清單（N6／N7）。
///
/// 單點訂單不顯示（`stops` 為空）——既有的「上車點／目的地」兩行畫面不受影響。
///
/// 每站給司機三件事：**是誰、在哪、處理了沒**；待處理的**下一站**額外給
/// 「已上車／已下車」與「跳過」按鈕，以及導航到該站的捷徑。
class RideStopsList extends StatelessWidget {
  const RideStopsList({required this.ctrl, required this.ride, super.key});

  final DriverController ctrl;
  final ActiveRide ride;

  Future<void> _confirmSkip(BuildContext context, RideStop stop) async {
    // 跳過會讓該段不計入車資，且**不可反悔**（後端條件式更新，已跳過就不能改回到達）。
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('跳過${stop.title}？'),
        content: const Text('確認乘客未出現。跳過後不可復原，該段路程也不會計入車資。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('確認跳過'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ctrl.markStopSkipped(stop.id);
  }

  @override
  Widget build(BuildContext context) {
    if (!ride.hasStops) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final next = ride.nextStop;

    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.alt_route, size: 20),
                const SizedBox(width: 8),
                Text('全程 ${ride.stops.length} 站', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            for (final s in ride.stops)
              _StopTile(
                stop: s,
                isNext: next != null && next.id == s.id,
                busy: ctrl.busy,
                onArrive: () => ctrl.markStopArrived(s.id),
                onSkip: () => _confirmSkip(context, s),
                // 有座標時以 lat,lng 為導航目標；地址僅為退路（同 mapsNavigationUri 的既有語意）。
                onNavigate: () =>
                    openMapsNavigation(s.address ?? '', lat: s.lat, lng: s.lng),
              ),
          ],
        ),
      ),
    );
  }
}

class _StopTile extends StatelessWidget {
  const _StopTile({
    required this.stop,
    required this.isNext,
    required this.busy,
    required this.onArrive,
    required this.onSkip,
    required this.onNavigate,
  });

  final RideStop stop;
  final bool isNext;
  final bool busy;
  final VoidCallback onArrive;
  final VoidCallback onSkip;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color) = switch (stop) {
      _ when stop.skipped => (Icons.block, theme.colorScheme.outline),
      _ when stop.arrived => (Icons.check_circle, theme.colorScheme.primary),
      _ when isNext => (Icons.radio_button_checked, theme.colorScheme.primary),
      _ => (Icons.radio_button_unchecked, theme.colorScheme.outline),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${stop.seq}. ${stop.title}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: isNext ? FontWeight.bold : FontWeight.normal,
                        // 已跳過的站用刪除線，一眼看出這站不去了。
                        decoration: stop.skipped ? TextDecoration.lineThrough : null,
                        color: stop.skipped ? theme.colorScheme.outline : null,
                      ),
                    ),
                    if (stop.address != null && stop.address!.isNotEmpty)
                      Text(
                        stop.address!,
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (stop.skipped)
                Text('已跳過', style: theme.textTheme.labelSmall)
              else if (stop.arrived)
                Text('已完成', style: theme.textTheme.labelSmall)
              else
                IconButton(
                  tooltip: '導航到這站',
                  onPressed: onNavigate,
                  icon: const Icon(Icons.navigation_outlined, size: 20),
                ),
            ],
          ),
          // 只有「下一站」給操作——一次只讓司機處理一件事，避免誤按到後面的站。
          if (isNext) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const SizedBox(width: 26),
                FilledButton.tonal(
                  // 全域主題的 minimumSize 是 Size.fromHeight（寬＝infinity），
                  // 在 Row（寬度無界）裡會炸掉整個 home 的 layout（模擬器實跑抓到，
                  // 例外只出現在 attach console、不進 logcat）。這裡覆寫回自適應寬。
                  style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
                  onPressed: busy ? null : onArrive,
                  child: Text(stop.kind == StopKind.pickup ? '已上車' : '已下車'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(64, 40)),
                  onPressed: busy ? null : onSkip,
                  child: const Text('跳過'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
