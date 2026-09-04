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

  final bool skipped;
  final bool ok;
  final String? messageTh;
  final bool queuedForRetry;

  /// ข้อความต่อท้ายหลังบันทึกสำเร็จ
  String successSuffixTh({String sent = 'แจ้ง LINE แล้ว'}) {
    if (ok && !skipped) return sent;
    if (queuedForRetry) return 'จะแจ้ง LINE เมื่อออนไลน์';
    if (skipped || !ok) {
      final m = (messageTh ?? '').trim();
      if (m.isNotEmpty) return m;
      return 'ยังไม่แจ้ง LINE';
    }
    return sent;
  }
}

Future<List<String>> _adminLineRecipientIds() async {
  final to = <String>{};
  final extraRaw = dotenv.env['LINE_ADVANCE_NOTIFY_USER_IDS'] ?? '';
  for (final part in extraRaw.split(',')) {
    final u = normalizeLineUserId(part);
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
          final u = normalizeLineUserId('$x');
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
