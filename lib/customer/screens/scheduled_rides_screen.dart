import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/models/models.dart';
import '../../shared/widgets/rune_limit.dart';
import '../customer_controller.dart';
import '../widgets/saved_places_bar.dart';
import 'map_picker_screen.dart';

/// 預約司機：我的預約清單＋建立新預約。
class ScheduledRidesScreen extends StatefulWidget {
  const ScheduledRidesScreen({super.key});

  @override
  State<ScheduledRidesScreen> createState() => _ScheduledRidesScreenState();
}

class _ScheduledRidesScreenState extends State<ScheduledRidesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctrl = context.read<CustomerController>();
      ctrl.loadScheduledRides();
      // 常用地點是建立預約時的快捷來源，順手載一份（失敗就沒有快捷鈕，不擋預約）。
      ctrl.loadSavedPlaces(silent: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CustomerController>();
    final upcoming = ctrl.upcomingSchedules;
    // 已轉單的**不算過往**——車正在來的路上。把它跟已取消／未成立混在同一區，
    // 乘客會以為那筆預約已經結束了。
    final dispatched = [
      for (final s in ctrl.scheduledRides)
        if (s.isDispatched) s,
    ];
    final past = [
      for (final s in ctrl.scheduledRides)
        if (!s.isUpcoming && !s.isDispatched) s,
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('預約司機')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createSchedule(context),
        icon: const Icon(Icons.event),
        label: const Text('新增預約'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ctrl.loadScheduledRides(),
        child: ctrl.schedulesLoading && ctrl.scheduledRides.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  if (ctrl.schedulesError != null) ...[
                    _ScheduleErrorBanner(
                      message: ctrl.schedulesError!,
                      onRetry: () => ctrl.loadScheduledRides(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (ctrl.scheduleLeadMinutes > 0)
                    Text(
                      '我們會在約定時間前 ${ctrl.scheduleLeadMinutes} 分鐘開始為你找車。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: 16),
                  if (upcoming.isEmpty && dispatched.isEmpty && past.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(child: Text('還沒有任何預約。')),
                    ),
                  if (upcoming.isNotEmpty) ...[
                    Text('即將到來', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    for (final s in upcoming)
                      ScheduledRideCard(
                        schedule: s,
                        onCancel: () => _cancel(context, s),
                      ),
                    const SizedBox(height: 24),
                  ],
                  if (dispatched.isNotEmpty) ...[
                    Text('車已在路上',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    for (final s in dispatched) ScheduledRideCard(schedule: s),
                    const SizedBox(height: 24),
                  ],
                  if (past.isNotEmpty) ...[
                    Text('過往預約', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    for (final s in past) ScheduledRideCard(schedule: s),
                  ],
                ],
              ),
      ),
    );
  }

  Future<void> _cancel(BuildContext context, ScheduledRide s) async {
    final ctrl = context.read<CustomerController>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('取消預約'),
        content: Text('要取消 ${formatScheduleTime(s.scheduledAt)} 的預約嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('先不要'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('取消預約'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final error = await ctrl.cancelScheduledRide(s.id);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(error ?? '預約已取消')));
  }

  Future<void> _createSchedule(BuildContext context) async {
    final ctrl = context.read<CustomerController>();
    final messenger = ScaffoldMessenger.of(context);
    final draft = await Navigator.of(context).push<_ScheduleDraft>(
      MaterialPageRoute(builder: (_) => const _ScheduleEditorScreen()),
    );
    if (draft == null) return;
    final error = await ctrl.createScheduledRide(
      scheduledAt: draft.at,
      pickupLat: draft.pickupLat,
      pickupLng: draft.pickupLng,
      pickupAddress: draft.pickupAddress,
      dropoffAddress: draft.dropoffAddress,
      dropoffLat: draft.dropoffLat,
      dropoffLng: draft.dropoffLng,
      note: draft.note,
    );
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(error ?? '已預約 ${formatScheduleTime(draft.at)}'),
      ),
    );
  }
}

/// 單筆預約卡。可取消時才給取消鈕——已轉單的要取消的是那張訂單，不是這筆紀錄。
class ScheduledRideCard extends StatelessWidget {
  const ScheduledRideCard({required this.schedule, this.onCancel, super.key});

  final ScheduledRide schedule;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(_statusIcon, size: 18, color: _statusColor(context)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    formatScheduleTime(schedule.scheduledAt),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  schedule.statusLabel,
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: _statusColor(context)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _Line(icon: Icons.my_location, text: schedule.pickupAddress),
            if (schedule.dropoffAddress != null) ...[
              const SizedBox(height: 4),
              _Line(icon: Icons.place, text: schedule.dropoffAddress!),
            ],
            // 車種顯示名由前端對應（見 VehicleType 的說明：後端一律只送 code）。
            // 未知 code 整行不顯示——顯示原始 code 對乘客沒有意義，
            // 顯示「—」也只是把空洞畫出來。
            if (VehicleType.fromCode(schedule.requiredVehicleType) != null) ...[
              const SizedBox(height: 4),
              _Line(
                icon: Icons.directions_car,
                text: '指定車種：'
                    '${VehicleType.fromCode(schedule.requiredVehicleType)!.label}',
              ),
            ],
            if (schedule.note.isNotEmpty) ...[
              const SizedBox(height: 4),
              _Line(icon: Icons.sticky_note_2, text: schedule.note),
            ],
            // 已轉單：告訴乘客車已經在找了，以及要取消得去哪裡取消。
            if (schedule.isDispatched) ...[
              const SizedBox(height: 8),
              Text(
                '已為你建立訂單${schedule.rideId != null ? ' #${schedule.rideId}' : ''}，'
                '要取消請到首頁取消該趟行程。',
                style: theme.textTheme.bodySmall,
              ),
            ],
            // 失敗：把後端記下的原因如實給乘客，不要只寫「預約失敗」。
            if (schedule.isFailed && schedule.lastError.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '原因：${schedule.lastError}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            if (onCancel != null && schedule.cancellable) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onCancel,
                icon: const Icon(Icons.event_busy),
                label: const Text('取消預約'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData get _statusIcon {
    if (schedule.isDispatched) return Icons.local_taxi;
    if (schedule.isCancelled) return Icons.event_busy;
    if (schedule.isFailed) return Icons.error_outline;
    return Icons.schedule;
  }

  Color _statusColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (schedule.isFailed) return scheme.error;
    if (schedule.isDispatched) return scheme.primary;
    if (schedule.isCancelled) return scheme.outline;
    return scheme.secondary;
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 6),
        Expanded(child: Text(text)),
      ],
    );
  }
}

class _ScheduleErrorBanner extends StatelessWidget {
  const _ScheduleErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(message,
                style: TextStyle(color: scheme.onErrorContainer)),
          ),
          TextButton(onPressed: onRetry, child: const Text('重試')),
        ],
      ),
    );
  }
}

/// 預約表單的回傳值。
class _ScheduleDraft {
  const _ScheduleDraft({
    required this.at,
    required this.pickupAddress,
    required this.pickupLat,
    required this.pickupLng,
    this.dropoffAddress,
    this.dropoffLat,
    this.dropoffLng,
    this.note = '',
  });

  final DateTime at;
  final String pickupAddress;
  final double pickupLat;
  final double pickupLng;
  final String? dropoffAddress;
  final double? dropoffLat;
  final double? dropoffLng;
  final String note;
}

/// 建立預約的表單：時間 → 上車點 → 目的地 → 備註。
class _ScheduleEditorScreen extends StatefulWidget {
  const _ScheduleEditorScreen();

  @override
  State<_ScheduleEditorScreen> createState() => _ScheduleEditorScreenState();
}

class _ScheduleEditorScreenState extends State<_ScheduleEditorScreen> {
  DateTime? _at;
  String? _pickupAddress;
  double? _pickupLat;
  double? _pickupLng;
  String? _dropoffAddress;
  double? _dropoffLat;
  double? _dropoffLng;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  bool get _ready =>
      _at != null &&
      _pickupLat != null &&
      _pickupLng != null &&
      (_pickupAddress ?? '').isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CustomerController>();
    return Scaffold(
      appBar: AppBar(title: const Text('新增預約')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('什麼時候用車？', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.schedule),
              title: Text(_at == null ? '選擇時間' : formatScheduleTime(_at!)),
              subtitle: Text('最早可預約 ${ctrl.scheduleMinLeadMinutes} 分鐘後'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickDateTime,
            ),
          ),
          const SizedBox(height: 20),
          if (ctrl.savedPlaces.isNotEmpty) ...[
            SavedPlacesBar(
              ctrl: ctrl,
              title: '從常用地點帶入上車點',
              onPick: (p) => setState(() {
                _pickupAddress = p.address;
                _pickupLat = p.lat;
                _pickupLng = p.lng;
              }),
            ),
            const SizedBox(height: 12),
          ],
          Text('從哪裡上車？', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.my_location),
              title: Text(_pickupAddress ?? '在地圖上選上車點'),
              trailing: const Icon(Icons.map),
              onTap: () => _pickPoint(isPickup: true),
            ),
          ),
          const SizedBox(height: 20),
          if (ctrl.savedPlaces.isNotEmpty) ...[
            SavedPlacesBar(
              ctrl: ctrl,
              title: '從常用地點帶入目的地',
              onPick: (p) => setState(() {
                _dropoffAddress = p.address;
                _dropoffLat = p.lat;
                _dropoffLng = p.lng;
              }),
            ),
            const SizedBox(height: 12),
          ],
          Text('要去哪裡？（選填）',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.place),
              title: Text(_dropoffAddress ?? '在地圖上選目的地'),
              trailing: const Icon(Icons.map),
              onTap: () => _pickPoint(isPickup: false),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _note,
            // 與後端 maxScheduleNoteRunes（200）對齊，且數的是 rune 不是 grapheme
            // （見 RuneLimitingTextInputFormatter 的說明）。
            inputFormatters: const [RuneLimitingTextInputFormatter(200)],
            maxLength: 200,
            maxLengthEnforcement: MaxLengthEnforcement.none,
            buildCounter: runeCounter(200, _note),
            decoration: const InputDecoration(
              labelText: '給司機的備註（選填）',
              hintText: '例如：有一件大行李',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _ready ? _submit : null,
            icon: const Icon(Icons.event_available),
            label: const Text('建立預約'),
          ),
          if (!_ready) ...[
            const SizedBox(height: 8),
            Text(
              '請先選好時間與上車點。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  void _submit() {
    Navigator.of(context).pop(
      _ScheduleDraft(
        at: _at!,
        pickupAddress: _pickupAddress!,
        pickupLat: _pickupLat!,
        pickupLng: _pickupLng!,
        dropoffAddress: _dropoffAddress,
        dropoffLat: _dropoffLat,
        dropoffLng: _dropoffLng,
        note: _note.text.trim(),
      ),
    );
  }

  Future<void> _pickDateTime() async {
    // 門檻來自後端（見 CustomerController.scheduleMinLeadMinutes）——
    // 在 App 端也擋一次，是為了讓乘客**在按下送出之前**就知道時間太近，
    // 而不是填完整張表才收到 400。後端那道仍然是權威。
    final minLead = context.read<CustomerController>().scheduleMinLeadMinutes;
    final now = DateTime.now();
    final earliest = now.add(Duration(minutes: minLead));
    final messenger = ScaffoldMessenger.of(context);
    final date = await showDatePicker(
      context: context,
      initialDate: earliest,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(earliest),
    );
    if (time == null || !mounted) return;
    final at =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (at.isBefore(earliest)) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '預約時間至少要在 $minLead 分鐘後。想馬上用車請直接叫車。',
          ),
        ),
      );
      return;
    }
    setState(() => _at = at);
  }

  Future<void> _pickPoint({required bool isPickup}) async {
    final ctrl = context.read<CustomerController>();
    final pos = ctrl.lastPosition;
    final current = isPickup
        ? (_pickupLat != null ? LatLng(_pickupLat!, _pickupLng!) : null)
        : (_dropoffLat != null ? LatLng(_dropoffLat!, _dropoffLng!) : null);
    final picked = await Navigator.of(context).push<MapPickResult>(
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(
          initial: current ??
              (pos != null ? LatLng(pos.latitude, pos.longitude) : null),
        ),
      ),
    );
    if (picked == null || picked.address.isEmpty) return;
    setState(() {
      if (isPickup) {
        _pickupAddress = picked.address;
        _pickupLat = picked.lat;
        _pickupLng = picked.lng;
      } else {
        _dropoffAddress = picked.address;
        _dropoffLat = picked.lat;
        _dropoffLng = picked.lng;
      }
    });
  }
}

/// 預約時間的顯示格式（本地時間）。
///
/// 刻意帶星期：「8/3 09:00」看不出是星期幾，而預約多半是「下週一早上」這種想法。
String formatScheduleTime(DateTime at) {
  const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
  final w = weekdays[(at.weekday - 1).clamp(0, 6)];
  final mm = at.month.toString().padLeft(2, '0');
  final dd = at.day.toString().padLeft(2, '0');
  final hh = at.hour.toString().padLeft(2, '0');
  final min = at.minute.toString().padLeft(2, '0');
  return '$mm/$dd（$w）$hh:$min';
}
