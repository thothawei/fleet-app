import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/models.dart';
import '../../core/util/money.dart';
import '../../shared/screens/ride_chat_screen.dart';
import '../customer_controller.dart';

/// 「我的行程」歷史列表（留言板入口補遺）。
///
/// 過去行程沒有其他對話入口——這裡讓乘客事後（例如想起有東西忘在車上、
/// 或對車資有疑問）仍能聯絡當時的司機。**只有派到司機的行程**才給「聯絡司機」，
/// 派單前就取消的行程沒有對象可聯絡。
class CustomerRideHistoryScreen extends StatefulWidget {
  const CustomerRideHistoryScreen({super.key});

  @override
  State<CustomerRideHistoryScreen> createState() =>
      _CustomerRideHistoryScreenState();
}

class _CustomerRideHistoryScreenState extends State<CustomerRideHistoryScreen> {
  @override
  void initState() {
    super.initState();
    // build 期間不可改 provider 狀態，排到下一影格。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CustomerController>().loadRideHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CustomerController>();
    return Scaffold(
      appBar: AppBar(title: const Text('我的行程')),
      body: RefreshIndicator(
        onRefresh: ctrl.loadRideHistory,
        child: _body(context, ctrl),
      ),
    );
  }

  Widget _body(BuildContext context, CustomerController ctrl) {
    if (ctrl.historyLoading && ctrl.rideHistory.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (ctrl.historyError != null && ctrl.rideHistory.isEmpty) {
      return _ErrorState(
        message: ctrl.historyError!,
        onRetry: ctrl.loadRideHistory,
      );
    }
    if (ctrl.rideHistory.isEmpty) {
      // ListView 而非 Center，讓下拉刷新在空清單也能觸發。
      return ListView(
        children: [
          const SizedBox(height: 120),
          Center(
            child: Text(
              '還沒有行程紀錄',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: ctrl.rideHistory.length,
      itemBuilder: (context, i) =>
          _RideHistoryCard(ctrl: ctrl, ride: ctrl.rideHistory[i]),
    );
  }
}

class _RideHistoryCard extends StatelessWidget {
  const _RideHistoryCard({required this.ctrl, required this.ride});

  final CustomerController ctrl;
  final CustomerRideSummary ride;

  static const _months = [
    '', '1月', '2月', '3月', '4月', '5月', '6月',
    '7月', '8月', '9月', '10月', '11月', '12月',
  ];

  String _dateLabel() {
    final t = ride.completedAt ?? ride.requestedAt;
    if (t == null) return '';
    final local = t.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${_months[local.month]}${local.day}日 $hh:$mm';
  }

  void _openChat(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RideChatScreen(
          rideId: ride.rideId,
          selfRole: 'customer',
          title: '聯絡司機（行程 #${ride.rideId}）',
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
    final theme = Theme.of(context);
    final date = _dateLabel();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '行程 #${ride.rideId}',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Chip(
                  label: Text(ride.statusLabel),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            if (date.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(date, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 10),
            _RouteRow(
              icon: Icons.my_location,
              label: ride.pickupAddress.isEmpty ? '上車點' : ride.pickupAddress,
            ),
            if (ride.dropoffAddress != null) ...[
              const SizedBox(height: 4),
              _RouteRow(icon: Icons.place, label: ride.dropoffAddress!),
            ],
            if (ride.driverName != null) ...[
              const SizedBox(height: 8),
              Text('司機：${ride.driverName}', style: theme.textTheme.bodyMedium),
            ],
            if (ride.fareAmountCents != null) ...[
              const SizedBox(height: 4),
              Text(
                '車資 ${formatCentsAsNtd(ride.fareAmountCents!)}',
                style: theme.textTheme.bodyMedium,
              ),
            ],
            // 有派到司機才給對話入口——這是本畫面存在的理由（事後聯絡）。
            if (ride.hasDriver) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => _openChat(context),
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: const Text('聯絡司機'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  const _RouteRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.outline),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label, style: theme.textTheme.bodyMedium),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 100),
        const Center(child: Icon(Icons.cloud_off, size: 40)),
        const SizedBox(height: 12),
        Center(child: Text(message, textAlign: TextAlign.center)),
        const SizedBox(height: 16),
        Center(
          child: FilledButton.icon(
            onPressed: () => onRetry(),
            icon: const Icon(Icons.refresh),
            label: const Text('重試'),
          ),
        ),
      ],
    );
  }
}
