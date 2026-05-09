import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../models/app_transaction.dart';
import '../models/employee.dart';
import 'advance_work_details.dart';
import 'line_messaging.dart';

/// ผลการแจ้ง LINE หลังบันทึกเบิกเงิน
class AdvanceLineNotifyStatus {
  const AdvanceLineNotifyStatus._({
    required this.skipped,
    required this.ok,
    this.messageTh,
  });

  /// ไม่มี LINE User ID ของพนักงาน / env — ไม่ได้เรียก Edge
  factory AdvanceLineNotifyStatus.skippedNoRecipients() =>
      const AdvanceLineNotifyStatus._(skipped: true, ok: true);

  /// ส่งสำเร็จ (HTTP 200 และ ok !== false)
  factory AdvanceLineNotifyStatus.sent() =>
      const AdvanceLineNotifyStatus._(skipped: false, ok: true);

  factory AdvanceLineNotifyStatus.failed(String messageTh) =>
      AdvanceLineNotifyStatus._(
        skipped: false,
        ok: false,
        messageTh: messageTh,
      );

  final bool skipped;
  final bool ok;
  final String? messageTh;
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
  final extraRaw = dotenv.env['LINE_ADVANCE_NOTIFY_USER_IDS'] ?? '';
  for (final part in extraRaw.split(',')) {
    final u = normalizeLineUserId(part);
    if (u != null) to.add(u);
  }
  if (to.isEmpty) {
    return AdvanceLineNotifyStatus.skippedNoRecipients();
  }

  final text = buildAdvanceLineText(tx, employees);
  try {
    final res = await invokeNotifyAdvanceLine(text: text, to: to.toList());
    final body = res.data;
    if (res.status >= 400) {
      final msg =
          'แจ้ง LINE ไม่สำเร็จ (HTTP ${res.status}) — ${res.data}';
      debugPrint('notifyAdvanceLineAfterSaved: $msg');
      return AdvanceLineNotifyStatus.failed(msg);
    }
    if (body is Map && body['ok'] == false) {
      final hint = '${body['hint_th'] ?? body['message'] ?? body['error']}';
      debugPrint('notifyAdvanceLineAfterSaved: $hint $body');
      return AdvanceLineNotifyStatus.failed(
        hint.isEmpty ? 'แจ้ง LINE ไม่สำเร็จ' : hint,
      );
    }
    return AdvanceLineNotifyStatus.sent();
  } catch (e, st) {
    final msg = lineNotifyAdvanceInvokeErrorMessage(e);
    debugPrint('notifyAdvanceLineAfterSaved failed: $msg\n$st');
    return AdvanceLineNotifyStatus.failed(msg);
  }
}

String _leaveKindTh(String? subCategory) {
  final s = (subCategory ?? '').trim().toLowerCase();
  if (s == 'sick') return 'ลาป่วย';
  return 'ลากิจ';
}

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
    '$daysStr วัน',
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
  final extraRaw = dotenv.env['LINE_ADVANCE_NOTIFY_USER_IDS'] ?? '';
  for (final part in extraRaw.split(',')) {
    final u = normalizeLineUserId(part);
    if (u != null) to.add(u);
  }
  if (to.isEmpty) {
    return AdvanceLineNotifyStatus.skippedNoRecipients();
  }

  final text = buildLeaveLineText(tx, employees);
  try {
    final res = await invokeNotifyAdvanceLine(text: text, to: to.toList());
    final body = res.data;
    if (res.status >= 400) {
      final msg =
          'แจ้ง LINE ไม่สำเร็จ (HTTP ${res.status}) — ${res.data}';
      debugPrint('notifyLeaveLineAfterSaved: $msg');
      return AdvanceLineNotifyStatus.failed(msg);
    }
    if (body is Map && body['ok'] == false) {
      final hint = '${body['hint_th'] ?? body['message'] ?? body['error']}';
      debugPrint('notifyLeaveLineAfterSaved: $hint $body');
      return AdvanceLineNotifyStatus.failed(
        hint.isEmpty ? 'แจ้ง LINE ไม่สำเร็จ' : hint,
      );
    }
    return AdvanceLineNotifyStatus.sent();
  } catch (e, st) {
    final msg = lineNotifyAdvanceInvokeErrorMessage(e);
    debugPrint('notifyLeaveLineAfterSaved failed: $msg\n$st');
    return AdvanceLineNotifyStatus.failed(msg);
  }
}
