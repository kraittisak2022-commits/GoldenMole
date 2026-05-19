import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// บริบทตอนผู้ใช้กดบันทึก/ส่งข้อมูล — ใช้แสดงใน SnackBar เมื่อเกิดข้อผิดพลาด
class SaveErrorContext {
  const SaveErrorContext({
    required this.page,
    required this.action,
    required this.button,
  });

  final String page;
  final String action;
  final String button;
}

/// ข้อผิดพลาดจากการตรวจฟอร์มก่อนบันทึก (รู้จุด/ฟิลด์ที่ผิด)
class UserSaveException implements Exception {
  UserSaveException(
    this.message, {
    required this.context,
    this.field,
  });

  final String message;
  final SaveErrorContext context;
  final String? field;

  @override
  String toString() => message;
}

String formatSaveErrorMessage(
  Object error, {
  SaveErrorContext? context,
}) {
  final cause = error is UserSaveException
      ? error.message
      : error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
  final field = error is UserSaveException ? error.field : null;
  final ctx = error is UserSaveException ? error.context : context;

  final lines = <String>['บันทึกไม่สำเร็จ'];
  if (ctx != null) {
    lines.add('หน้า: ${ctx.page}');
    lines.add('รายการ: ${ctx.action}');
    lines.add('ปุ่ม: ${ctx.button}');
  }
  if (field != null && field.trim().isNotEmpty) {
    lines.add('จุดที่ผิด: ${field.trim()}');
  }
  lines.add('สาเหตุ: $cause');
  return lines.join('\n');
}

/// ส่งรายงาน error ขึ้นเซิร์ฟเวอร์ — คืน `id` รายงานถ้าสำเร็จ
typedef SaveErrorReportHandler = Future<String?> Function();

void showSaveErrorSnackBar(
  BuildContext context, {
  required Object error,
  SaveErrorContext? saveContext,
  SaveErrorReportHandler? onSendReport,
}) {
  if (!context.mounted) return;
  // หลังปิด dialog บันทึก element tree อาจยังไม่ stable — รอเฟรมถัดไป
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _presentSaveErrorSnackBar(
      context,
      error: error,
      saveContext: saveContext,
      onSendReport: onSendReport,
    );
  });
}

int _saveErrorPresentSeq = 0;

void _presentSaveErrorSnackBar(
  BuildContext context, {
  required Object error,
  SaveErrorContext? saveContext,
  SaveErrorReportHandler? onSendReport,
}) {
  if (!context.mounted) return;

  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  messenger.showSnackBar(
    SnackBar(
      content: Text(
        formatSaveErrorMessage(error, context: saveContext),
        style: GoogleFonts.kanit(fontSize: 14, height: 1.35),
      ),
      duration: const Duration(seconds: 8),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
    ),
  );

  if (onSendReport == null) return;

  final session = ++_saveErrorPresentSeq;
  _runAutoSaveErrorReport(
    context: context,
    session: session,
    onSendReport: onSendReport,
  );
}

Future<void> _runAutoSaveErrorReport({
  required BuildContext context,
  required int session,
  required SaveErrorReportHandler onSendReport,
}) async {
  try {
    final id = await onSendReport();
    if (!context.mounted || session != _saveErrorPresentSeq) return;
    if (id != null && id.isNotEmpty) {
      await _showSaveErrorReportSentDialog(context);
    }
  } catch (_) {
    // ส่งไม่สำเร็จ — ไม่รบกวนผู้ใช้ด้วย popup (มี SnackBar ข้อผิดพลาดอยู่แล้ว)
  }
}

Future<void> _showSaveErrorReportSentDialog(BuildContext context) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    useRootNavigator: true,
    builder: (dialogCtx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle_rounded,
            color: Colors.green.shade700,
            size: 30,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'ส่งรายงาน error สำเร็จ',
              style: GoogleFonts.kanit(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
      content: Text(
        'ระบบได้ส่งรายงานข้อผิดพลาดไปยังผู้ดูแลแล้ว',
        style: GoogleFonts.kanit(fontSize: 15, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogCtx).pop(),
          child: Text(
            'ตกลง',
            style: GoogleFonts.kanit(
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
        ),
      ],
    ),
  );
}

/// โยนข้อผิดพลาดพร้อมบริบท (ใช้ภายใน callback ของ [_runSaveWithPopups])
Never failSave(
  String message, {
  required SaveErrorContext context,
  String? field,
}) {
  throw UserSaveException(message, context: context, field: field);
}

/// ข้อมูลบริบทสำหรับส่งรายงานไปเว็บ (`mobile_error_reports`)
class SaveErrorReportFields {
  const SaveErrorReportFields({
    this.page,
    this.action,
    this.button,
    this.field,
    required this.cause,
  });

  final String? page;
  final String? action;
  final String? button;
  final String? field;
  final String cause;
}

SaveErrorReportFields extractSaveErrorReportFields(
  Object error, {
  SaveErrorContext? context,
}) {
  final ctx = error is UserSaveException ? error.context : context;
  final field = error is UserSaveException ? error.field : null;
  final cause = error is UserSaveException
      ? error.message
      : error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
  return SaveErrorReportFields(
    page: ctx?.page,
    action: ctx?.action,
    button: ctx?.button,
    field: field,
    cause: cause,
  );
}

String buildSaveErrorReportSummary(SaveErrorReportFields f) {
  final parts = <String>['บันทึกไม่สำเร็จ'];
  if (f.page != null && f.page!.trim().isNotEmpty) {
    parts.add(f.page!.trim());
  }
  if (f.cause.trim().isNotEmpty) parts.add(f.cause.trim());
  return parts.join(' · ');
}
