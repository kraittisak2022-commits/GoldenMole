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

void showSaveErrorSnackBar(
  BuildContext context, {
  required Object error,
  SaveErrorContext? saveContext,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        formatSaveErrorMessage(error, context: saveContext),
        style: GoogleFonts.kanit(fontSize: 14, height: 1.35),
      ),
      duration: const Duration(seconds: 8),
      behavior: SnackBarBehavior.floating,
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
