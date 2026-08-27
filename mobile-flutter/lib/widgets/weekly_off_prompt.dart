import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/weekly_off_calendar_store.dart';

/// Popup ถามวันหยุดของสัปดาห์ — แสดงครั้งแรกที่เปิดหน้าหลักในแต่ละสัปดาห์
class WeeklyOffPrompt {
  WeeklyOffPrompt._();

  static bool _showing = false;

  /// ถ้าสัปดาห์นี้ยังไม่ตอบ จะโชว์ dialog เลือกวันหยุด
  static Future<void> showIfNeeded(
    BuildContext context, {
    SupabaseClient? client,
    DateTime? forDay,
  }) async {
    if (_showing) return;
    final day = forDay ?? DateTime.now();
    final store = WeeklyOffCalendarStore();
    final supabase = client ?? Supabase.instance.client;
    if (await store.isWeekAnswered(day, client: supabase)) return;
    if (!context.mounted) return;

    _showing = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _WeeklyOffPromptDialog(
          store: store,
          client: supabase,
          anyDayInWeek: day,
        ),
      );
    } finally {
      _showing = false;
    }
  }
}

class _WeeklyOffPromptDialog extends StatefulWidget {
  const _WeeklyOffPromptDialog({
    required this.store,
    required this.client,
    required this.anyDayInWeek,
  });

  final WeeklyOffCalendarStore store;
  final SupabaseClient client;
  final DateTime anyDayInWeek;

  @override
  State<_WeeklyOffPromptDialog> createState() => _WeeklyOffPromptDialogState();
}

class _WeeklyOffPromptDialogState extends State<_WeeklyOffPromptDialog> {
  static const _brandTeal = Color(0xFF0D98A5);

  late int _selected;
  late final TextEditingController _reasonCtrl;
  bool _saving = false;
  String? _weekRangeLabel;

  @override
  void initState() {
    super.initState();
    _selected = WeeklyOffCalendarStore.defaultOffWeekday;
    _reasonCtrl = TextEditingController();
    _weekRangeLabel = _formatWeekRange(widget.anyDayInWeek);
    unawaited(_hydrate());
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _hydrate() async {
    final data = await widget.store.load(client: widget.client);
    if (!mounted) return;
    final monday = WeeklyOffCalendarStore.mondayKeyOf(widget.anyDayInWeek);
    final wd =
        data.weekdayByMonday[monday] ?? WeeklyOffCalendarStore.defaultOffWeekday;
    final reason = data.moveReasonByMonday[monday] ?? '';
    setState(() {
      _selected = wd;
      if (reason.isNotEmpty) _reasonCtrl.text = reason;
    });
  }

  String _formatWeekRange(DateTime d) {
    final local = DateTime(d.year, d.month, d.day);
    final monday = local.subtract(Duration(days: local.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));
    String fmt(DateTime x) =>
        '${x.day.toString().padLeft(2, '0')}/${x.month.toString().padLeft(2, '0')}/${x.year + 543}';
    return '${fmt(monday)} – ${fmt(sunday)}';
  }

  String _thaiWeekday(int weekday) {
    const names = [
      'วันจันทร์',
      'วันอังคาร',
      'วันพุธ',
      'วันพฤหัสบดี',
      'วันศุกร์',
      'วันเสาร์',
      'วันอาทิตย์',
    ];
    return names[weekday.clamp(1, 7) - 1];
  }

  Future<void> _confirm() async {
    if (_saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final needsReason =
          _selected != WeeklyOffCalendarStore.defaultOffWeekday;
      await widget.store.setWeekOffWeekday(
        widget.anyDayInWeek,
        _selected,
        moveReason: needsReason ? _reasonCtrl.text : null,
        requireReason: false,
        client: widget.client,
      );
      await widget.store.markWeekAnswered(
        widget.anyDayInWeek,
        client: widget.client,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            _selected == WeeklyOffCalendarStore.defaultOffWeekday
                ? 'สัปดาห์นี้หยุดวันพฤหัสบดีตามมาตรฐาน'
                : 'สัปดาห์นี้หยุด${_thaiWeekday(_selected)}',
            style: GoogleFonts.kanit(),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger?.showSnackBar(
        SnackBar(
          content: Text('$e', style: GoogleFonts.kanit()),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _later() {
    if (_saving) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final needsReason =
        _selected != WeeklyOffCalendarStore.defaultOffWeekday;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'สัปดาห์นี้หยุดวันไหน?',
            style: GoogleFonts.kanit(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1A2433),
            ),
          ),
          if (_weekRangeLabel != null) ...[
            const SizedBox(height: 4),
            Text(
              _weekRangeLabel!,
              style: GoogleFonts.kanit(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var wd = 1; wd <= 7; wd++)
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: Icon(
                    _selected == wd
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: _selected == wd ? _brandTeal : Colors.black38,
                  ),
                  title: Text(
                    _thaiWeekday(wd),
                    style: GoogleFonts.kanit(fontWeight: FontWeight.w600),
                  ),
                  subtitle: wd == WeeklyOffCalendarStore.defaultOffWeekday
                      ? Text(
                          'ค่าเริ่มต้น',
                          style: GoogleFonts.kanit(
                            fontSize: 11.5,
                            color: Colors.black45,
                          ),
                        )
                      : null,
                  onTap: _saving
                      ? null
                      : () => setState(() => _selected = wd),
                ),
              if (needsReason) ...[
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: TextField(
                    controller: _reasonCtrl,
                    enabled: !_saving,
                    minLines: 2,
                    maxLines: 3,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: 'เหตุผล (ถ้ามี)',
                      hintText: 'เช่น งานเร่งด่วนวันพฤหัสบดี',
                      labelStyle: GoogleFonts.kanit(),
                      hintStyle: GoogleFonts.kanit(fontSize: 13),
                      border: const OutlineInputBorder(),
                    ),
                    style: GoogleFonts.kanit(fontSize: 15),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : _later,
          child: Text(
            'ไว้ก่อน',
            style: GoogleFonts.kanit(fontWeight: FontWeight.w600),
          ),
        ),
        FilledButton(
          onPressed: _saving ? null : _confirm,
          style: FilledButton.styleFrom(backgroundColor: _brandTeal),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  'ยืนยัน',
                  style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
                ),
        ),
      ],
    );
  }
}
