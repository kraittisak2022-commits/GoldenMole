import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/utils/attendance_session_times.dart';

void main() {
  test('encode/parse closed and open sessions', () {
    const closed = AttendanceWorkSession(
      role: 'drum',
      empId: 'e1',
      startHHmm: '08:00',
      endHHmm: '12:00',
    );
    expect(closed.encode(), 'drum|e1|08:00|12:00');
    expect(closed.labelRange, '08:00–12:00');

    final parsed = AttendanceWorkSession.tryParse(closed.encode());
    expect(parsed?.role, 'drum');
    expect(parsed?.empId, 'e1');
    expect(parsed?.startHHmm, '08:00');
    expect(parsed?.endHHmm, '12:00');
    expect(parsed?.isOpen, isFalse);

    const open = AttendanceWorkSession(
      role: 'work',
      empId: 'e2',
      startHHmm: '09:15',
    );
    expect(open.encode(), 'work|e2|09:15|');
    expect(open.isOpen, isTrue);
    expect(open.labelRange, '09:15–');
  });

  test('openSession closes prior open roles for same emp', () {
    var sessions = <AttendanceWorkSession>[
      const AttendanceWorkSession(
        role: 'drum',
        empId: 'e1',
        startHHmm: '08:00',
      ),
    ];
    sessions = AttendanceSessionTimes.openSession(
      sessions: sessions,
      role: 'macro_driver',
      empId: 'e1',
      startHHmm: '12:00',
    );
    expect(sessions.length, 2);
    expect(sessions[0].role, 'drum');
    expect(sessions[0].endHHmm, '12:00');
    expect(sessions[1].role, 'macro_driver');
    expect(sessions[1].isOpen, isTrue);
  });
}
