/// เซสชันเวลาในกระดานเช็คชื่อ — เก็บใน workAssignments['sessionTimes']
/// รูปแบบ: `role|empId|HH:mm|HH:mm` (ปิดแล้ว) หรือ `role|empId|HH:mm|` (ยังเปิด)
class AttendanceWorkSession {
  const AttendanceWorkSession({
    required this.role,
    required this.empId,
    required this.startHHmm,
    this.endHHmm,
  });

  final String role;
  final String empId;
  final String startHHmm;
  final String? endHHmm;

  bool get isOpen => endHHmm == null || endHHmm!.trim().isEmpty;

  String get labelRange {
    final end = endHHmm?.trim();
    if (end == null || end.isEmpty) return '$startHHmm–';
    return '$startHHmm–$end';
  }

  AttendanceWorkSession copyWith({
    String? role,
    String? empId,
    String? startHHmm,
    String? endHHmm,
    bool clearEnd = false,
  }) {
    return AttendanceWorkSession(
      role: role ?? this.role,
      empId: empId ?? this.empId,
      startHHmm: startHHmm ?? this.startHHmm,
      endHHmm: clearEnd ? null : (endHHmm ?? this.endHHmm),
    );
  }

  String encode() =>
      '$role|$empId|$startHHmm|${isOpen ? '' : endHHmm!.trim()}';

  static AttendanceWorkSession? tryParse(String raw) {
    final parts = raw.split('|');
    if (parts.length < 3) return null;
    final role = parts[0].trim();
    final empId = parts[1].trim();
    final start = parts[2].trim();
    if (role.isEmpty || empId.isEmpty || start.isEmpty) return null;
    final end = parts.length >= 4 ? parts[3].trim() : '';
    return AttendanceWorkSession(
      role: role,
      empId: empId,
      startHHmm: start,
      endHHmm: end.isEmpty ? null : end,
    );
  }
}

abstract final class AttendanceSessionTimes {
  static const key = 'sessionTimes';

  static const roleWork = 'work';
  static const roleMacro = 'macro_driver';
  static const roleDrum = 'drum';

  static const Set<String> timedRoles = {roleWork, roleMacro, roleDrum};

  /// bucket UI → role ที่เก็บใน sessionTimes
  static String? roleForBucket(String bucketId) {
    return switch (bucketId) {
      'att_work' => roleWork,
      'att_drv_macro' => roleMacro,
      'att_drv_drum' => roleDrum,
      _ => null,
    };
  }

  static String? bucketForRole(String role) {
    return switch (role) {
      roleWork => 'att_work',
      roleMacro => 'att_drv_macro',
      roleDrum => 'att_drv_drum',
      _ => null,
    };
  }

  static String formatHHmm(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  static List<AttendanceWorkSession> parseList(Iterable<String>? raw) {
    if (raw == null) return const [];
    final out = <AttendanceWorkSession>[];
    for (final line in raw) {
      final s = tryParseLine(line);
      if (s != null) out.add(s);
    }
    return out;
  }

  static AttendanceWorkSession? tryParseLine(String line) =>
      AttendanceWorkSession.tryParse(line);

  static List<String> encodeList(Iterable<AttendanceWorkSession> sessions) =>
      sessions.map((s) => s.encode()).toList();

  static List<AttendanceWorkSession> forRoles(
    Iterable<AttendanceWorkSession> sessions,
    Set<String> roles,
  ) {
    return sessions.where((s) => roles.contains(s.role)).toList();
  }

  /// ปิดเซสชันเปิดของ emp ใน roles ที่กำหนด
  static List<AttendanceWorkSession> closeOpenForEmp({
    required List<AttendanceWorkSession> sessions,
    required String empId,
    required Set<String> roles,
    required String endHHmm,
  }) {
    return [
      for (final s in sessions)
        if (s.empId == empId && s.isOpen && roles.contains(s.role))
          s.copyWith(endHHmm: endHHmm)
        else
          s,
    ];
  }

  /// เปิดเซสชันใหม่ (ไม่แตะเซสชันที่ปิดแล้ว)
  static List<AttendanceWorkSession> openSession({
    required List<AttendanceWorkSession> sessions,
    required String role,
    required String empId,
    required String startHHmm,
  }) {
    final closedOthers = closeOpenForEmp(
      sessions: sessions,
      empId: empId,
      roles: timedRoles,
      endHHmm: startHHmm,
    );
    return [
      ...closedOthers,
      AttendanceWorkSession(
        role: role,
        empId: empId,
        startHHmm: startHHmm,
      ),
    ];
  }

  static List<AttendanceWorkSession> removeSessionAt({
    required List<AttendanceWorkSession> sessions,
    required int index,
  }) {
    if (index < 0 || index >= sessions.length) return sessions;
    final next = List<AttendanceWorkSession>.from(sessions);
    next.removeAt(index);
    return next;
  }
}
