// 金額顯示工具：後端一律以「分」儲存，顯示時除 100。

/// 分 → 「NT$ 1,234.50」顯示字串（千分位、2 位小數）。
String formatCentsAsNtd(int cents) {
  final negative = cents < 0;
  final abs = cents.abs();
  final yuan = abs ~/ 100;
  final frac = abs % 100;
  final sign = negative ? '-' : '';
  return 'NT\$ $sign${_thousands(yuan)}.${frac.toString().padLeft(2, '0')}';
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
