import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/models/models.dart';
import '../../shared/widgets/rune_limit.dart';
import '../customer_controller.dart';
import '../widgets/saved_places_bar.dart' show savedPlaceIcon;
import 'map_picker_screen.dart';

/// 常用地點管理：設定住家／公司，以及自訂地點的新增、改名、刪除。
class SavedPlacesScreen extends StatefulWidget {
  const SavedPlacesScreen({super.key});

  @override
  State<SavedPlacesScreen> createState() => _SavedPlacesScreenState();
}

class _SavedPlacesScreenState extends State<SavedPlacesScreen> {
  @override
  void initState() {
    super.initState();
    // 進畫面才載入（不是 App 啟動就載）：這是輔助功能，不該在冷啟動時多打一支 API。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CustomerController>().loadSavedPlaces();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<CustomerController>();
    final custom = [
      for (final p in ctrl.savedPlaces)
        if (!p.isSlot) p,
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('常用地點')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, kind: SavedPlaceKind.custom),
        icon: const Icon(Icons.add_location_alt),
        label: const Text('新增地點'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ctrl.loadSavedPlaces(),
        child: ctrl.placesLoading && ctrl.savedPlaces.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  if (ctrl.placesError != null) ...[
                    _ErrorBanner(
                      message: ctrl.placesError!,
                      onRetry: () => ctrl.loadSavedPlaces(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    '設定好住家與公司，叫車和預約時就能一鍵帶入，不必每次重打地址。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  _SlotTile(
                    kind: SavedPlaceKind.home,
                    icon: Icons.home,
                    title: '住家',
                    place: ctrl.homePlace,
                    onEdit: () => _edit(
                      context,
                      kind: SavedPlaceKind.home,
                      existing: ctrl.homePlace,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _SlotTile(
                    kind: SavedPlaceKind.work,
                    icon: Icons.work,
                    title: '公司',
                    place: ctrl.workPlace,
                    onEdit: () => _edit(
                      context,
                      kind: SavedPlaceKind.work,
                      existing: ctrl.workPlace,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('其他地點', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (custom.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('還沒有其他常用地點。'),
                    )
                  else
                    for (final p in custom)
                      Card(
                        child: ListTile(
                          leading: Icon(savedPlaceIcon(p)),
                          title: Text(p.label),
                          subtitle: Text(p.address),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: '編輯',
                                icon: const Icon(Icons.edit),
                                onPressed: () =>
                                    _edit(context, kind: p.kind, existing: p),
                              ),
                              IconButton(
                                tooltip: '刪除',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _confirmDelete(context, p),
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              ),
      ),
    );
  }

  Future<void> _edit(
    BuildContext context, {
    required String kind,
    SavedPlace? existing,
  }) async {
    final ctrl = context.read<CustomerController>();
    final messenger = ScaffoldMessenger.of(context);
    final result = await showModalBottomSheet<_PlaceDraft>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PlaceEditorSheet(kind: kind, existing: existing),
    );
    if (result == null) return;

    final error = existing == null
        ? await ctrl.savePlace(
            kind: kind,
            label: result.label,
            address: result.address,
            lat: result.lat,
            lng: result.lng,
          )
        : await ctrl.updateSavedPlace(
            existing.id,
            label: result.label,
            address: result.address,
            lat: result.lat,
            lng: result.lng,
          );
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(error ?? '已儲存「${result.label}」')),
    );
  }

  Future<void> _confirmDelete(BuildContext context, SavedPlace place) async {
    final ctrl = context.read<CustomerController>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('刪除常用地點'),
        content: Text('要刪除「${place.label}」嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final error = await ctrl.deleteSavedPlace(place.id);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(error ?? '已刪除「${place.label}」')),
    );
  }
}

/// 住家／公司這種「每人一筆」的插槽列。
///
/// 沒設過時顯示「設定」而不是空白列——空白列看起來像壞掉，而這兩格是這個畫面的主角。
class _SlotTile extends StatelessWidget {
  const _SlotTile({
    required this.kind,
    required this.icon,
    required this.title,
    required this.place,
    required this.onEdit,
  });

  final String kind;
  final IconData icon;
  final String title;
  final SavedPlace? place;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final set = place != null;
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(set ? place!.address : '尚未設定'),
        trailing: TextButton(
          onPressed: onEdit,
          child: Text(set ? '變更' : '設定'),
        ),
        onTap: onEdit,
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

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
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('重試')),
        ],
      ),
    );
  }
}

/// 編輯表單的回傳值。
class _PlaceDraft {
  const _PlaceDraft({
    required this.label,
    required this.address,
    required this.lat,
    required this.lng,
  });

  final String label;
  final String address;
  final double lat;
  final double lng;
}

/// 地點編輯表單。
///
/// **座標一律來自地圖選點**，沒有讓使用者手打經緯度的欄位——手打的座標對不上地址時，
/// 司機會被導到另一個地方，而那是最難查的一種錯。
class _PlaceEditorSheet extends StatefulWidget {
  const _PlaceEditorSheet({required this.kind, this.existing});

  final String kind;
  final SavedPlace? existing;

  @override
  State<_PlaceEditorSheet> createState() => _PlaceEditorSheetState();
}

class _PlaceEditorSheetState extends State<_PlaceEditorSheet> {
  late final TextEditingController _label =
      TextEditingController(text: widget.existing?.label ?? _defaultLabel());
  late final TextEditingController _address =
      TextEditingController(text: widget.existing?.address ?? '');
  late double? _lat = widget.existing?.lat;
  late double? _lng = widget.existing?.lng;

  String _defaultLabel() {
    switch (widget.kind) {
      case SavedPlaceKind.home:
        return '住家';
      case SavedPlaceKind.work:
        return '公司';
      default:
        return '';
    }
  }

  @override
  void dispose() {
    _label.dispose();
    _address.dispose();
    super.dispose();
  }

  bool get _ready =>
      _label.text.trim().isNotEmpty &&
      _address.text.trim().isNotEmpty &&
      _lat != null &&
      _lng != null;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.existing == null ? '新增常用地點' : '編輯常用地點',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _label,
            onChanged: (_) => setState(() {}),
            // 先前**完全沒有上限**：後端 maxPlaceLabelRunes 是 40，超過會回
            // 「地點名稱過長」，但那句話沒說上限是多少，使用者只能亂猜著砍。
            inputFormatters: const [RuneLimitingTextInputFormatter(40)],
            maxLength: 40,
            maxLengthEnforcement: MaxLengthEnforcement.none,
            buildCounter: runeCounter(40, _label),
            decoration: const InputDecoration(
              labelText: '名稱',
              hintText: '例如：健身房、媽媽家',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _address,
            readOnly: true,
            onTap: _pickOnMap,
            decoration: InputDecoration(
              labelText: '地址',
              hintText: '點這裡在地圖上選位置',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.place),
              suffixIcon: IconButton(
                icon: const Icon(Icons.map),
                onPressed: _pickOnMap,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (_lat == null)
            Text(
              '請先在地圖上選一個位置——座標要跟地址對得上，司機才不會被導到別的地方。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _ready
                ? () => Navigator.of(context).pop(
                      _PlaceDraft(
                        label: _label.text.trim(),
                        address: _address.text.trim(),
                        lat: _lat!,
                        lng: _lng!,
                      ),
                    )
                : null,
            child: const Text('儲存'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickOnMap() async {
    final picked = await Navigator.of(context).push<MapPickResult>(
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(
          initial: _lat != null && _lng != null ? LatLng(_lat!, _lng!) : null,
        ),
      ),
    );
    if (picked == null || picked.address.isEmpty) return;
    setState(() {
      _address.text = picked.address;
      _lat = picked.lat;
      _lng = picked.lng;
    });
  }
}
