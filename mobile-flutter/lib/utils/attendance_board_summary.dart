import 'package:flutter/material.dart';

import '../models/employee.dart';

/// ความคืบหน้าการเช็คชื่อของ 1 กลุ่ม (พนักงานท่าทราย หรือ คนขับรถ)
class AttendanceGroupProgress {
  const AttendanceGroupProgress({
    this.checkedCount = 0,
    this.totalCount = 0,
  });

  final int checkedCount;
  final int totalCount;

  int get remainingCount =>
      totalCount <= 0 ? 0 : (totalCount - checkedCount).clamp(0, totalCount);

  double get ratio =>
      totalCount <= 0 ? 0.0 : (checkedCount / totalCount).clamp(0.0, 1.0);

  bool get hasAny => checkedCount > 0;

  bool get isComplete => totalCount > 0 && checkedCount >= totalCount;
}

/// ป้ายสถิติย่อยในหน้าเลือกกลุ่มและแถบสรุปด้านล่างกระดาน
class AttendanceStatBadgeData {
  const AttendanceStatBadgeData({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;
}

const Color kAttendanceWorkColor = Color(0xFF0D9488);
const Color kAttendanceMacroColor = Color(0xFFD97706);
const Color kAttendanceDrumColor = Color(0xFF4F46E5);
const Color kAttendanceLeaveColor = Color(0xFFE11D48);

/// สรุปป้ายสถิติของกลุ่มพนักงานท่าทราย (ซ่อนรายการที่เป็น 0 เพื่อลดความรก)
List<AttendanceStatBadgeData> buildAttendanceSandYardStats({
  required int work,
  required int leaveFull,
  required int leaveMorning,
  required int leaveAfternoon,
}) {
  return [
    if (work > 0)
      AttendanceStatBadgeData(
        label: 'ทำงาน',
        count: work,
        color: kAttendanceWorkColor,
      ),
    if (leaveFull > 0)
      AttendanceStatBadgeData(
        label: 'ลาเต็มวัน',
        count: leaveFull,
        color: kAttendanceLeaveColor,
      ),
    if (leaveMorning > 0)
      AttendanceStatBadgeData(
        label: 'ลาเช้า',
        count: leaveMorning,
        color: kAttendanceLeaveColor,
      ),
    if (leaveAfternoon > 0)
      AttendanceStatBadgeData(
        label: 'ลาบ่าย',
        count: leaveAfternoon,
        color: kAttendanceLeaveColor,
      ),
  ];
}

/// สรุปป้ายสถิติของกลุ่มคนขับรถ (ซ่อนรายการที่เป็น 0 เพื่อลดความรก)
List<AttendanceStatBadgeData> buildAttendanceDriverStats({
  required int macro,
  required int drum,
  required int leaveFull,
  required int leaveMorning,
  required int leaveAfternoon,
}) {
  return [
    if (macro > 0)
      AttendanceStatBadgeData(
        label: 'แม็คโคร',
        count: macro,
        color: kAttendanceMacroColor,
      ),
    if (drum > 0)
      AttendanceStatBadgeData(
        label: 'ดรัม',
        count: drum,
        color: kAttendanceDrumColor,
      ),
    if (leaveFull > 0)
      AttendanceStatBadgeData(
        label: 'ลาเต็มวัน',
        count: leaveFull,
        color: kAttendanceLeaveColor,
      ),
    if (leaveMorning > 0)
      AttendanceStatBadgeData(
        label: 'ลาเช้า',
        count: leaveMorning,
        color: kAttendanceLeaveColor,
      ),
    if (leaveAfternoon > 0)
      AttendanceStatBadgeData(
        label: 'ลาบ่าย',
        count: leaveAfternoon,
        color: kAttendanceLeaveColor,
      ),
  ];
}

bool _isThaiLeadingVowelOrMark(int unit) {
  // สระหน้า เ แ โ ใ ไ (0x0E40–0x0E44) และวรรณยุกต์/สระบนล่าง
  if (unit >= 0x0E40 && unit <= 0x0E44) return true;
  if (unit == 0x0E31 || (unit >= 0x0E34 && unit <= 0x0E3A)) return true;
  if (unit >= 0x0E47 && unit <= 0x0E4E) return true;
  return false;
}

bool _isThaiConsonant(int unit) => unit >= 0x0E01 && unit <= 0x0E2E;

/// ตัวอักษรย่อสำหรับอวาตาร์บนชิปรายชื่อ (ข้ามสระหน้าภาษาไทย เช่น เก่ง → ก)
String attendanceInitialsOf(String rawName) {
  final trimmed = rawName.trim();
  if (trimmed.isEmpty) return '?';

  final runes = trimmed.runes.toList();
  // ชื่อภาษาไทย: ใช้พยัญชนะตัวแรกที่พบ (ข้ามสระหน้า เ/แ/โ/ใ/ไ)
  for (final r in runes) {
    if (_isThaiConsonant(r)) return String.fromCharCode(r);
  }

  // ชื่ออังกฤษ / ตัวอักษรละติน: ใช้ตัวแรกของคำ (สูงสุด 2 ตัว)
  final words = trimmed
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.length >= 2) {
    final a = words[0].runes.first;
    final b = words[1].runes.first;
    return (String.fromCharCode(a) + String.fromCharCode(b)).toUpperCase();
  }
  for (final r in runes) {
    if (!_isThaiLeadingVowelOrMark(r) && !RegExp(r'\s').hasMatch(String.fromCharCode(r))) {
      return String.fromCharCode(r).toUpperCase();
    }
  }
  return String.fromCharCode(runes.first).toUpperCase();
}

/// กรองรายชื่อในพูลตามคำค้นหา (จับคู่ทั้งชื่อเล่น ชื่อจริง และชื่อที่แสดงบน UI)
List<Employee> filterAttendancePoolEmployees(
  List<Employee> people,
  String query,
  String Function(Employee) displayNameOf,
) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return people;
  return [
    for (final e in people)
      if (displayNameOf(e).toLowerCase().contains(needle) ||
          e.name.toLowerCase().contains(needle) ||
          e.nickname.toLowerCase().contains(needle))
        e,
  ];
}
