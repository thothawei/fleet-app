import 'package:flutter_test/flutter_test.dart';
import 'package:line_fleet_app/core/util/money.dart';

void main() {
  group('formatCentsAsNtd', () {
    test('基本換算與 2 位小數', () {
      expect(formatCentsAsNtd(27000), 'NT\$ 270.00');
      expect(formatCentsAsNtd(4050), 'NT\$ 40.50');
      expect(formatCentsAsNtd(0), 'NT\$ 0.00');
    });

    test('千分位', () {
      expect(formatCentsAsNtd(300000), 'NT\$ 3,000.00');
      expect(formatCentsAsNtd(304050), 'NT\$ 3,040.50');
      expect(formatCentsAsNtd(123456789), 'NT\$ 1,234,567.89');
    });

    test('負數', () {
      expect(formatCentsAsNtd(-4050), 'NT\$ -40.50');
    });
  });
}
