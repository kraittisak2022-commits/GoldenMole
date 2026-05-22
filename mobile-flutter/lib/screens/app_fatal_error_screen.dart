import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin_user.dart';
import '../services/mobile_error_report_service.dart';
import '../services/session_service.dart';
import '../utils/mobile_error_report_submit_guard.dart';
import '../utils/mobile_error_screen_tracker.dart';
import '../widgets/mobile_error_report_send_dialog.dart';

/// หน้าเมื่อเกิด error ร้ายแรงที่ไม่ได้จับ — ให้ส่งรายงานเข้าเว็บ (ตาราง mobile_error_reports)
class AppFatalErrorScreen extends StatefulWidget {
  const AppFatalErrorScreen({
    super.key,
    required this.error,
    this.stackTrace,
    required this.source,
  });

  final Object error;
  final StackTrace? stackTrace;
  /// เช่น uncaught_flutter | uncaught_zone | bootstrap
  final String source;

  @override
  State<AppFatalErrorScreen> createState() => _AppFatalErrorScreenState();
}

class _AppFatalErrorScreenState extends State<AppFatalErrorScreen> {
  final _note = TextEditingController();
  bool _sending = false;
  String? _sendOk;
  String? _sendErr;
  AdminUser? _reporter;

  @override
  void initState() {
    super.initState();
    SessionService().getSavedAdmin().then((a) {
      if (mounted) setState(() => _reporter = a);
    });
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String get _errorPreview {
    final t = widget.error.toString().trim();
    if (t.length <= 180) return t;
    return '${t.substring(0, 180)}…';
  }

  Future<void> _openSendPopup() async {
    final confirmed = await showMobileErrorReportSendDialog(
      context,
      summary: _errorPreview,
      detail: _note.text.trim(),
      confirmLabel: 'ยืนยันส่งข้อมูล',
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _sending = true;
      _sendOk = null;
      _sendErr = null;
    });
    try {
      final svc = MobileErrorReportService(Supabase.instance.client);
      final id = await svc.submit(
        error: widget.error,
        stackTrace: widget.stackTrace,
        source: widget.source,
        userNote: _note.text,
        reporter: _reporter,
        screenPage: MobileErrorScreenTracker.page,
        screenAction: MobileErrorScreenTracker.module,
      );
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sendOk = 'ส่งข้อมูลแล้ว (รหัส $id) ทีมดูได้ที่เว็บ ตั้งค่า > แอป Android';
      });
    } on MobileErrorReportRateLimitException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sendErr = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sendErr = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F5),
      appBar: AppBar(
        title: Text(
          'เกิดข้อผิดพลาดในแอป',
          style: GoogleFonts.kanit(fontWeight: FontWeight.w800),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Icon(Icons.bug_report_outlined, size: 56, color: Colors.red.shade700),
          const SizedBox(height: 12),
          Text(
            'แอปหยุดทำงานผิดปกติ คุณสามารถส่งรายละเอียดให้ผู้ดูแลระบบผ่านเว็บได้',
            style: GoogleFonts.kanit(
              fontSize: 15,
              height: 1.4,
              color: const Color(0xFF37474F),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'ข้อความจากระบบ',
            style: GoogleFonts.kanit(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 6),
          SelectableText(
            widget.error.toString(),
            style: GoogleFonts.kanit(
              fontSize: 13,
              color: const Color(0xFFB71C1C),
            ),
          ),
          if (widget.stackTrace != null) ...[
            const SizedBox(height: 12),
            Text(
              'Stack trace',
              style: GoogleFonts.kanit(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 6),
            SelectableText(
              widget.stackTrace.toString(),
              style: GoogleFonts.kanit(fontSize: 11, color: Colors.black54),
            ),
          ],
          const SizedBox(height: 20),
          TextField(
            controller: _note,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'อธิบายเพิ่ม (ไม่บังคับ)',
              hintText: 'เช่น กดปุ่มไหน อยู่หน้าไหน',
              labelStyle: GoogleFonts.kanit(),
              hintStyle: GoogleFonts.kanit(fontSize: 13),
            ),
            style: GoogleFonts.kanit(),
          ),
          const SizedBox(height: 20),
          if (_sendErr != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'ส่งไม่สำเร็จ: $_sendErr',
                style: GoogleFonts.kanit(color: Colors.red.shade800, fontSize: 13),
              ),
            ),
          if (_sendOk != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _sendOk!,
                style: GoogleFonts.kanit(
                  color: Colors.green.shade800,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _sending ? null : _openSendPopup,
              icon: _sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.upload_outlined),
              label: Text(
                _sending ? 'กำลังส่ง...' : 'ส่งข้อมูล',
                style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _sending ? null : () => Navigator.of(context).maybePop(),
              child: Text('ปิดหน้านี้', style: GoogleFonts.kanit()),
            ),
          ),
        ],
      ),
    );
  }
}
