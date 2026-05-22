import '../models/employee.dart';

/// ตำแหน่งที่ไม่ให้เลือกในฟอร์มส่งคำขอเบิกเงิน (รวมชื่อเรียกที่ใช้ในระบบ)
const advanceExcludedPositionTitles = <String>{
  'คนขับรถ',
  'พนักงานขับรถ',
  'รับจ้างรายวัน',
  'รายจ้างรายวัน',
};

/// ตำแหน่งที่ไม่ให้เลือกในฟอร์มบันทึกลางาน (เดียวกับเบิกเงิน)
const leaveExcludedPositionTitles = advanceExcludedPositionTitles;

/// ตำแหน่งที่ไม่ให้เลือกในฟอร์มบันทึก OT
const otExcludedPositionTitles = <String>{
  ...advanceExcludedPositionTitles,
  'เฝ้ากลางคืน',
};

final RegExp _positionPartSplit = RegExp(r'[,;/|、]');

String normalizePositionTitle(String raw) =>
    raw.trim().replaceAll(RegExp(r'\s+'), ' ');

/// รวมทุกตำแหน่งจาก `positions` และ `position` (รองรับหลายตำแหน่งในฟิลด์เดียว)
List<String> collectEmployeePositionTokens(Employee e) {
  final seen = <String>{};
  final out = <String>[];

  void addRaw(String? raw) {
    if (raw == null) return;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;
    final parts = trimmed.contains(',') ||
            trimmed.contains(';') ||
            trimmed.contains('/') ||
            trimmed.contains('|') ||
            trimmed.contains('、')
        ? trimmed.split(_positionPartSplit)
        : [trimmed];
    for (final part in parts) {
      final t = normalizePositionTitle(part);
      if (t.isNotEmpty && seen.add(t)) out.add(t);
    }
  }

  for (final p in e.positions) {
    addRaw(p);
  }
  addRaw(e.position);

  return out;
}

bool _isExcludedByPositionSet(String token, Set<String> excluded) {
  final n = normalizePositionTitle(token);
  if (n.isEmpty) return false;
  return excluded.contains(n);
}

bool isExcludedPositionToken(String token) =>
    _isExcludedByPositionSet(token, advanceExcludedPositionTitles);

/// ซ่อนเมื่อมีอย่างน้อย 1 ตำแหน่งที่อยู่ในรายการยกเว้น (เบิกเงิน / ลางาน)
bool _isExcludedFromPickerIfAnyPositionBlocked(
  Employee e,
  Set<String> excluded,
) {
  final tokens = collectEmployeePositionTokens(e);
  if (tokens.isEmpty) return false;
  return tokens.any((t) => _isExcludedByPositionSet(t, excluded));
}

/// ซ่อนเมื่อทุกตำแหน่งอยู่ในรายการยกเว้น (OT — หลายตำแหน่งยังแสดงถ้ามีตำแหน่งที่เลือกได้)
bool _isExcludedFromPickerIfAllPositionsBlocked(
  Employee e,
  Set<String> excluded,
) {
  final tokens = collectEmployeePositionTokens(e);
  if (tokens.isEmpty) return false;
  return tokens.every((t) => _isExcludedByPositionSet(t, excluded));
}

/// ซ่อนจากรายการเบิกเมื่อทุกตำแหน่งอยู่ในรายการยกเว้น (หลายตำแหน่งยังแสดงถ้ามีตำแหน่งที่เลือกได้)
bool isExcludedFromAdvanceEmployeePicker(Employee e) =>
    _isExcludedFromPickerIfAllPositionsBlocked(
      e,
      advanceExcludedPositionTitles,
    );

bool employeeEligibleForAdvancePicker(Employee e) =>
    !e.inactive && !isExcludedFromAdvanceEmployeePicker(e);

/// ซ่อนจากรายการลางานเมื่อมีอย่างน้อย 1 ตำแหน่งที่อยู่ในรายการยกเว้น
bool isExcludedFromLeaveEmployeePicker(Employee e) =>
    _isExcludedFromPickerIfAnyPositionBlocked(
      e,
      leaveExcludedPositionTitles,
    );

bool employeeEligibleForLeavePicker(Employee e) =>
    !e.inactive && !isExcludedFromLeaveEmployeePicker(e);

/// ซ่อนจากรายการ OT เมื่อทุกตำแหน่งอยู่ในรายการยกเว้น
bool isExcludedFromOtEmployeePicker(Employee e) =>
    _isExcludedFromPickerIfAllPositionsBlocked(e, otExcludedPositionTitles);

bool employeeEligibleForOtPicker(Employee e) =>
    !e.inactive && !isExcludedFromOtEmployeePicker(e);
