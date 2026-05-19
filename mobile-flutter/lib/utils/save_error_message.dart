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

/// ส่งรายงานเมื่อผู้ใช้กดปุ่ม «ส่งข้อมูล» — คืน `id` รายงานถ้าสำเร็จ
typedef SaveErrorReportHandler = Future<String?> Function();

void showSaveErrorSnackBar(
  BuildContext context, {
  required Object error,
  SaveErrorContext? saveContext,
  SaveErrorReportHandler? onSendReport,
}) {
  _SaveErrorEdgeUi.dismiss();

  final messenger = ScaffoldMessenger.of(context);
  final hasEdgeSend = onSendReport != null;
  final controller = messenger.showSnackBar(
    SnackBar(
      content: Text(
        formatSaveErrorMessage(error, context: saveContext),
        style: GoogleFonts.kanit(fontSize: 14, height: 1.35),
      ),
      duration: const Duration(seconds: 8),
      behavior: SnackBarBehavior.floating,
      margin: hasEdgeSend
          ? const EdgeInsets.fromLTRB(12, 0, 72, 16)
          : null,
    ),
  );

  if (hasEdgeSend) {
    _SaveErrorEdgeUi.show(
      context: context,
      onSendReport: onSendReport,
      onSent: () {
        if (!context.mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'ส่งข้อมูลแล้ว',
              style: GoogleFonts.kanit(fontWeight: FontWeight.w600),
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(12, 0, 72, 16),
          ),
        );
      },
      onFailed: (e) {
        if (!context.mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'ส่งข้อมูลไม่สำเร็จ',
              style: GoogleFonts.kanit(fontWeight: FontWeight.w600),
            ),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(12, 0, 72, 16),
          ),
        );
      },
    );
    controller.closed.then((_) => _SaveErrorEdgeUi.dismiss());
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

class _SaveErrorEdgeUi {
  static OverlayEntry? _entry;

  static void dismiss() {
    _entry?.remove();
    _entry = null;
  }

  static void show({
    required BuildContext context,
    required SaveErrorReportHandler onSendReport,
    required VoidCallback onSent,
    required void Function(Object error) onFailed,
  }) {
    dismiss();
    final overlay = Overlay.of(context, rootOverlay: true);
    _entry = OverlayEntry(
      builder: (ctx) => _SaveErrorEdgeSendButton(
        onSendReport: onSendReport,
        onSent: () {
          onSent();
          dismiss();
        },
        onFailed: onFailed,
      ),
    );
    overlay.insert(_entry!);
  }
}

class _SaveErrorEdgeSendButton extends StatefulWidget {
  const _SaveErrorEdgeSendButton({
    required this.onSendReport,
    required this.onSent,
    required this.onFailed,
  });

  final SaveErrorReportHandler onSendReport;
  final VoidCallback onSent;
  final void Function(Object error) onFailed;

  @override
  State<_SaveErrorEdgeSendButton> createState() =>
      _SaveErrorEdgeSendButtonState();
}

class _SaveErrorEdgeSendButtonState extends State<_SaveErrorEdgeSendButton> {
  bool _sending = false;
  bool _sent = false;

  Future<void> _handleTap() async {
    if (_sending || _sent) return;
    setState(() => _sending = true);
    try {
      final id = await widget.onSendReport();
      if (!mounted) return;
      if (id != null && id.isNotEmpty) {
        setState(() {
          _sending = false;
          _sent = true;
        });
        widget.onSent();
      } else {
        setState(() => _sending = false);
        widget.onFailed(Exception('empty report id'));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      widget.onFailed(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewPaddingOf(context).bottom + 20;
    final label = _sent
        ? 'ส่งแล้ว'
        : _sending
        ? 'กำลังส่ง'
        : 'ส่งข้อมูล';
    final bg = _sent ? const Color(0xFF2E7D32) : const Color(0xFFC62828);

    return Positioned(
      right: 0,
      bottom: bottom,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: (_sending || _sent) ? null : _handleTap,
          borderRadius: const BorderRadius.horizontal(
            left: Radius.circular(18),
          ),
          child: Ink(
            decoration: BoxDecoration(
              color: bg,
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(18),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 12,
                  offset: const Offset(-2, 3),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _sending
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          _sent
                              ? Icons.check_rounded
                              : Icons.cloud_upload_outlined,
                          color: Colors.white,
                          size: 24,
                        ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: GoogleFonts.kanit(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
