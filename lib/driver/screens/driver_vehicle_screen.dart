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
  final _phoneFormKey = GlobalKey<FormState>();
  final _plateCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  VehicleType? _type;
  bool _initialised = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialised) return;
    // 帶入既有值（修改情境）；未填時留空。
    final ctrl = context.read<DriverController>();
    final v = ctrl.vehicle;
    if (v != null) {
      _type = v.type;
      _plateCtrl.text = v.plateNumber;
    }
    _phoneCtrl.text = ctrl.phone;
    _initialised = true;
  }

  @override
  void dispose() {
    _plateCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _savePhone() async {
    if (!(_phoneFormKey.currentState?.validate() ?? false)) return;
    final ctrl = context.read<DriverController>();
    final ok = await ctrl.savePhone(_phoneCtrl.text);
    if (!mounted) return;
    if (ok) {
      // 以後端正規化後的號碼回填，讓司機看到真正存進去的內容。
      _phoneCtrl.text = ctrl.phone;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ctrl.hasPhone ? '聯絡電話已儲存' : '已清除聯絡電話')),
      );
    }
    // 失敗時錯誤訊息由 ctrl.error 顯示。
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('車輛資訊已儲存')));
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Form(
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
                                Expanded(child: Text('請先填寫車種與車牌，填完才能開始接單。')),
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
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: ctrl.vehicleSaving ? null : _save,
                        child: ctrl.vehicleSaving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('儲存車輛資訊'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),
                // 電話**獨立一區、獨立送出**：改車輛會讓審核回到待審核（O5），
                // 而改電話不該讓司機被鎖出接單，兩者因此走不同的後端端點。
                Form(
                  key: _phoneFormKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '聯絡電話',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '乘客在您前往上車點時可直接撥打。留空則乘客端不顯示撥號按鈕。'
                        '修改電話不會影響車輛審核狀態。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phoneCtrl,
                        enabled: !ctrl.phoneSaving,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: '電話（選填）',
                          hintText: '例如 0912345678',
                          border: OutlineInputBorder(),
                        ),
                        // 留空是合法的（＝清除號碼）；只在有填時做最低限度的長度檢查，
                        // 格式仍以後端為準——市話、國際碼樣式太多，App 端硬綁會誤擋。
                        validator: (v) {
                          final s = (v ?? '').trim();
                          if (s.isEmpty) return null;
                          final digits = s.replaceAll(RegExp(r'[\s\-()]'), '');
                          return digits.length < 8 ? '電話長度不足' : null;
                        },
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: ctrl.phoneSaving ? null : _savePhone,
                        child: ctrl.phoneSaving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('儲存聯絡電話'),
                      ),
                    ],
                  ),
                ),
                // 共用一個錯誤區（controller 只有一個 error）；訊息本身會說明是車牌
                // 重複還是電話格式，放在最下方兩區都看得到。
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
