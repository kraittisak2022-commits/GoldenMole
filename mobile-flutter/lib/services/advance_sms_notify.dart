import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_transaction.dart';
import '../models/employee.dart';
import '../utils/thai_phone.dart';

String _buildAdvanceSmsText(AppTransaction tx, List<Employee> employees) {
  final ids = tx.employeeIds;
  final names = ids
      .map((id) {
        Employee? e;
        for (final x in employees) {
          if (x.id == id) {
            e = x;
            break;
          }
        }
        final n = (e?.nickname ?? e?.name ?? id).trim();
        return n.isEmpty ? id : n;
      })
      .join(', ');
  final n = ids.length;
  final per = (tx.advanceAmount ?? 0).toStringAsFixed(0);
  final buf =
      'GoldenMole เบิกเงิน วันที่ ${tx.date} $nคน รวม${tx.amount.toStringAsFixed(0)}บ '
      'คนละ$perบ ${names.isNotEmpty ? '($names) ' : ''}${tx.description.trim()}';
  final s = buf.trim();
  return s.length <= 480 ? s : s.substring(0, 480);
}

/// SMS หลังบันทึกเบิกเงิน (ไม่ throw — ไม่ให้กระทบ UX หลัก)
Future<void> notifyAdvanceSmsAfterSave({
  required AppTransaction transaction,
  required List<Employee> employees,
}) async {
  if (transaction.category != 'Labor' ||
      (transaction.subCategory ?? '').toLowerCase() != 'advance') {
    return;
  }
  final phones = <String>{};
  for (final id in transaction.employeeIds) {
    Employee? e;
    for (final x in employees) {
      if (x.id == id) {
        e = x;
        break;
      }
    }
    final p = normalizeThaiPhone(e?.phone);
    if (p != null) phones.add(p);
  }
  final extra = dotenv.env['SMS_ADVANCE_NOTIFY_EXTRA'] ?? '';
  for (final part in extra.split(',')) {
    final p = normalizeThaiPhone(part.trim());
    if (p != null) phones.add(p);
  }
  if (phones.isEmpty) return;

  try {
    final text = _buildAdvanceSmsText(transaction, employees);
    await Supabase.instance.client.functions.invoke(
      'send-advance-sms',
      body: {
        'text': text,
        'destinations': phones.toList(),
      },
    );
  } catch (_) {
    // เงียบ — บันทึกธุรกรรมสำเร็จแล้ว
  }
}
