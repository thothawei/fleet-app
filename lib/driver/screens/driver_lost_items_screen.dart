import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/fleet_api_client.dart' show ApiException;
import '../../core/models/models.dart';
import '../../core/util/money.dart';
import '../../shared/screens/ride_chat_screen.dart';
import '../driver_controller.dart';

/// 司機端遺失物協尋工作清單：乘客回報 → 標記尋獲 → 乘客付款 → 標記歸還。
class DriverLostItemsScreen extends StatelessWidget {
  const DriverLostItemsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DriverController>();
    final items = ctrl.lostItems;

    return Scaffold(
      appBar: AppBar(title: const Text('遺失物協尋')),
      body: RefreshIndicator(
        onRefresh: () => ctrl.refreshLostItems(),
        child: items.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        '目前沒有待處理的協尋',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ),
                ],
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                itemBuilder: (context, i) =>
                    _LostItemCard(ctrl: ctrl, item: items[i]),
              ),
      ),
    );
  }
}

class _LostItemCard extends StatelessWidget {
  const _LostItemCard({required this.ctrl, required this.item});

  final DriverController ctrl;
  final LostItemRequest item;

  Future<void> _run(
    BuildContext context,
    Future<LostItemRequest> Function() action,
  ) async {
    try {
      await action();
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  void _openChat(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RideChatScreen(
          rideId: item.rideId,
          selfRole: 'driver',
          title: '聯絡乘客（行程 #${item.rideId}）',
          loadHistory: ctrl.fetchMessages,
          send: ctrl.sendMessage,
          incoming: ctrl.chatStream,
          onVisibilityChanged: ctrl.setChatVisible,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('行程 #${item.rideId}', style: text.titleMedium),
                ),
                Chip(
                  label: Text(item.statusLabel),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('物品：${item.description}'),
            const SizedBox(height: 4),
            Text('處理費：${formatCentsAsNtd(item.feeCents)}（乘客支付）'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openChat(context),
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('聯絡乘客'),
                  ),
                ),
                const SizedBox(width: 8),
                if (item.status == LostItemStatus.open)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () =>
                          _run(context, () => ctrl.markLostItemFound(item.id)),
                      icon: const Icon(Icons.check),
                      label: const Text('已找到'),
                    ),
                  )
                else if (item.status == LostItemStatus.paid)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _run(
                          context, () => ctrl.markLostItemReturned(item.id)),
                      icon: const Icon(Icons.done_all),
                      label: const Text('已歸還'),
                    ),
                  )
                else
                  const Expanded(
                    child: Center(child: Text('等待乘客付款')),
                  ),
              ],
            ),
            if (item.status == LostItemStatus.open ||
                item.status == LostItemStatus.found) ...[
              const SizedBox(height: 4),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogCtx) => AlertDialog(
                      title: const Text('確定結案？'),
                      content: const Text('未尋獲結案後，乘客可再重新回報。'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(dialogCtx).pop(false),
                          child: const Text('返回'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(dialogCtx).pop(true),
                          child: const Text('確定結案'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true && context.mounted) {
                    await _run(context, () => ctrl.closeLostItem(item.id));
                  }
                },
                child: const Text('未尋獲，結案'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
