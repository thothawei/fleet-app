import 'package:flutter/material.dart';

import '../../core/models/models.dart';

/// 乘客端的多停靠點行程進度（N8）。
///
/// 單點訂單不顯示（`stops` 為空）——既有畫面不變。
///
/// 與司機端 `RideStopsList` 的差別：**這裡完全唯讀**。
/// 乘客不能標記到站，只需要知道「走到哪一站、下一站是誰」，
/// 所以不放任何操作鈕，也不顯示導航捷徑。
class RideStopsProgress extends StatelessWidget {
  const RideStopsProgress({required this.ride, super.key});

  final CustomerRide ride;

  @override
  Widget build(BuildContext context) {
    if (!ride.hasStops) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final next = ride.nextStop;

    return Card(
      margin: const EdgeInsets.only(top: 12, bottom: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.alt_route, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    // 進度用「已處理／全部」表示；跳過的站也算處理完（司機不會再回去）。
                    '行程進度 ${ride.handledStopCount}／${ride.stops.length} 站',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            if (next != null) ...[
              const SizedBox(height: 4),
              Text(
                '下一站：${next.title}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
            const SizedBox(height: 8),
            for (final s in ride.stops)
              _StopRow(stop: s, isNext: next != null && next.id == s.id),
          ],
        ),
      ),
    );
  }
}

class _StopRow extends StatelessWidget {
  const _StopRow({required this.stop, required this.isNext});

  final RideStop stop;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, color, note) = switch (stop) {
      // 跳過＝乘客沒出現、司機不會再去。講「未搭乘」而不是「跳過」——
      // 「跳過」是司機視角的動作，乘客看到的應該是結果。
      _ when stop.skipped => (Icons.block, theme.colorScheme.outline, '未搭乘'),
      _ when stop.arrived => (Icons.check_circle, theme.colorScheme.primary, '已完成'),
      _ when isNext => (Icons.radio_button_checked, theme.colorScheme.primary, ''),
      _ => (Icons.radio_button_unchecked, theme.colorScheme.outline, ''),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
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
          if (note.isNotEmpty) Text(note, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}
