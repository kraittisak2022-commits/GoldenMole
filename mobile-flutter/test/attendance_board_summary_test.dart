import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/models/employee.dart';
import 'package:mobile_flutter/utils/attendance_board_summary.dart';

Employee _emp(String id, String name, {String nickname = ''}) => Employee(
  id: id,
  name: name,
  nickname: nickname,
  type: 'Daily',
  position: 'พนักงานท่าทราย',
  baseWage: 400,
);

void main() {
  group('AttendanceGroupProgress', () {
    test('computes ratio, remaining, and completion accurately', () {
      const partial = AttendanceGroupProgress(checkedCount: 6, totalCount: 8);
      expect(partial.remainingCount, 2);
      expect(partial.ratio, closeTo(0.75, 1e-6));
      expect(partial.isComplete, isFalse);
      expect(partial.hasAny, isTrue);

      const full = AttendanceGroupProgress(checkedCount: 8, totalCount: 8);
      expect(full.remainingCount, 0);
      expect(full.ratio, 1.0);
      expect(full.isComplete, isTrue);

      const empty = AttendanceGroupProgress(checkedCount: 0, totalCount: 0);
      expect(empty.remainingCount, 0);
      expect(empty.ratio, 0.0);
      expect(empty.isComplete, isFalse);
      expect(empty.hasAny, isFalse);
    });

    test('clamps overflow counts cleanly', () {
      const over = AttendanceGroupProgress(checkedCount: 10, totalCount: 8);
      expect(over.remainingCount, 0);
      expect(over.ratio, 1.0);
      expect(over.isComplete, isTrue);
    });
  });

  group('attendanceInitialsOf', () {
    test('skips Thai leading vowels and combining marks cleanly', () {
      expect(attendanceInitialsOf('สมชาย'), 'ส');
      expect(attendanceInitialsOf('เก่ง'), 'ก');
      expect(attendanceInitialsOf('แดง'), 'ด');
      expect(attendanceInitialsOf('โอม'), 'อ');
      expect(attendanceInitialsOf('พี่บอย'), 'พ');
    });

    test('extracts uppercase Latin initials and handles blanks', () {
      expect(attendanceInitialsOf('John Doe'), 'JD');
      expect(attendanceInitialsOf('aek'), 'A');
      expect(attendanceInitialsOf('   '), '?');
    });
  });

  group('filterAttendancePoolEmployees', () {
    final people = [
      _emp('1', 'สมชาย ใจดี', nickname: 'ชาย'),
      _emp('2', 'วิชัย มั่นคง', nickname: 'เก่ง'),
      _emp('3', 'ประเสริฐ สุขใจ', nickname: 'บอย'),
    ];

    test('returns full list when query is blank', () {
      final res = filterAttendancePoolEmployees(
        people,
        '   ',
        (e) => e.nickname.isNotEmpty ? e.nickname : e.name,
      );
      expect(res.map((e) => e.id).toList(), ['1', '2', '3']);
    });

    test('matches by nickname or full name case-insensitively', () {
      final byNick = filterAttendancePoolEmployees(
        people,
        'เก่ง',
        (e) => e.nickname.isNotEmpty ? e.nickname : e.name,
      );
      expect(byNick.map((e) => e.id).toList(), ['2']);

      final byFull = filterAttendancePoolEmployees(
        people,
        'สมชาย',
        (e) => e.nickname.isNotEmpty ? e.nickname : e.name,
      );
      expect(byFull.map((e) => e.id).toList(), ['1']);
    });
  });

  group('buildAttendanceStatBadges', () {
    test('filters out zero-count items when any count is positive', () {
      final badges = buildAttendanceSandYardStats(
        work: 5,
        leaveFull: 1,
        leaveMorning: 0,
        leaveAfternoon: 0,
      );
      expect(badges.map((b) => '${b.label}:${b.count}').toList(), [
        'ทำงาน:5',
        'ลาเต็มวัน:1',
      ]);
    });

    test('returns empty list when all counts are zero', () {
      expect(
        buildAttendanceSandYardStats(
          work: 0,
          leaveFull: 0,
          leaveMorning: 0,
          leaveAfternoon: 0,
        ),
        isEmpty,
      );
      expect(
        buildAttendanceDriverStats(
          macro: 0,
          drum: 0,
          leaveFull: 0,
          leaveMorning: 0,
          leaveAfternoon: 0,
        ),
        isEmpty,
      );
    });

    test('builds driver stat badges for active roles and leaves', () {
      final badges = buildAttendanceDriverStats(
        macro: 3,
        drum: 2,
        leaveFull: 0,
        leaveMorning: 1,
        leaveAfternoon: 0,
      );
      expect(badges.map((b) => '${b.label}:${b.count}').toList(), [
        'แม็คโคร:3',
        'ดรัม:2',
        'ลาเช้า:1',
      ]);
    });
  });
}
