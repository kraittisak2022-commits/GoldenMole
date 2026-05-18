import '../models/employee.dart';

/// ตำแหน่งที่ไม่ให้เลือกในฟอร์มส่งคำขอเบิกเงิน (รวมชื่อเรียกที่ใช้ในระบบ)
const advanceExcludedPositionTitles = <String>{
  'คนขับรถ',
  'พนักงานขับรถ',
  'รับจ้างรายวัน',
  'รายจ้างรายวัน',
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

bool isExcludedPositionToken(String token) {
  final n = normalizePositionTitle(token);
  if (n.isEmpty) return false;
  return advanceExcludedPositionTitles.contains(n);
}

/// ซ่อนจากรายการเบิกเมื่อมีอย่างน้อย 1 ตำแหน่งที่อยู่ในรายการยกเว้น
bool isExcludedFromAdvanceEmployeePicker(Employee e) {
  final tokens = collectEmployeePositionTokens(e);
  if (tokens.isEmpty) return false;
  return tokens.any(isExcludedPositionToken);
}

bool employeeEligibleForAdvancePicker(Employee e) =>
    !e.inactive && !isExcludedFromAdvanceEmployeePicker(e);
