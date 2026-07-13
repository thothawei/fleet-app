import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/fleet_api_client.dart' show ApiException;
import '../../core/models/models.dart';
import '../../core/util/money.dart';
import '../../shared/screens/ride_chat_screen.dart';
import '../customer_controller.dart';

/// 乘客端遺失物協尋：對已完成行程回報遺失 → 顯示處理費 → 與司機即時對話 →
/// 司機尋獲後支付處理費 → 等待歸還。
class CustomerLostItemScreen extends StatefulWidget {
  const CustomerLostItemScreen({required this.rideId, super.key});

  final int rideId;

  @override
  State<CustomerLostItemScreen> createState() => _CustomerLostItemScreenState();
}

class _CustomerLostItemScreenState extends State<CustomerLostItemScreen> {
  final _description = TextEditingController();
  LostItemRequest? _item;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final ctrl = context.read<CustomerController>();
    try {
      final item = await ctrl.fetchLostItemByRide(widget.rideId);
      if (!mounted) return;
      setState(() {
        _item = item;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  Future<void> _run(Future<LostItemRequest> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final item = await action();
      if (!mounted) return;
      setState(() {
        _item = item;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openChat() {
    final ctrl = context.read<CustomerController>();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RideChatScreen(
          rideId: widget.rideId,
          selfRole: 'customer',
          title: '聯絡司機',
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
    // watch：WS lost_item.updated 讓 controller 清單更新時，同步刷新本頁狀態。
    final ctrl = context.watch<CustomerController>();
    LostItemRequest? item = _item;
    if (item != null) {
      final idx = ctrl.lostItems.indexWhere((e) => e.id == item!.id);
      if (idx >= 0) {
        item = ctrl.lostItems[idx];
      } else if (item.isActive && !_loading) {
        // 本頁認知仍是未結案、但清單已移除 → 已被結案（returned/closed），回查一次終態。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _load();
        });
      }
    }
    // final 區域變數才能在閉包內維持 null 提升（item 有再賦值，提升會失效）。
    final current = item;

    return Scaffold(
      appBar: AppBar(title: Text('遺失物協尋（行程 #${widget.rideId}）')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null) ...[
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (current == null)
                  _ReportForm(
                    description: _description,
                    busy: _busy,
                    onSubmit: () {
                      final ctrl = context.read<CustomerController>();
                      _run(() => ctrl.reportLostItem(
                            widget.rideId,
                            _description.text,
                          ));
                    },
                  )
                else
                  _ItemDetail(
                    item: current,
                    busy: _busy,
                    onChat: _openChat,
                    onPay: () {
                      final ctrl = context.read<CustomerController>();
                      _run(() => ctrl.payLostItem(current.id));
                    },
                    onClose: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dialogCtx) => AlertDialog(
                          title: const Text('取消協尋？'),
                          content: const Text('取消後這張協尋單會結案。'),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogCtx).pop(false),
                              child: const Text('返回'),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.of(dialogCtx).pop(true),
                              child: const Text('確定取消'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true && context.mounted) {
                        final ctrl = context.read<CustomerController>();
                        await _run(() => ctrl.closeLostItem(current.id));
                      }
                    },
                  ),
              ],
            ),
    );
  }
}

/// 回報表單：描述遺失物品。
class _ReportForm extends StatelessWidget {
  const _ReportForm({
    required this.description,
    required this.busy,
    required this.onSubmit,
  });

  final TextEditingController description;
  final bool busy;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('物品遺失了嗎？', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '描述遺失的物品，我們會通知司機協尋。司機尋獲後需支付協尋處理費'
              '（依該趟車資的一定比例計算，送出後即可看到金額）。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: description,
              maxLines: 3,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: '物品描述（例：黑色錢包掉在後座）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: busy ? null : onSubmit,
              icon: const Icon(Icons.search),
              label: Text(busy ? '送出中…' : '送出協尋請求'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 協尋單詳情＋依狀態顯示動作。
class _ItemDetail extends StatelessWidget {
  const _ItemDetail({
    required this.item,
    required this.busy,
    required this.onChat,
    required this.onPay,
    required this.onClose,
  });

  final LostItemRequest item;
  final bool busy;
  final VoidCallback onChat;
  final VoidCallback onPay;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final canPay = item.status == LostItemStatus.found;
    final canClose = item.status == LostItemStatus.open ||
        item.status == LostItemStatus.found;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('協尋單 #${item.id}', style: text.titleLarge)),
                Chip(label: Text(item.statusLabel)),
              ],
            ),
            const SizedBox(height: 8),
            Text('物品：${item.description}'),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('協尋處理費', style: text.titleMedium),
                Text(
                  formatCentsAsNtd(item.feeCents),
                  style: text.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              item.status == LostItemStatus.open
                  ? '司機確認尋獲後即可付款，付款後司機會安排歸還。'
                  : item.status == LostItemStatus.found
                      ? '司機已找到您的物品，付款後即可安排歸還。'
                      : item.status == LostItemStatus.paid
                          ? '已付款，請與司機約定歸還方式。'
                          : '',
              style: text.bodySmall,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onChat,
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('與司機對話'),
            ),
            if (canPay) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: busy ? null : onPay,
                icon: const Icon(Icons.payment),
                label: Text('支付處理費 ${formatCentsAsNtd(item.feeCents)}'),
              ),
            ],
            if (canClose) ...[
              const SizedBox(height: 8),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                onPressed: busy ? null : onClose,
                child: const Text('取消協尋'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
