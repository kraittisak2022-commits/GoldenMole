import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/models/employee.dart';
import 'package:mobile_flutter/utils/advance_employee_filter.dart';

Employee _emp({
  List<String> positions = const [],
  String? position,
  bool inactive = false,
}) =>
    Employee(
      id: '1',
      name: 'Test',
      nickname: 'T',
      type: 'Daily',
      positions: positions,
      position: position,
      inactive: inactive,
    );

void main() {
  test('advance shows sand yard staff and macro drivers', () {
    for (final title in ['พนักงานท่าทราย', 'คนขับรถแม็คโคร']) {
      final e = _emp(positions: [title]);
      expect(isExcludedFromAdvanceEmployeePicker(e), isFalse, reason: title);
      expect(employeeEligibleForAdvancePicker(e), isTrue, reason: title);
      expect(employeeEligibleForLeavePicker(e), isTrue, reason: title);
    }
  });

  test('advance accepts alternate spellings', () {
    for (final title in ['พนักงานทำทราย', 'คนขับรถแมคโคร', 'ท่าทราย']) {
      expect(
        employeeEligibleForAdvancePicker(_emp(positions: [title])),
        isTrue,
        reason: title,
      );
    }
  });

  test('advance hides every other position', () {
    for (final title in ['ร่อนทราย', 'เฝ้ากลางคืน', 'คนขับรถ', 'รับจ้างรายวัน']) {
      final e = _emp(positions: [title]);
      expect(isExcludedFromAdvanceEmployeePicker(e), isTrue, reason: title);
      expect(employeeEligibleForAdvancePicker(e), isFalse, reason: title);
      expect(employeeEligibleForLeavePicker(e), isFalse, reason: title);
    }
  });

  test('advance hides employees without any position', () {
    final e = _emp();
    expect(employeeEligibleForAdvancePicker(e), isFalse);
    expect(employeeEligibleForLeavePicker(e), isFalse);
  });

  test('advance shows when one of many positions is allowed', () {
    final e = _emp(positions: ['คนขับรถ', 'พนักงานท่าทราย']);
    expect(employeeEligibleForAdvancePicker(e), isTrue);
    expect(employeeEligibleForLeavePicker(e), isTrue);
  });

  test('advance reads comma-separated legacy position field', () {
    final e = _emp(position: 'คนขับรถ, คนขับรถแม็คโคร');
    expect(employeeEligibleForAdvancePicker(e), isTrue);
  });

  test('inactive employees never show', () {
    final e = _emp(positions: ['พนักงานท่าทราย'], inactive: true);
    expect(employeeEligibleForAdvancePicker(e), isFalse);
    expect(employeeEligibleForLeavePicker(e), isFalse);
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

  test('OT still shows employee when any position is not blocked', () {
    final e = _emp(positions: ['ร่อนทราย', 'เฝ้ากลางคืน']);
    expect(isExcludedFromOtEmployeePicker(e), isFalse);
    expect(employeeEligibleForOtPicker(e), isTrue);
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

  test('leave uses the same allowlist as advance', () {
    expect(
      isExcludedFromLeaveEmployeePicker(_emp(positions: ['คนขับรถ'])),
      isTrue,
    );
    expect(
      employeeEligibleForLeavePicker(_emp(positions: ['เฝ้ากลางคืน'])),
      isFalse,
    );
    expect(
      isExcludedFromLeaveEmployeePicker(_emp(positions: ['พนักงานท่าทราย'])),
      isFalse,
    );
  });
}
