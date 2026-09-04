import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_transaction.dart';
import '../models/employee.dart';
import 'advance_work_details.dart';
import 'line_messaging.dart';
import 'maintenance_catalog.dart';

const _kPendingLineNotifyPrefsKey = 'gm_pending_line_notify_v1';
const _kAttendanceLinePendingPrefsKey = 'gm_pending_attendance_line_v2';
const _kAttendanceLineWait = Duration(hours: 1);

Timer? _attendanceLineWaitTimer;
List<Employee> _attendanceLineWaitEmployees = const [];

/// ผลการแจ้ง LINE หลังบันทึกเบิกเงิน / ลางาน / แจ้งซ่อม
class AdvanceLineNotifyStatus {
  const AdvanceLineNotifyStatus._({
    required this.skipped,
    required this.ok,
    this.messageTh,
    this.queuedForRetry = false,
  });

  /// ไม่มี LINE User ID ของพนักงาน / env — ไม่ได้เรียก Edge
  factory AdvanceLineNotifyStatus.skippedNoRecipients() =>
      const AdvanceLineNotifyStatus._(
        skipped: true,
        ok: false,
        messageTh:
            'ยังไม่แจ้ง LINE — ไม่มีผู้รับ (ตั้ง LINE User ID พนักงาน หรือ LINE_ADVANCE_NOTIFY_USER_IDS)',
      );

  /// ส่งสำเร็จ (HTTP 200 และ ok !== false)
  factory AdvanceLineNotifyStatus.sent() =>
      const AdvanceLineNotifyStatus._(skipped: false, ok: true);

  factory AdvanceLineNotifyStatus.failed(String messageTh) =>
      AdvanceLineNotifyStatus._(
        skipped: false,
        ok: false,
        messageTh: messageTh,
      );

  factory AdvanceLineNotifyStatus.queuedForRetry() =>
      const AdvanceLineNotifyStatus._(
        skipped: false,
        ok: false,
        queuedForRetry: true,
        messageTh: 'บันทึกแล้ว จะแจ้ง LINE อัตโนมัติเมื่อออนไลน์',
      );

  /// รอข้อมูลอีกฝั่งก่อนแจ้ง (เช่น รอคนขับรถ)
  factory AdvanceLineNotifyStatus.waitingForMore(String messageTh) =>
      AdvanceLineNotifyStatus._(
        skipped: true,
        ok: true,
        messageTh: messageTh,
      );

  final bool skipped;
  final bool ok;
  final String? messageTh;
  final bool queuedForRetry;

  /// ข้อความต่อท้ายหลังบันทึกสำเร็จ
  String successSuffixTh({String sent = 'แจ้ง LINE แล้ว'}) {
    if (ok && !skipped) return sent;
    if (queuedForRetry) return 'จะแจ้ง LINE เมื่อออนไลน์';
    final m = (messageTh ?? '').trim();
    if (m.isNotEmpty) return m;
    return 'ยังไม่แจ้ง LINE';
  }
}

Future<List<String>> _adminLineRecipientIds() async {
  final to = <String>{};
  final extraRaw = dotenv.env['LINE_ADVANCE_NOTIFY_USER_IDS'] ?? '';
  for (final part in extraRaw.split(',')) {
    final u = normalizeLineRecipientId(part);
    if (u != null) to.add(u);
  }
  return to.toList();
}

List<String> _employeeLineRecipientIds(
  AppTransaction tx,
  List<Employee> employees,
) {
  final to = <String>{};
  for (final id in tx.employeeIds) {
    Employee? e;
    for (final x in employees) {
      if (x.id == id) {
        e = x;
        break;
      }
    }
    final u = normalizeLineUserId(e?.lineUserId ?? '');
    if (u != null) to.add(u);
  }
  return to.toList();
}

Future<void> _enqueuePendingLineNotify({
  required String text,
  required List<String> to,
}) async {
  if (to.isEmpty || text.trim().isEmpty) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPendingLineNotifyPrefsKey);
    final list = <Map<String, dynamic>>[];
    if (raw != null && raw.trim().isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map) {
            list.add(Map<String, dynamic>.from(item));
          }
        }
      }
    }
    list.add(<String, dynamic>{
      'text': text,
      'to': to,
      'at': DateTime.now().toIso8601String(),
    });
    // กันคิวยาวเกิน
    while (list.length > 40) {
      list.removeAt(0);
    }
    await prefs.setString(_kPendingLineNotifyPrefsKey, jsonEncode(list));
  } catch (e, st) {
    debugPrint('_enqueuePendingLineNotify failed: $e\n$st');
  }
}

/// ส่งคิวแจ้ง LINE ที่ค้างตอนออฟไลน์ (เรียกหลังซิงก์สำเร็จ)
Future<int> flushPendingLineNotifies() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPendingLineNotifyPrefsKey);
    if (raw == null || raw.trim().isEmpty) return 0;
    final decoded = jsonDecode(raw);
    if (decoded is! List || decoded.isEmpty) {
      await prefs.remove(_kPendingLineNotifyPrefsKey);
      return 0;
    }
    final remaining = <Map<String, dynamic>>[];
    var sent = 0;
    for (final item in decoded) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final text = '${map['text'] ?? ''}'.trim();
      final toRaw = map['to'];
      final to = <String>[];
      if (toRaw is List) {
        for (final x in toRaw) {
          final u = normalizeLineRecipientId('$x') ?? normalizeLineUserId('$x');
          if (u != null) to.add(u);
        }
      }
      if (text.isEmpty || to.isEmpty) continue;
      try {
        final res = await invokeNotifyAdvanceLine(text: text, to: to);
        final body = res.data;
        if (res.status >= 400 || (body is Map && body['ok'] == false)) {
          remaining.add(map);
          continue;
        }
        sent++;
      } catch (_) {
        remaining.add(map);
      }
    }
    if (remaining.isEmpty) {
      await prefs.remove(_kPendingLineNotifyPrefsKey);
    } else {
      await prefs.setString(
        _kPendingLineNotifyPrefsKey,
        jsonEncode(remaining),
      );
    }
    return sent;
  } catch (e, st) {
    debugPrint('flushPendingLineNotifies failed: $e\n$st');
    return 0;
  }
}

Future<AdvanceLineNotifyStatus> _sendOrQueueLineNotify({
  required String text,
  required List<String> to,
  required String debugTag,
}) async {
  if (to.isEmpty) {
    return AdvanceLineNotifyStatus.skippedNoRecipients();
  }
  try {
    final res = await invokeNotifyAdvanceLine(text: text, to: to);
    final body = res.data;
    if (res.status >= 500) {
      final msg = 'แจ้ง LINE ไม่สำเร็จ (HTTP ${res.status}) — ${res.data}';
      debugPrint('$debugTag: $msg');
      await _enqueuePendingLineNotify(text: text, to: to);
      return AdvanceLineNotifyStatus.queuedForRetry();
    }
    if (res.status >= 400) {
      final msg = 'แจ้ง LINE ไม่สำเร็จ (HTTP ${res.status}) — ${res.data}';
      debugPrint('$debugTag: $msg');
      return AdvanceLineNotifyStatus.failed(msg);
    }
    if (body is Map && body['ok'] == false) {
      final hint = '${body['hint_th'] ?? body['message'] ?? body['error']}';
      debugPrint('$debugTag: $hint $body');
      return AdvanceLineNotifyStatus.failed(
        hint.isEmpty ? 'แจ้ง LINE ไม่สำเร็จ' : hint,
      );
    }
    return AdvanceLineNotifyStatus.sent();
  } catch (e, st) {
    final msg = lineNotifyAdvanceInvokeErrorMessage(e);
    debugPrint('$debugTag failed: $msg\n$st');
    await _enqueuePendingLineNotify(text: text, to: to);
    return AdvanceLineNotifyStatus.queuedForRetry();
  }
}

String _formatBahtTh(num value) {
  final isInt = value == value.roundToDouble();
  final raw = isInt ? value.round().toString() : value.toStringAsFixed(2);
  final parts = raw.split('.');
  final intPart = parts[0];
  final buf = StringBuffer();
  final len = intPart.length;
  for (var i = 0; i < len; i++) {
    if (i > 0 && (len - i) % 3 == 0) buf.write(',');
    buf.write(intPart[i]);
  }
  if (parts.length > 1) buf.write('.${parts[1]}');
  return buf.toString();
}

String _formatDateThaiBE(String ymd) {
  const mm = [
    'ม.ค.',
    'ก.พ.',
    'มี.ค.',
    'เม.ย.',
    'พ.ค.',
    'มิ.ย.',
    'ก.ค.',
    'ส.ค.',
    'ก.ย.',
    'ต.ค.',
    'พ.ย.',
    'ธ.ค.',
  ];
  try {
    final segs = ymd.split('-');
    if (segs.length != 3) return ymd;
    final y = int.parse(segs[0]);
    final m = int.parse(segs[1]);
    final d = int.parse(segs[2]);
    if (m < 1 || m > 12) return ymd;
    return '$d ${mm[m - 1]} ${y + 543}';
  } catch (_) {
    return ymd;
  }
}

String _advancePayoutSlotTh(AdvanceGmMeta meta) =>
    meta.payoutSlot == AdvanceGmMeta.evening ? 'ช่วงเย็น' : 'ช่วงกลางวัน';

String _advancePaymentTh(AdvanceGmMeta meta) {
  if (meta.paymentMethod == AdvanceGmMeta.transfer) {
    final b = meta.bank.trim();
    final a = meta.accountNumber.trim();
    if (b.isNotEmpty || a.isNotEmpty) {
      final parts = <String>[];
      if (b.isNotEmpty) parts.add(b);
      if (a.isNotEmpty) parts.add('เลข $a');
      return 'เงินโอน (${parts.join(' · ')})';
    }
    return 'เงินโอน';
  }
  return 'เงินสด';
}

/// ข้อความส่ง LINE — จัดรูปแบบอ่านง่าย (UTF-16 ไม่เกิน 5000 โดย Edge จะตัดให้อีกที)
String buildAdvanceLineText(AppTransaction tx, List<Employee> employees) {
  final ids = tx.employeeIds;
  final names = ids
      .map((id) {
        Employee? found;
        for (final e in employees) {
          if (e.id == id) {
            found = e;
            break;
          }
        }
        return (found?.nickname ?? found?.name ?? id).trim();
      })
      .where((s) => s.isNotEmpty)
      .join(', ');
  final meta = AdvanceGmMeta.decode(tx.workDetails);
  final amt = tx.amount;
  final per = tx.advanceAmount ?? 0;
  final n = ids.length;
  final namesLine = names.isEmpty ? '—' : names;
  final totalStr = _formatBahtTh(amt);
  final perStr = _formatBahtTh(per);
  final dateLine = '${_formatDateThaiBE(tx.date)} (${tx.date})';
  final lines = <String>[
    '━━━━ GoldenMole ━━━━',
    '',
    'รายการเบิกเงิน',
    '',
    'วันที่ :',
    dateLine,
    '',
    'ชื่อ :',
    namesLine,
    '',
    'จำนวนเงิน :',
    'รวม $totalStr บาท ($n คน × $perStr บาท/คน)',
    '',
    'ต้องการรับเงินช่วง :',
    _advancePayoutSlotTh(meta),
    '',
    'ได้เงินเป็น :',
    _advancePaymentTh(meta),
  ];
  final raw = lines.join('\n').trim();
  return raw.length > 4800 ? raw.substring(0, 4800) : raw;
}

/// หลังบันทึกเบิกเงินออนไลน์ — เรียก Edge `notify-advance-line` (ต้องมี LINE_CHANNEL_ACCESS_TOKEN ฝั่ง Supabase)
Future<AdvanceLineNotifyStatus> notifyAdvanceLineAfterSaved(
  AppTransaction tx,
  List<Employee> employees,
) async {
  if (tx.category != 'Labor') {
    return AdvanceLineNotifyStatus.skippedNoRecipients();
  }
  if ((tx.subCategory ?? '').trim().toLowerCase() != 'advance') {
    return AdvanceLineNotifyStatus.skippedNoRecipients();
  }

  final to = <String>{
    ..._employeeLineRecipientIds(tx, employees),
    ...await _adminLineRecipientIds(),
  };
  final text = buildAdvanceLineText(tx, employees);
  return _sendOrQueueLineNotify(
    text: text,
    to: to.toList(),
    debugTag: 'notifyAdvanceLineAfterSaved',
  );
}

String _leaveKindTh(String? subCategory) {
  final s = (subCategory ?? '').trim().toLowerCase();
  if (s == 'sick') return 'ลาป่วย';
  return 'ลากิจ';
}

const _leaveHalfMorningMeta = 'leave_half:morning';
const _leaveHalfAfternoonMeta = 'leave_half:afternoon';

String _formatLeaveDays(double? value) {
  if (value == null || value.isNaN || value <= 0) return '—';
  final v = value;
  if ((v - v.roundToDouble()).abs() < 1e-9) return '${v.round()}';
  return v.toString();
}

/// ข้อความส่ง LINE หลังบันทึกลา — ใช้ Edge เดียวกับเบิกเงิน (`notify-advance-line`)
String buildLeaveLineText(AppTransaction tx, List<Employee> employees) {
  final ids = tx.employeeIds;
  final names = ids
      .map((id) {
        Employee? found;
        for (final e in employees) {
          if (e.id == id) {
            found = e;
            break;
          }
        }
        return (found?.nickname ?? found?.name ?? id).trim();
      })
      .where((s) => s.isNotEmpty)
      .join(', ');
  final reason = (tx.leaveReason ?? '').trim();
  final reasonLine = reason.isNotEmpty ? reason : '—';
  final daysStr = _formatLeaveDays(tx.leaveDays);
  final wd = (tx.workDetails ?? '').trim();
  var dayLine = '$daysStr วัน';
  if (tx.leaveDays != null && (tx.leaveDays! - 0.5).abs() < 1e-6) {
    if (wd == _leaveHalfMorningMeta) {
      dayLine = '0.5 วัน (ครึ่งเช้า)';
    } else if (wd == _leaveHalfAfternoonMeta) {
      dayLine = '0.5 วัน (ครึ่งบ่าย)';
    } else {
      dayLine = '0.5 วัน (ครึ่งวัน)';
    }
  }
  final namesLine = names.isEmpty ? '—' : names;
  final dateLine = '${_formatDateThaiBE(tx.date)} (${tx.date})';
  final lines = <String>[
    '━━━━ GoldenMole ━━━━',
    '',
    'บันทึกลางาน',
    '',
    'ประเภท :',
    _leaveKindTh(tx.subCategory),
    '',
    'วันที่เริ่มลา :',
    dateLine,
    '',
    'ชื่อ :',
    namesLine,
    '',
    'จำนวนวัน :',
    dayLine,
    '',
    'เหตุผล :',
    reasonLine,
  ];
  final raw = lines.join('\n').trim();
  return raw.length > 4800 ? raw.substring(0, 4800) : raw;
}

/// หลังบันทึกลางาน — เรียก Edge `notify-advance-line` (ต้องมี LINE_CHANNEL_ACCESS_TOKEN ฝั่ง Supabase)
Future<AdvanceLineNotifyStatus> notifyLeaveLineAfterSaved(
  AppTransaction tx,
  List<Employee> employees,
) async {
  if (tx.category.trim() != 'Leave') {
    return AdvanceLineNotifyStatus.skippedNoRecipients();
  }

  final to = <String>{
    ..._employeeLineRecipientIds(tx, employees),
    ...await _adminLineRecipientIds(),
  };
  final text = buildLeaveLineText(tx, employees);
  return _sendOrQueueLineNotify(
    text: text,
    to: to.toList(),
    debugTag: 'notifyLeaveLineAfterSaved',
  );
}

String buildMaintenanceRepairLineText(AppTransaction tx) {
  final asset = (tx.vehicleName ?? tx.vehicleId ?? '').trim();
  final group =
      MaintenanceAssetGroupX.tryParse(tx.workType)?.label ?? '—';
  final detail = maintenanceDetailFromDescription(
    tx.description,
    kMaintenanceTypeRepairRequest,
  );
  final urgency = ((tx.eventPriority ?? '').trim() == 'urgent') ? 'ด่วน' : 'ปกติ';
  final dateLine = '${_formatDateThaiBE(tx.date)} (${tx.date})';
  final lines = <String>[
    '━━━━ GoldenMole ━━━━',
    '',
    'แจ้งซ่อม',
    '',
    'วันที่ :',
    dateLine,
    '',
    'กลุ่ม :',
    group,
    '',
    'รายการ :',
    asset.isEmpty ? '—' : asset,
    '',
    'ความเร่งด่วน :',
    urgency,
    '',
    'อาการ / รายละเอียด :',
    detail.isEmpty ? '—' : detail,
  ];
  final raw = lines.join('\n').trim();
  return raw.length > 4800 ? raw.substring(0, 4800) : raw;
}

/// หลังบันทึกแจ้งซ่อม — แจ้งผู้ดูแลผ่าน Edge เดียวกับเบิกเงิน
Future<AdvanceLineNotifyStatus> notifyMaintenanceRepairLineAfterSaved(
  AppTransaction tx,
) async {
  if (!isMaintenanceRepairRequest(tx)) {
    return AdvanceLineNotifyStatus.skippedNoRecipients();
  }

  final to = await _adminLineRecipientIds();
  final text = buildMaintenanceRepairLineText(tx);
  return _sendOrQueueLineNotify(
    text: text,
    to: to,
    debugTag: 'notifyMaintenanceRepairLineAfterSaved',
  );
}

String _employeeDisplayName(String id, List<Employee> employees) {
  for (final e in employees) {
    if (e.id == id) {
      final nick = e.nickname.trim();
      if (nick.isNotEmpty) return nick;
      final name = e.name.trim();
      return name.isEmpty ? id : name;
    }
  }
  return id;
}

String _joinNames(Iterable<String> ids, List<Employee> employees) {
  final names = ids
      .map((id) => _employeeDisplayName(id, employees))
      .where((s) => s.trim().isNotEmpty)
      .toList();
  if (names.isEmpty) return '—';
  return names.join(', ');
}

String _formatOptionalBaht(double amount) {
  if (amount <= 0) return '—';
  return '${_formatBahtTh(amount)} บาท';
}

/// ข้อความ LINE หลังบันทึกซ่อม/ดูแลรักษา (ไม่ใช่แจ้งซ่อม)
String buildMaintenanceServiceLogLineText(AppTransaction tx) {
  final asset = (tx.vehicleName ?? tx.vehicleId ?? '').trim();
  final group =
      MaintenanceAssetGroupX.tryParse(tx.workType)?.label ?? '—';
  final type = (tx.subCategory ?? '').trim();
  final detail = maintenanceDetailFromDescription(
    tx.description,
    type.isEmpty ? kMaintenanceTypeRepair : type,
  );
  final dateLine = '${_formatDateThaiBE(tx.date)} (${tx.date})';
  final lines = <String>[
    '━━━━ GoldenMole ━━━━',
    '',
    'บันทึกบำรุงรักษา',
    '',
    'วันที่ :',
    dateLine,
    '',
    'กลุ่ม :',
    group,
    '',
    'รายการ :',
    asset.isEmpty ? '—' : asset,
    '',
    'ประเภท :',
    type.isEmpty ? '—' : type,
    '',
    'จำนวนเงิน :',
    _formatOptionalBaht(tx.amount),
    '',
    'รายละเอียด :',
    detail.isEmpty ? '—' : detail,
  ];
  final raw = lines.join('\n').trim();
  return raw.length > 4800 ? raw.substring(0, 4800) : raw;
}

Future<AdvanceLineNotifyStatus> notifyMaintenanceServiceLogLineAfterSaved(
  AppTransaction tx,
) async {
  if (tx.category.trim() != kMaintenanceTxCategory) {
    return AdvanceLineNotifyStatus.skippedNoRecipients();
  }
  if (isMaintenanceRepairRequest(tx)) {
    return AdvanceLineNotifyStatus.skippedNoRecipients();
  }

  final to = await _adminLineRecipientIds();
  final text = buildMaintenanceServiceLogLineText(tx);
  return _sendOrQueueLineNotify(
    text: text,
    to: to,
    debugTag: 'notifyMaintenanceServiceLogLineAfterSaved',
  );
}

/// สรุปเช็คชื่อสำหรับ LINE — รวมท่าทราย + คนขับรถ (รอข้อมูลครบก่อนส่ง)
enum AttendanceLineSection { sandYard, driver }

class AttendanceLineSectionUpdate {
  const AttendanceLineSectionUpdate({
    required this.dateYmd,
    required this.section,
    required this.presentIds,
    required this.leaveIds,
  });

  final String dateYmd;
  final AttendanceLineSection section;
  final List<String> presentIds;
  final List<String> leaveIds;
}

/// ข้อความรายงานเช็คชื่อรูปแบบรวม (ตามที่ทีมใช้แจ้งใน LINE)
String buildCombinedAttendanceLineText({
  required String dateYmd,
  required String sectionTitle,
  required List<String> presentIds,
  required List<String> leaveIds,
  required List<Employee> employees,
}) {
  final dateLine = '${_formatDateThaiBE(dateYmd)} ($dateYmd)';
  final presentCount = presentIds.length;
  final leaveCount = leaveIds.length;
  final lines = <String>[
    '━━━━ GoldenMole ━━━━',
    'วันที่ : $dateLine',
    'เช็คชื่อ · $sectionTitle',
    'มาทำงาน :$presentCount คน',
    '',
    'รายชื่อมาทำงาน :',
    _joinNames(presentIds, employees),
    '',
    'ลางาน : $leaveCount คน',
    'รายชื่อลางาน : ${_joinNames(leaveIds, employees)}',
  ];
  final raw = lines.join('\n').trim();
  return raw.length > 4800 ? raw.substring(0, 4800) : raw;
}

String _attendanceFingerprint({
  required String mode,
  required List<String> presentIds,
  required List<String> leaveIds,
}) {
  final p = [...presentIds]..sort();
  final l = [...leaveIds]..sort();
  return '$mode|${p.join(',')}|${l.join(',')}';
}

Map<String, dynamic> _attendanceDayState(Map<String, dynamic> root, String ymd) {
  final existing = root[ymd];
  if (existing is Map) return Map<String, dynamic>.from(existing);
  return <String, dynamic>{};
}

Future<Map<String, dynamic>> _readAttendancePendingRoot() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_kAttendanceLinePendingPrefsKey);
  if (raw == null || raw.trim().isEmpty) return <String, dynamic>{};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {}
  return <String, dynamic>{};
}

Future<void> _writeAttendancePendingRoot(Map<String, dynamic> root) async {
  final prefs = await SharedPreferences.getInstance();
  // เก็บเฉพาะ ~14 วันล่าสุด
  final keys = root.keys.toList()..sort();
  while (keys.length > 14) {
    root.remove(keys.removeAt(0));
  }
  await prefs.setString(_kAttendanceLinePendingPrefsKey, jsonEncode(root));
}

List<String> _stringList(dynamic raw) {
  if (raw is! List) return const [];
  return [
    for (final x in raw)
      if ('$x'.trim().isNotEmpty) '$x'.trim(),
  ];
}

DateTime? _parseIso(dynamic raw) {
  if (raw is! String || raw.trim().isEmpty) return null;
  return DateTime.tryParse(raw.trim());
}

/// อัปเดตข้อมูลเช็คชื่อแล้วส่ง LINE เมื่อครบทั้งสองฝั่ง หรือครบเวลา 1 ชม.
Future<AdvanceLineNotifyStatus> upsertAttendanceLineAndMaybeNotify(
  AttendanceLineSectionUpdate update,
  List<Employee> employees, {
  DateTime? now,
}) async {
  final ymd = update.dateYmd.trim();
  if (ymd.isEmpty) {
    return AdvanceLineNotifyStatus.skippedNoRecipients();
  }
  if (update.presentIds.isEmpty && update.leaveIds.isEmpty) {
    return AdvanceLineNotifyStatus.skippedNoRecipients();
  }

  final clock = now ?? DateTime.now();
  final root = await _readAttendancePendingRoot();
  final day = _attendanceDayState(root, ymd);

  if (update.section == AttendanceLineSection.sandYard) {
    day['sandPresent'] = update.presentIds;
    day['sandLeave'] = update.leaveIds;
    day['sandAt'] = clock.toIso8601String();
  } else {
    day['drvPresent'] = update.presentIds;
    day['drvLeave'] = update.leaveIds;
    day['drvAt'] = clock.toIso8601String();
  }
  root[ymd] = day;
  await _writeAttendancePendingRoot(root);

  final status = await _evaluateAndSendAttendanceLineDay(
    dateYmd: ymd,
    day: day,
    employees: employees,
    now: clock,
    persistRoot: root,
  );
  if (status.skipped &&
      (status.messageTh ?? '').contains('รอข้อมูล')) {
    _armAttendanceLineWaitTimer(employees);
  } else {
    _attendanceLineWaitTimer?.cancel();
    _attendanceLineWaitTimer = null;
  }
  return status;
}

void _armAttendanceLineWaitTimer(List<Employee> employees) {
  _attendanceLineWaitEmployees = List<Employee>.from(employees);
  _attendanceLineWaitTimer?.cancel();
  // เผื่อนาฬิกาเครื่องคลาดเล็กน้อย — ยิงหลังครบ 1 ชม. + 5 วินาที
  _attendanceLineWaitTimer = Timer(
    _kAttendanceLineWait + const Duration(seconds: 5),
    () {
      unawaited(
        flushPendingAttendanceLineReports(_attendanceLineWaitEmployees),
      );
    },
  );
}

Future<AdvanceLineNotifyStatus> _evaluateAndSendAttendanceLineDay({
  required String dateYmd,
  required Map<String, dynamic> day,
  required List<Employee> employees,
  required DateTime now,
  required Map<String, dynamic> persistRoot,
}) async {
  final sandPresent = _stringList(day['sandPresent']);
  final sandLeave = _stringList(day['sandLeave']);
  final drvPresent = _stringList(day['drvPresent']);
  final drvLeave = _stringList(day['drvLeave']);
  final sandAt = _parseIso(day['sandAt']);
  final drvAt = _parseIso(day['drvAt']);

  final hasSand = sandPresent.isNotEmpty || sandLeave.isNotEmpty;
  final hasDrv = drvPresent.isNotEmpty || drvLeave.isNotEmpty;

  if (!hasSand && !hasDrv) {
    return AdvanceLineNotifyStatus.skippedNoRecipients();
  }

  String mode;
  String title;
  List<String> present;
  List<String> leave;

  if (hasSand && hasDrv) {
    mode = 'full';
    title = 'คนขับรถ และ พนักงานท่าทราย';
    // คนขับก่อน แล้วตามด้วยท่าทราย (ตามรูปแบบรายงานทีม)
    present = [...drvPresent, ...sandPresent];
    leave = [...drvLeave, ...sandLeave];
  } else if (hasSand && !hasDrv) {
    if (sandAt == null || now.difference(sandAt) < _kAttendanceLineWait) {
      return AdvanceLineNotifyStatus.waitingForMore(
        'รอข้อมูลคนขับรถครบแล้วค่อยแจ้ง LINE (เกิน 1 ชม. จะรายงานเฉพาะท่าทราย)',
      );
    }
    mode = 'sand';
    title = 'พนักงานท่าทราย';
    present = sandPresent;
    leave = sandLeave;
  } else {
    // มีแต่คนขับรถ
    if (drvAt == null || now.difference(drvAt) < _kAttendanceLineWait) {
      return AdvanceLineNotifyStatus.waitingForMore(
        'รอข้อมูลพนักงานท่าทรายครบแล้วค่อยแจ้ง LINE (เกิน 1 ชม. จะรายงานเฉพาะคนขับรถ)',
      );
    }
    mode = 'drv';
    title = 'คนขับรถ';
    present = drvPresent;
    leave = drvLeave;
  }

  final fingerprint = _attendanceFingerprint(
    mode: mode,
    presentIds: present,
    leaveIds: leave,
  );
  if (day['lastSentFingerprint'] == fingerprint) {
    return AdvanceLineNotifyStatus.waitingForMore('แจ้ง LINE รายงานนี้ไปแล้ว');
  }

  final text = buildCombinedAttendanceLineText(
    dateYmd: dateYmd,
    sectionTitle: title,
    presentIds: present,
    leaveIds: leave,
    employees: employees,
  );
  final to = await _adminLineRecipientIds();
  final status = await _sendOrQueueLineNotify(
    text: text,
    to: to,
    debugTag: 'attendanceLineReport',
  );
  if (status.ok && !status.skipped) {
    day['lastSentFingerprint'] = fingerprint;
    day['lastSentAt'] = now.toIso8601String();
    day['lastSentMode'] = mode;
    persistRoot[dateYmd] = day;
    await _writeAttendancePendingRoot(persistRoot);
  }
  return status;
}

/// ตรวจคิวรายงานเช็คชื่อที่รอครบ 1 ชม. แล้วส่ง (เรียกตอนเปิดแอป/ซิงก์)
Future<int> flushPendingAttendanceLineReports(List<Employee> employees) async {
  final root = await _readAttendancePendingRoot();
  if (root.isEmpty) return 0;
  final now = DateTime.now();
  var sent = 0;
  for (final entry in root.entries.toList()) {
    final ymd = entry.key;
    if (entry.value is! Map) continue;
    final day = Map<String, dynamic>.from(entry.value as Map);
    final beforeFp = '${day['lastSentFingerprint'] ?? ''}';
    final status = await _evaluateAndSendAttendanceLineDay(
      dateYmd: ymd,
      day: day,
      employees: employees,
      now: now,
      persistRoot: root,
    );
    if (status.ok && !status.skipped) {
      final after = await _readAttendancePendingRoot();
      final dayAfter = after[ymd];
      final afterFp =
          dayAfter is Map ? '${dayAfter['lastSentFingerprint'] ?? ''}' : '';
      if (afterFp.isNotEmpty && afterFp != beforeFp) sent++;
    }
  }
  return sent;
}

/// แถวสรุปเที่ยวรถสำหรับ LINE
class VehicleTripLineItem {
  const VehicleTripLineItem({
    required this.vehicle,
    required this.driverName,
    required this.billingLabel,
    required this.detailLine,
  });

  final String vehicle;
  final String driverName;
  final String billingLabel;
  final String detailLine;
}

String buildVehicleTripLineText({
  required String dateYmd,
  required List<VehicleTripLineItem> items,
}) {
  final dateLine = '${_formatDateThaiBE(dateYmd)} ($dateYmd)';
  final lines = <String>[
    '━━━━ GoldenMole ━━━━',
    '',
    'บันทึกรถดรัม / จำนวนเที่ยว',
    '',
    'วันที่ :',
    dateLine,
    '',
    'จำนวนรถ :',
    '${items.length} คัน',
  ];
  for (var i = 0; i < items.length; i++) {
    final it = items[i];
    lines.addAll([
      '',
      '${i + 1}) ${it.vehicle}',
      'คนขับ : ${it.driverName}',
      'รูปแบบ : ${it.billingLabel}',
      it.detailLine,
    ]);
  }
  final raw = lines.join('\n').trim();
  return raw.length > 4800 ? raw.substring(0, 4800) : raw;
}

Future<AdvanceLineNotifyStatus> notifyVehicleTripLineAfterSaved({
  required String dateYmd,
  required List<VehicleTripLineItem> items,
}) async {
  if (items.isEmpty) {
    return AdvanceLineNotifyStatus.skippedNoRecipients();
  }
  final to = await _adminLineRecipientIds();
  final text = buildVehicleTripLineText(dateYmd: dateYmd, items: items);
  return _sendOrQueueLineNotify(
    text: text,
    to: to,
    debugTag: 'notifyVehicleTripLineAfterSaved',
  );
}
