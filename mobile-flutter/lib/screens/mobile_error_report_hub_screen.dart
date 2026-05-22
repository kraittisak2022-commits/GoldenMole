import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/admin_user.dart';
import '../services/mobile_error_report_service.dart';
import '../utils/mobile_error_report_submit_guard.dart';
import '../widgets/mobile_error_report_send_dialog.dart';

/// ตั้งค่า > แอป Android
class MobileErrorReportHubScreen extends StatefulWidget {
  const MobileErrorReportHubScreen({
    super.key,
    required this.currentAdmin,
  });

  final AdminUser currentAdmin;

  @override
  State<MobileErrorReportHubScreen> createState() =>
      _MobileErrorReportHubScreenState();
}

class _MobileErrorReportHubScreenState extends State<MobileErrorReportHubScreen> {
  late final MobileErrorReportService _svc;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  String? _err;
  final _manualTitle = TextEditingController();
  final _manualDetail = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _svc = MobileErrorReportService(Supabase.instance.client);
    _reload();
  }

  @override
  void dispose() {
    _manualTitle.dispose();
    _manualDetail.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final list = await _svc.listRecent(limit: 100);
      if (!mounted) return;
      setState(() {
        _rows = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _err = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _markRead(String id) async {
    try {
      await Supabase.instance.client.from('mobile_error_reports').update({
        'reviewed': true,
        'reviewed_at': DateTime.now().toUtc().toIso8601String(),
        'reviewed_by': widget.currentAdmin.username,
      }).eq('id', id);
      await _reload();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('อัปเดตไม่สำเร็จ', style: GoogleFonts.kanit())),
      );
    }
  }

  Future<void> _openSendPopup() async {
    final title = _manualTitle.text.trim();
    final body = _manualDetail.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('กรุณากรอกหัวข้อปัญหา', style: GoogleFonts.kanit()),
        ),
      );
      return;
    }

    final confirmed = await showMobileErrorReportSendDialog(
      context,
      summary: title,
      detail: body.isEmpty ? '(ไม่มีรายละเอียดเพิ่ม)' : body,
    );
    if (!confirmed || !mounted) return;

    setState(() => _submitting = true);
    try {
      final id = await _svc.submit(
        error: title,
        stackTrace: null,
        source: 'manual_settings',
        userNote: body,
        reporter: widget.currentAdmin,
      );
      if (!mounted) return;
      _manualTitle.clear();
      _manualDetail.clear();
      await showMobileErrorReportSentDialog(context, reportId: id);
      await _reload();
    } on MobileErrorReportRateLimitException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message, style: GoogleFonts.kanit())),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e', style: GoogleFonts.kanit())),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _fmt(dynamic v) {
    if (v == null) return '—';
    return '$v';
  }

  String? _contextLine(Map<String, dynamic> r) {
    final page = '${r['screen_page'] ?? ''}'.trim();
    final action = '${r['screen_action'] ?? ''}'.trim();
    final button = '${r['screen_button'] ?? ''}'.trim();
    final field = '${r['error_field'] ?? ''}'.trim();
    if (page.isEmpty && action.isEmpty && button.isEmpty && field.isEmpty) {
      return null;
    }
    final parts = <String>[];
    if (page.isNotEmpty) parts.add('หน้า: $page');
    if (action.isNotEmpty) parts.add('รายการ: $action');
    if (button.isNotEmpty) parts.add('ปุ่ม: $button');
    if (field.isNotEmpty) parts.add('จุด: $field');
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FA),
      appBar: AppBar(
        title: Text(
          'แอป Android · รายงานปัญหา',
          style: GoogleFonts.kanit(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'รีเฟรช',
            onPressed: _loading ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Text(
              'รายงานจากแอปจะถูกเก็บในระบบเว็บ — ผู้ดูแลเปิดที่ตั้งค่า > แอป Android เพื่อติดตามและทำเครื่องหมายอ่านแล้ว',
              style: GoogleFonts.kanit(
                fontSize: 13,
                color: Colors.black54,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'รายงานด้วยตนเอง',
              style: GoogleFonts.kanit(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _manualTitle,
              decoration: InputDecoration(
                labelText: 'หัวข้อ / สรุปปัญหา',
                labelStyle: GoogleFonts.kanit(),
              ),
              style: GoogleFonts.kanit(),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _manualDetail,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'รายละเอียด (ไม่บังคับ)',
                labelStyle: GoogleFonts.kanit(),
              ),
              style: GoogleFonts.kanit(fontSize: 14),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _submitting ? null : _openSendPopup,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.upload_outlined),
                label: Text(
                  _submitting ? 'กำลังส่ง...' : 'ส่งข้อมูล',
                  style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'กดส่งข้อมูลเพื่อเปิดหน้าต่างยืนยันก่อนบันทึก — ระบบจำกัดการส่งซ้ำภายใน 45 วินาที',
                style: GoogleFonts.kanit(fontSize: 11, color: Colors.black45),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    'รายงานล่าสุด',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.kanit(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (_rows.where((r) => r['reviewed'] != true).isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'ยังไม่อ่าน ${_rows.where((r) => r['reviewed'] != true).length}',
                      style: GoogleFonts.kanit(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            else if (_err != null)
              Text(_err!, style: GoogleFonts.kanit(color: Colors.red))
            else if (_rows.isEmpty)
              Text(
                'ยังไม่มีรายงาน',
                style: GoogleFonts.kanit(color: Colors.black45),
              )
            else
              ..._rows.map((r) {
                final id = '${r['id'] ?? ''}';
                final reviewed = r['reviewed'] == true;
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                _fmt(r['error_summary']),
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.kanit(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            if (!reviewed)
                              TextButton(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () => _markRead(id),
                                child: Text(
                                  'อ่านแล้ว',
                                  style: GoogleFonts.kanit(fontSize: 12),
                                ),
                              ),
                          ],
                        ),
                        if (_contextLine(r) != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            _contextLine(r)!,
                            style: GoogleFonts.kanit(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF1565C0),
                              height: 1.35,
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          '${_fmt(r['created_at'])} · ${_fmt(r['source'])} · v${_fmt(r['app_version'])}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.kanit(
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                        ),
                        if ((r['user_note'] ?? '').toString().trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'หมายเหตุ: ${r['user_note']}',
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.kanit(fontSize: 12),
                            ),
                          ),
                        if ((r['device_info'] ?? '').toString().trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'เครื่อง: ${r['device_info']}',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.kanit(
                                fontSize: 11,
                                color: Colors.black45,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
