import 'package:flutter/material.dart';

import '../models/app_transaction.dart';

/// ข้อมูลเมตาดาต้าของประเภทเหตุการณ์แต่ละชนิด
class DailyEventTypeSpec {
  const DailyEventTypeSpec({
    required this.code,
    required this.label,
    required this.shortLabel,
    required this.icon,
    required this.accentLight,
    required this.accentDark,
  });

  final String code;
  final String label;
  final String shortLabel;
  final IconData icon;
  final Color accentLight;
  final Color accentDark;

  Color accent({required bool isDark}) => isDark ? accentDark : accentLight;
}

/// 6 ประเภทเหตุการณ์มาตรฐาน (ตรงกับ event_type บนเว็บและฐานข้อมูล)
const List<DailyEventTypeSpec> kDailyEventTypes = [
  DailyEventTypeSpec(
    code: 'info',
    label: 'ข้อมูลทั่วไป',
    shortLabel: 'ข้อมูล',
    icon: Icons.info_outline_rounded,
    accentLight: Color(0xFF1565C0),
    accentDark: Color(0xFF60A5FA),
  ),
  DailyEventTypeSpec(
    code: 'warning',
    label: 'แจ้งเตือน',
    shortLabel: 'เตือน',
    icon: Icons.warning_amber_rounded,
    accentLight: Color(0xFFEF6C00),
    accentDark: Color(0xFFFFB74D),
  ),
  DailyEventTypeSpec(
    code: 'problem',
    label: 'ปัญหาหน้างาน',
    shortLabel: 'ปัญหา',
    icon: Icons.error_outline_rounded,
    accentLight: Color(0xFFC62828),
    accentDark: Color(0xFFF87171),
  ),
  DailyEventTypeSpec(
    code: 'success',
    label: 'งานสำเร็จ',
    shortLabel: 'สำเร็จ',
    icon: Icons.check_circle_outline_rounded,
    accentLight: Color(0xFF2E7D32),
    accentDark: Color(0xFF4ADE80),
  ),
  DailyEventTypeSpec(
    code: 'complaint',
    label: 'ข้อร้องเรียน',
    shortLabel: 'ร้องเรียน',
    icon: Icons.campaign_outlined,
    accentLight: Color(0xFF7B1FA2),
    accentDark: Color(0xFFCE93D8),
  ),
  DailyEventTypeSpec(
    code: 'request',
    label: 'ความต้องการ',
    shortLabel: 'ต้องการ',
    icon: Icons.assignment_outlined,
    accentLight: Color(0xFF00838F),
    accentDark: Color(0xFF4DD0E1),
  ),
];

/// เทมเพลตด่วนสำหรับหน้างาน — แตะเมื่อช่องว่างจะช่วยตั้งประเภทและความสำคัญให้ด้วย
class DailyEventQuickTemplate {
  const DailyEventQuickTemplate({
    required this.text,
    required this.defaultType,
    this.defaultPriority = 'normal',
  });

  final String text;
  final String defaultType;
  final String defaultPriority;
}

const List<DailyEventQuickTemplate> kDailyEventQuickTemplates = [
  DailyEventQuickTemplate(
    text: 'ฝนตก หยุดงาน',
    defaultType: 'warning',
  ),
  DailyEventQuickTemplate(
    text: 'เครื่องจักรเสีย',
    defaultType: 'problem',
    defaultPriority: 'urgent',
  ),
  DailyEventQuickTemplate(
    text: 'ไฟฟ้าดับ',
    defaultType: 'problem',
    defaultPriority: 'urgent',
  ),
  DailyEventQuickTemplate(
    text: 'ทรายไม่ครบ',
    defaultType: 'warning',
  ),
  DailyEventQuickTemplate(
    text: 'คนงานมาสาย',
    defaultType: 'warning',
  ),
  DailyEventQuickTemplate(
    text: 'อุบัติเหตุเล็กน้อย',
    defaultType: 'problem',
    defaultPriority: 'urgent',
  ),
  DailyEventQuickTemplate(
    text: 'งานเสร็จตามแผน',
    defaultType: 'success',
  ),
  DailyEventQuickTemplate(
    text: 'ขอเบิกวัสดุเพิ่ม',
    defaultType: 'request',
  ),
];

final RegExp _kRecorderSuffixRe = RegExp(r'\s*\(ผู้กรอก:([^)]+)\)\s*$');

String normalizeDailyEventType(String? raw) {
  final code = (raw ?? '').trim().toLowerCase();
  for (final spec in kDailyEventTypes) {
    if (spec.code == code) return spec.code;
  }
  return 'info';
}

DailyEventTypeSpec dailyEventTypeSpecOf(String? raw) {
  final code = normalizeDailyEventType(raw);
  return kDailyEventTypes.firstWhere(
    (s) => s.code == code,
    orElse: () => kDailyEventTypes.first,
  );
}

bool isDailyEventUrgent(String? rawPriority) {
  final p = (rawPriority ?? '').trim().toLowerCase();
  return p == 'urgent' || p == 'high';
}

String normalizeDailyEventPriority(String? rawPriority) =>
    isDailyEventUrgent(rawPriority) ? 'urgent' : 'normal';

String stripDailyEventRecorderSuffix(String raw) =>
    raw.replaceAll(_kRecorderSuffixRe, '').trim();

String? extractDailyEventRecorderName(String raw) {
  final match = _kRecorderSuffixRe.firstMatch(raw);
  final name = match?.group(1)?.trim() ?? '';
  return name.isEmpty ? null : name;
}

bool isDailyEventRow(AppTransaction t) {
  if (t.category != 'DailyLog') return false;
  if ((t.subCategory ?? '').trim() != 'Event') return false;
  return stripDailyEventRecorderSuffix(t.description).isNotEmpty;
}

int? _clockMinutesOf(String? raw) {
  final clean = (raw ?? '').trim();
  if (clean.isEmpty) return null;
  final m = RegExp(r'(\d{1,2})\s*[:.]\s*(\d{2})').firstMatch(clean);
  if (m == null) return null;
  final h = int.tryParse(m.group(1)!);
  final min = int.tryParse(m.group(2)!);
  if (h == null || min == null || h < 0 || h > 23 || min < 0 || min > 59) {
    return null;
  }
  return h * 60 + min;
}

/// เวลาแสดงผลของเหตุการณ์ — ใช้ eventTime ก่อน หากว่างใช้เวลาจาก createdAt
String dailyEventDisplayTime(AppTransaction t) {
  final explicit = (t.eventTime ?? '').trim();
  if (explicit.isNotEmpty) return explicit;
  final created = t.createdAt;
  if (created == null) return '';
  final local = created.isUtc ? created.toLocal() : created;
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

int _eventSortKeyMinutes(AppTransaction t) {
  final explicit = _clockMinutesOf(t.eventTime);
  if (explicit != null) return explicit;
  final created = t.createdAt;
  if (created != null) {
    final local = created.isUtc ? created.toLocal() : created;
    return local.hour * 60 + local.minute;
  }
  return -1;
}

/// รายการเหตุการณ์ทั้งหมดของวันที่ระบุ เรียงใหม่สุดไว้ด้านบน
List<AppTransaction> dailyEventEntriesForDay({
  required String dayYmd,
  required Iterable<AppTransaction> transactions,
}) {
  final day = dayYmd.trim();
  final byId = <String, AppTransaction>{};
  for (final t in transactions) {
    if (t.date.trim() != day) continue;
    if (!isDailyEventRow(t)) continue;
    byId[t.id] = t;
  }
  final rows = byId.values.toList()
    ..sort((a, b) {
      final ma = _eventSortKeyMinutes(a);
      final mb = _eventSortKeyMinutes(b);
      if (ma != mb) return mb.compareTo(ma);
      final ca = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final cb = b.createdAt?.millisecondsSinceEpoch ?? 0;
      if (ca != cb) return cb.compareTo(ca);
      return b.id.compareTo(a.id);
    });
  return rows;
}

enum DailyEventFilter { all, urgent, issues }

bool matchesDailyEventFilter(AppTransaction tx, DailyEventFilter filter) {
  switch (filter) {
    case DailyEventFilter.all:
      return true;
    case DailyEventFilter.urgent:
      return isDailyEventUrgent(tx.eventPriority);
    case DailyEventFilter.issues:
      final type = normalizeDailyEventType(tx.eventType);
      return type == 'problem' || type == 'warning' || type == 'complaint';
  }
}

class DailyEventDayOverview {
  const DailyEventDayOverview({
    this.totalCount = 0,
    this.urgentCount = 0,
    this.issueCount = 0,
  });

  final int totalCount;
  final int urgentCount;
  final int issueCount;
}

DailyEventDayOverview summarizeDailyEvents(Iterable<AppTransaction> entries) {
  var total = 0;
  var urgent = 0;
  var issues = 0;
  for (final e in entries) {
    total++;
    if (isDailyEventUrgent(e.eventPriority)) urgent++;
    if (matchesDailyEventFilter(e, DailyEventFilter.issues)) issues++;
  }
  return DailyEventDayOverview(
    totalCount: total,
    urgentCount: urgent,
    issueCount: issues,
  );
}

/// เติมเทมเพลตด่วน — ถ้าช่องว่างจะเลือกประเภท+ความสำคัญให้ด้วย ถ้ามีข้อความแล้วจะต่อท้ายโดยไม่ซ้ำ
({String text, String type, String priority}) applyQuickEventTemplate({
  required String currentText,
  required String currentType,
  required String currentPriority,
  required DailyEventQuickTemplate template,
}) {
  final trimmed = currentText.trim();
  if (trimmed.isEmpty) {
    return (
      text: template.text,
      type: template.defaultType,
      priority: template.defaultPriority,
    );
  }
  final existingParts = trimmed
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toSet();
  final nextText = existingParts.contains(template.text)
      ? trimmed
      : '$trimmed, ${template.text}';
  return (
    text: nextText,
    type: normalizeDailyEventType(currentType),
    priority: normalizeDailyEventPriority(currentPriority),
  );
}
