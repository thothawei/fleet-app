// 金額顯示工具：後端一律以「分」儲存，且金額皆為整數元（分為 100 的倍數，台幣無小數）。
// 顯示一律取整數元、不帶小數點——避免出現 NT$XX.XX 這種不可支付的金額。

/// 分 → 「NT$ 1,234」整數元顯示字串（千分位、無小數）。
/// 後端金額皆為整數元；此處仍防禦性四捨五入到整數元，即使遇到殘留小數也收斂為整數元。
String formatCentsAsNtd(int cents) {
  final negative = cents < 0;
  final yuan = (cents.abs() + 50) ~/ 100; // 四捨五入到整數元
  final sign = negative ? '-' : '';
  return 'NT\$ $sign${_thousands(yuan)}';
}

String _thousands(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}
