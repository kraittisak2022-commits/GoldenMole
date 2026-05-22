import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Popup ยืนยันก่อนส่งรายงานไปเว็บ — คืน `true` เมื่อผู้ใช้กดยืนยัน
Future<bool> showMobileErrorReportSendDialog(
  BuildContext context, {
  required String summary,
  String detail = '',
  String confirmLabel = 'ยืนยันส่งข้อมูล',
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogCtx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.upload_outlined, color: Colors.blue.shade700, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'ส่งข้อมูล',
              style: GoogleFonts.kanit(
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'ตรวจสอบก่อนส่ง — ระบบจะบันทึกไปยังผู้ดูแลที่เว็บ (ตั้งค่า > แอป Android)',
              style: GoogleFonts.kanit(
                fontSize: 13,
                height: 1.4,
                color: Colors.black54,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F8FC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text(
                summary.trim().isEmpty ? '(ไม่มีหัวข้อ)' : summary.trim(),
                style: GoogleFonts.kanit(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
            ),
            if (detail.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                detail.trim(),
                style: GoogleFonts.kanit(fontSize: 12, height: 1.35),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogCtx).pop(false),
          child: Text('ยกเลิก', style: GoogleFonts.kanit(fontWeight: FontWeight.w600)),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogCtx).pop(true),
          child: Text(
            confirmLabel,
            style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
  return result == true;
}

/// แจ้งส่งสำเร็จหลังยืนยัน
Future<void> showMobileErrorReportSentDialog(
  BuildContext context, {
  String? reportId,
}) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(Icons.check_circle_rounded, color: Colors.green.shade700, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'ส่งข้อมูลแล้ว',
              style: GoogleFonts.kanit(fontWeight: FontWeight.w800, fontSize: 18),
            ),
          ),
        ],
      ),
      content: Text(
        reportId != null && reportId.isNotEmpty
            ? 'บันทึกรายงานแล้ว (รหัส $reportId)\nทีมดูได้ที่เว็บ ตั้งค่า > แอป Android'
            : 'บันทึกรายงานแล้ว — ทีมดูได้ที่เว็บ ตั้งค่า > แอป Android',
        style: GoogleFonts.kanit(fontSize: 14, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogCtx).pop(),
          child: Text('ตกลง', style: GoogleFonts.kanit(fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
}
