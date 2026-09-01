import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../widgets/mobile_error_report_send_dialog.dart';
import '../widgets/save_operation_feedback.dart';
import 'mobile_error_report_submit_guard.dart';

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

String buildSaveErrorPopupSubtitle(SaveErrorReportFields fields) {
  final parts = <String>[];
  if (fields.field != null && fields.field!.trim().isNotEmpty) {
    parts.add('จุดที่ผิด: ${fields.field!.trim()}');
  }
  if (fields.page != null && fields.page!.trim().isNotEmpty) {
    parts.add('หน้า: ${fields.page!.trim()}');
  }
  if (fields.action != null && fields.action!.trim().isNotEmpty) {
    parts.add(fields.action!.trim());
  }
  return parts.join(' · ');
}

void showSaveErrorSnackBar(
  BuildContext context, {
  required Object error,
  SaveErrorContext? saveContext,
  SaveErrorReportHandler? onSendReport,
}) {
  if (!context.mounted) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(
      _presentSaveErrorPopup(
        context,
        error: error,
        saveContext: saveContext,
        onSendReport: onSendReport,
      ),
    );
  });
}

Future<void> _presentSaveErrorPopup(
  BuildContext context, {
  required Object error,
  SaveErrorContext? saveContext,
  SaveErrorReportHandler? onSendReport,
}) async {
  if (!context.mounted) return;

  final fields = extractSaveErrorReportFields(error, context: saveContext);
  final previewSummary = buildSaveErrorReportSummary(fields);

  await SaveOperationFeedback.showError(
    context: context,
    title: 'บันทึกไม่สำเร็จ',
    message: fields.cause,
    subtitle: buildSaveErrorPopupSubtitle(fields),
    onSendReport: onSendReport == null
        ? null
        : () async {
            await _promptAndSendSaveErrorReport(
              context,
              previewSummary: previewSummary,
              previewDetail: fields.cause,
              onSendReport: onSendReport,
            );
          },
  );

  if (!context.mounted || onSendReport == null) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  await _autoSendSaveErrorReport(
    context,
    messenger: messenger,
    baseMessage: formatSaveErrorMessage(error, context: saveContext),
    onSendReport: onSendReport,
  );
}

Future<void> _promptAndSendSaveErrorReport(
  BuildContext context, {
  required String previewSummary,
  required String previewDetail,
  required SaveErrorReportHandler onSendReport,
}) async {
  if (!context.mounted) return;
  final confirmed = await showMobileErrorReportSendDialog(
    context,
    summary: previewSummary,
    detail: previewDetail,
  );
  if (!confirmed || !context.mounted) return;

  try {
    final id = await onSendReport();
    if (!context.mounted) return;
    if (id != null && id.isNotEmpty) {
      await showMobileErrorReportSentDialog(context, reportId: id);
    }
  } on MobileErrorReportRateLimitException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(e.message, style: GoogleFonts.kanit()),
        behavior: SnackBarBehavior.floating,
      ),
    );
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('ส่งข้อมูลไม่สำเร็จ', style: GoogleFonts.kanit()),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

Future<void> _autoSendSaveErrorReport(
  BuildContext context, {
  required ScaffoldMessengerState messenger,
  required String baseMessage,
  required SaveErrorReportHandler onSendReport,
}) async {
  try {
    final id = await onSendReport();
    if (!context.mounted) return;
    if (id != null && id.isNotEmpty) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '$baseMessage\n\nส่งรายงานเข้าเว็บอัตโนมัติแล้ว (รหัส $id)',
            style: GoogleFonts.kanit(fontSize: 14, height: 1.35),
          ),
          duration: const Duration(seconds: 12),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        ),
      );
    }
  } on MobileErrorReportRateLimitException catch (e) {
    if (!context.mounted) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '$baseMessage\n\n${e.message}',
          style: GoogleFonts.kanit(fontSize: 14, height: 1.35),
        ),
        duration: const Duration(seconds: 10),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      ),
    );
  } catch (_) {
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'ส่งรายงานอัตโนมัติไม่สำเร็จ',
          style: GoogleFonts.kanit(),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
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
