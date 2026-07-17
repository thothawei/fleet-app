import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/models.dart';
import '../../core/util/money.dart';
import '../driver_controller.dart';

/// 司機收入頁（E1）：月切換，顯示趟數、營業額、手續費、實得、月會費、應付總公司。
class DriverEarningsScreen extends StatefulWidget {
  const DriverEarningsScreen({super.key});

  @override
  State<DriverEarningsScreen> createState() => _DriverEarningsScreenState();
}

class _DriverEarningsScreenState extends State<DriverEarningsScreen> {
  late DateTime _month; // 該月 1 號
  Future<DriverEarnings>? _future;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _load();
  }

  void _load() {
    final ctrl = context.read<DriverController>();
    setState(() {
      _future = ctrl.fetchEarnings(_monthStr);
    });
  }

  String get _monthStr =>
      '${_month.year.toString().padLeft(4, '0')}-${_month.month.toString().padLeft(2, '0')}';

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的收入')),
      body: Column(
        children: [
          _MonthSelector(
            label: _monthStr,
            onPrev: () => _shiftMonth(-1),
            // 不允許查未來月份
            onNext: _isCurrentMonth ? null : () => _shiftMonth(1),
          ),
          Expanded(
            child: FutureBuilder<DriverEarnings>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _ErrorRetry(
                    message: snapshot.error.toString(),
                    onRetry: _load,
                  );
                }
                final data = snapshot.data;
                if (data == null) {
                  return const SizedBox.shrink();
                }
                return _EarningsBody(data: data);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthSelector extends StatelessWidget {
  const _MonthSelector({
    required this.label,
    required this.onPrev,
    required this.onNext,
  });

  final String label;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left),
            tooltip: '上個月',
          ),
          Text(label, style: Theme.of(context).textTheme.titleMedium),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
            tooltip: '下個月',
          ),
        ],
      ),
    );
  }
}

class _EarningsBody extends StatelessWidget {
  const _EarningsBody({required this.data});

  final DriverEarnings data;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _Row(label: '完成趟數', value: '${data.tripCount} 趟'),
                const Divider(),
                _Row(label: '營業額', value: formatCentsAsNtd(data.totalRevenueCents)),
                _Row(label: '手續費', value: '- ${formatCentsAsNtd(data.totalCommissionCents)}'),
                // 清潔費分項（O6）：營業額不含它、抽成也不含它，但實得含它——
                // 少了這一列，「營業額 − 手續費」就對不上實得，司機會以為算錯。
                // 只在真的有加收時顯示，避免每個月都掛一列 NT$0。
                if (data.totalCleaningFeeCents > 0)
                  _Row(
                    label: '寵物車清潔費',
                    value: '+ ${formatCentsAsNtd(data.totalCleaningFeeCents)}',
                  ),
                _Row(
                  label: '司機實得',
                  value: formatCentsAsNtd(data.driverNetCents),
                  emphasize: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _Row(label: '月會費', value: formatCentsAsNtd(data.membershipFeeCents)),
                _Row(label: '手續費', value: formatCentsAsNtd(data.totalCommissionCents)),
                const Divider(),
                _Row(
                  label: '應付總公司',
                  value: formatCentsAsNtd(data.owedToHqCents),
                  emphasize: true,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.emphasize = false});

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final style = emphasize
        ? text.titleMedium?.copyWith(color: scheme.primary, fontWeight: FontWeight.bold)
        : text.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: emphasize ? style : text.bodyMedium),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: scheme.error, size: 40),
            const SizedBox(height: 12),
            Text('載入收入失敗：$message', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('重試')),
          ],
        ),
      ),
    );
  }
}
