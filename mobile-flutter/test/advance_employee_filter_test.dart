import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/models/employee.dart';
import 'package:mobile_flutter/utils/advance_employee_filter.dart';

Employee _emp({
  List<String> positions = const [],
  String? position,
}) =>
    Employee(
      id: '1',
      name: 'Test',
      nickname: 'T',
      type: 'Daily',
      positions: positions,
      position: position,
    );

void main() {
  test('excludes when any position in list is blocked', () {
    final e = _emp(positions: ['ร่อนทราย', 'คนขับรถ']);
    expect(isExcludedFromAdvanceEmployeePicker(e), isTrue);
    expect(employeeEligibleForAdvancePicker(e), isFalse);
  });

  test('excludes when legacy position field is blocked but list is not', () {
    final e = _emp(positions: ['ร่อนทราย'], position: 'รับจ้างรายวัน');
    expect(isExcludedFromAdvanceEmployeePicker(e), isTrue);
  });

  test('excludes when comma-separated in single field', () {
    final e = _emp(position: 'คนขับรถ, ร่อนทราย');
    expect(isExcludedFromAdvanceEmployeePicker(e), isTrue);
  });

  test('shows when no blocked position', () {
    final e = _emp(positions: ['ร่อนทราย', 'เฝ้ากลางคืน']);
    expect(isExcludedFromAdvanceEmployeePicker(e), isFalse);
    expect(employeeEligibleForAdvancePicker(e), isTrue);
  });

  test('collects from both positions and position without duplicates', () {
    final tokens = collectEmployeePositionTokens(
      _emp(positions: ['ร่อนทราย'], position: 'ร่อนทราย'),
    );
    expect(tokens, ['ร่อนทราย']);
  });
}
