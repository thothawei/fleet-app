import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/models.dart';
import '../driver_controller.dart';

/// 車輛資訊設定頁（O2）。
///
/// 兩種進入情境：
/// - **強制**（`mandatory: true`）：司機未填車輛，由 `_DriverRoot` 直接導來。沒有返回鍵——
///   後端 O3 gate 會擋接單，回首頁也只是看著一個無法接單的畫面（拍板：不設寬限期）。
/// - **一般**：從首頁進來修改，可返回。
class DriverVehicleScreen extends StatefulWidget {
  const DriverVehicleScreen({this.mandatory = false, super.key});

  final bool mandatory;

  @override
  State<DriverVehicleScreen> createState() => _DriverVehicleScreenState();
}

class _DriverVehicleScreenState extends State<DriverVehicleScreen> {
  final _formKey = GlobalKey<FormState>();
  final _plateCtrl = TextEditingController();
  VehicleType? _type;
  bool _initialised = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialised) return;
    // 帶入既有值（修改情境）；未填時留空。
    final v = context.read<DriverController>().vehicle;
    if (v != null) {
      _type = v.type;
      _plateCtrl.text = v.plateNumber;
    }
    _initialised = true;
  }

  @override
  void dispose() {
    _plateCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_type == null) return;
    final ctrl = context.read<DriverController>();
    final ok = await ctrl.saveVehicle(
      vehicleType: _type!.code,
      plateNumber: _plateCtrl.text,
    );
    if (!mounted) return;
    if (ok) {
      // 強制情境：填完後 _DriverRoot 會自動換成首頁（hasVehicle 變 true），不必 pop。
      if (!widget.mandatory) Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('車輛資訊已儲存')),
      );
    }
    // 失敗時錯誤訊息由 ctrl.error 顯示（含車牌重複 409 的中文訊息）。
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DriverController>();
    return PopScope(
      // 強制情境不讓返回——沒填車輛回首頁也無法接單。
      canPop: !widget.mandatory,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('車輛資訊'),
          automaticallyImplyLeading: !widget.mandatory,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.mandatory) ...[
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text('請先填寫車種與車牌，填完才能開始接單。'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  DropdownButtonFormField<VehicleType>(
                    initialValue: _type,
                    decoration: const InputDecoration(
                      labelText: '車種',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final v in VehicleType.values)
                        DropdownMenuItem(value: v, child: Text(v.label)),
                    ],
                    onChanged: ctrl.vehicleSaving
                        ? null
                        : (v) => setState(() => _type = v),
                    validator: (v) => v == null ? '請選擇車種' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _plateCtrl,
                    enabled: !ctrl.vehicleSaving,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: '車牌',
                      hintText: '例如 ABC-1234',
                      border: OutlineInputBorder(),
                    ),
                    // 只擋明顯的空值——格式由後端寬鬆驗證（台灣車牌多代並存，
                    // App 端硬綁樣式會誤擋真車牌）。
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? '請輸入車牌' : null,
                  ),
                  if (_type == VehicleType.pet) ...[
                    const SizedBox(height: 12),
                    Text(
                      '寵物用車：乘客指定此車種時會加收清潔費，該費用全額歸司機。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (ctrl.error != null) ...[
                    const SizedBox(height: 16),
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(ctrl.error!),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: ctrl.vehicleSaving ? null : _save,
                    child: ctrl.vehicleSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('儲存'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
