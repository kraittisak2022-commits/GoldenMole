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
  test('advance shows when any position is not blocked', () {
    final e = _emp(positions: ['ร่อนทราย', 'คนขับรถ']);
    expect(isExcludedFromAdvanceEmployeePicker(e), isFalse);
    expect(employeeEligibleForAdvancePicker(e), isTrue);
  });

  test('advance shows when legacy position is blocked but list is not', () {
    final e = _emp(positions: ['ร่อนทราย'], position: 'รับจ้างรายวัน');
    expect(isExcludedFromAdvanceEmployeePicker(e), isFalse);
    expect(employeeEligibleForAdvancePicker(e), isTrue);
  });

  test('advance shows when comma-separated mix has eligible title', () {
    final e = _emp(position: 'คนขับรถ, ร่อนทราย');
    expect(isExcludedFromAdvanceEmployeePicker(e), isFalse);
    expect(employeeEligibleForAdvancePicker(e), isTrue);
  });

  test('advance hides only when every position is blocked', () {
    final e = _emp(positions: ['คนขับรถ', 'รับจ้างรายวัน']);
    expect(isExcludedFromAdvanceEmployeePicker(e), isTrue);
    expect(employeeEligibleForAdvancePicker(e), isFalse);
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

  test('OT excludes driver night watch and daily hire', () {
    expect(isExcludedFromOtEmployeePicker(_emp(positions: ['คนขับรถ'])), isTrue);
    expect(
      isExcludedFromOtEmployeePicker(_emp(positions: ['เฝ้ากลางคืน'])),
      isTrue,
    );
    expect(
      isExcludedFromOtEmployeePicker(_emp(position: 'รับจ้างรายวัน')),
      isTrue,
    );
    expect(
      employeeEligibleForOtPicker(_emp(positions: ['ร่อนทราย'])),
      isTrue,
    );
  });

  test('advance and OT show employee when any position is not blocked', () {
    final e = _emp(positions: ['ร่อนทราย', 'เฝ้ากลางคืน']);
    expect(isExcludedFromAdvanceEmployeePicker(e), isFalse);
    expect(isExcludedFromOtEmployeePicker(e), isFalse);
    expect(employeeEligibleForAdvancePicker(e), isTrue);
    expect(employeeEligibleForOtPicker(e), isTrue);
  });

  test('advance shows driver when also has eligible position', () {
    final e = _emp(positions: ['คนขับรถ', 'ร่อนทราย']);
    expect(isExcludedFromAdvanceEmployeePicker(e), isFalse);
    expect(employeeEligibleForAdvancePicker(e), isTrue);
  });

  test('OT shows driver when also has eligible position', () {
    final e = _emp(positions: ['คนขับรถ', 'ร่อนทราย']);
    expect(isExcludedFromOtEmployeePicker(e), isFalse);
    expect(employeeEligibleForOtPicker(e), isTrue);
  });

  test('OT hides only when every position is blocked', () {
    final e = _emp(positions: ['คนขับรถ', 'รับจ้างรายวัน']);
    expect(isExcludedFromOtEmployeePicker(e), isTrue);
    expect(employeeEligibleForOtPicker(e), isFalse);
  });

  test('leave excludes driver and daily hire like advance', () {
    expect(
      isExcludedFromLeaveEmployeePicker(_emp(positions: ['คนขับรถ'])),
      isTrue,
    );
    expect(
      employeeEligibleForLeavePicker(_emp(positions: ['เฝ้ากลางคืน'])),
      isTrue,
    );
    expect(
      isExcludedFromLeaveEmployeePicker(_emp(position: 'รับจ้างรายวัน')),
      isTrue,
    );
  });
}
