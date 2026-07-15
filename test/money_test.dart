import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/util/money.dart';

void main() {
  group('formatCentsAsNtd', () {
    test('整數元顯示（台幣無小數）', () {
      expect(formatCentsAsNtd(27000), 'NT\$ 270');
      expect(formatCentsAsNtd(4000), 'NT\$ 40');
      expect(formatCentsAsNtd(0), 'NT\$ 0');
    });

    test('千分位', () {
      expect(formatCentsAsNtd(300000), 'NT\$ 3,000');
      expect(formatCentsAsNtd(304000), 'NT\$ 3,040');
      expect(formatCentsAsNtd(123456700), 'NT\$ 1,234,567');
    });

    test('負數', () {
      expect(formatCentsAsNtd(-4000), 'NT\$ -40');
    });

    test('殘留小數防禦性四捨五入到整數元', () {
      expect(formatCentsAsNtd(4050), 'NT\$ 41'); // NT$40.50 → 41
      expect(formatCentsAsNtd(4049), 'NT\$ 40'); // NT$40.49 → 40
    });
  });
}
