import '../models/employee.dart';

/// ตำแหน่งที่ไม่ให้เลือก — ปัจจุบันใช้เป็นฐานของรายการยกเว้นฝั่ง OT เท่านั้น
/// (ฟอร์มเบิกเงิน/ลางานเปลี่ยนไปใช้บัญชีขาว [advanceAllowedPositionTitles] แล้ว)
const advanceExcludedPositionTitles = <String>{
  'คนขับรถ',
  'พนักงานขับรถ',
  'รับจ้างรายวัน',
  'รายจ้างรายวัน',
};

/// ตำแหน่งที่เลือกได้ในฟอร์มส่งคำขอเบิกเงิน / บันทึกลางาน
/// เก็บแบบตัดช่องว่างแล้ว เพื่อรองรับการสะกดหลายแบบ
const advanceAllowedPositionTitles = <String>{
  'พนักงานท่าทราย',
  'พนักงานทำทราย',
  'ท่าทราย',
  'คนขับรถแม็คโคร',
  'คนขับรถแมคโคร',
};

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

/// ซ่อนเมื่อทุกตำแหน่งอยู่ในรายการยกเว้น (OT — หลายตำแหน่งยังแสดงถ้ามีตำแหน่งที่เลือกได้)
bool _isExcludedFromPickerIfAllPositionsBlocked(
  Employee e,
  Set<String> excluded,
) {
  final tokens = collectEmployeePositionTokens(e);
  if (tokens.isEmpty) return false;
  return tokens.every((t) => _isExcludedByPositionSet(t, excluded));
}

/// เทียบตำแหน่งกับบัญชีขาวโดยไม่สนใจช่องว่าง (เช่น «พนักงาน ท่าทราย»)
bool isSandYardOrMacroDriverPositionToken(String token) {
  final compact = normalizePositionTitle(token).replaceAll(' ', '');
  if (compact.isEmpty) return false;
  return advanceAllowedPositionTitles.contains(compact);
}

/// พนักงานท่าทราย หรือ คนขับรถแม็คโคร — กลุ่มเดียวที่เลือกได้ในเบิกเงิน/ลางาน
bool isSandYardOrMacroDriverEmployee(Employee e) =>
    collectEmployeePositionTokens(
      e,
    ).any(isSandYardOrMacroDriverPositionToken);

/// ซ่อนจากรายการเบิกเมื่อไม่ใช่พนักงานท่าทราย/คนขับรถแม็คโคร
bool isExcludedFromAdvanceEmployeePicker(Employee e) =>
    !isSandYardOrMacroDriverEmployee(e);

bool employeeEligibleForAdvancePicker(Employee e) =>
    !e.inactive && !isExcludedFromAdvanceEmployeePicker(e);

/// ซ่อนจากรายการลางานด้วยเกณฑ์เดียวกับเบิกเงิน
bool isExcludedFromLeaveEmployeePicker(Employee e) =>
    !isSandYardOrMacroDriverEmployee(e);

bool employeeEligibleForLeavePicker(Employee e) =>
    !e.inactive && !isExcludedFromLeaveEmployeePicker(e);

/// ซ่อนจากรายการ OT เมื่อทุกตำแหน่งอยู่ในรายการยกเว้น
bool isExcludedFromOtEmployeePicker(Employee e) =>
    _isExcludedFromPickerIfAllPositionsBlocked(e, otExcludedPositionTitles);

bool employeeEligibleForOtPicker(Employee e) =>
    !e.inactive && !isExcludedFromOtEmployeePicker(e);
