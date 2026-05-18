import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_transaction.dart';
import '../models/employee.dart';
import '../services/employee_service.dart';
import '../services/transaction_service.dart';
import '../services/weekly_off_calendar_store.dart';
import '../utils/daily_module_transactions.dart';
import '../utils/thai_holidays.dart';
import '../widgets/page_loading_view.dart';

String _stripRecorderSuffix(String raw) =>
    raw.replaceAll(RegExp(r'\s*\(ผู้กรอก:[^)]+\)\s*$'), '').trim();

String _dailyEventTypeIcon(String? type) {
  switch ((type ?? '').trim().toLowerCase()) {
    case 'warning':
      return '⚠️';
    case 'problem':
      return '🚨';
    case 'success':
      return '✅';
    case 'complaint':
      return '📢';
    case 'request':
      return '📋';
    default:
      return 'ℹ️';
  }
}

String _formatDailyEventLine(AppTransaction t) {
  final desc = _stripRecorderSuffix(t.description);
  if (desc.isEmpty) return 'เหตุการณ์';
  final icon = _dailyEventTypeIcon(t.eventType);
  final pri = (t.eventPriority ?? '').trim().toLowerCase();
  final urgent = pri == 'high' ? ' [ด่วน]' : '';
  return '$icon $desc$urgent';
}

bool _isDailyEventTransaction(AppTransaction t) {
  if (t.category != 'DailyLog') return false;
  return (t.subCategory ?? '').trim() == 'Event';
}

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({
    super.key,
    required this.transactionService,
    required this.employeeService,
  });

  final TransactionService transactionService;
  final EmployeeService employeeService;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _monthCursor = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    1,
  );
  DateTime _selectedDate = DateTime.now();
  late Future<_CalendarPayload> _future;
  bool _savingEntry = false;

  final TextEditingController _eventTitleController = TextEditingController();
  final TextEditingController _eventTimeController = TextEditingController();
  final TextEditingController _eventNoteController = TextEditingController();
  final Set<String> _leaveEmpIds = {};
  String _entryMode = 'Holiday';
  String _leaveType = 'Leave';

  final WeeklyOffCalendarStore _weeklyOffStore = WeeklyOffCalendarStore();

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _eventTitleController.dispose();
    _eventTimeController.dispose();
    _eventNoteController.dispose();
    super.dispose();
  }

  Future<_CalendarPayload> _load({bool forceRefresh = false}) async {
    final transactions = await widget.transactionService.fetchTransactions(
      forceRefresh: forceRefresh,
    );
    final employees = await widget.employeeService.fetchEmployees(
      forceRefresh: forceRefresh,
    );
    final weeklyOff = await _weeklyOffStore.load(
      client: Supabase.instance.client,
    );
    return _CalendarPayload(
      transactions: transactions,
      employees: employees,
      weeklyOffByMonday: weeklyOff.weekdayByMonday,
      weeklyOffMoveReasonByMonday: weeklyOff.moveReasonByMonday,
    );
  }

  void _reload() {
    setState(() {
      _future = _load(forceRefresh: true);
    });
  }

  /// Scrollable body for modal bottom sheets — uses parent [LayoutBuilder] height
  /// (drag handle / safe area) so content does not overflow by a few pixels.
  Widget _calendarBottomSheetBody({
    required BuildContext context,
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(16, 4, 16, 0),
    double bottomExtra = 24,
  }) {
    final media = MediaQuery.of(context);
    final resolvedPad = padding.resolve(Directionality.of(context));
    final scrollPad = EdgeInsets.fromLTRB(
      resolvedPad.left,
      resolvedPad.top,
      resolvedPad.right,
      resolvedPad.bottom + media.padding.bottom + bottomExtra,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        var maxH = constraints.maxHeight;
        if (!maxH.isFinite || maxH <= 0) {
          maxH = media.size.height * 0.85;
        }
        const chromeSlack = 12.0;
        maxH = (maxH - chromeSlack).clamp(80.0, media.size.height);

        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: SingleChildScrollView(
            padding: scrollPad,
            child: child,
          ),
        );
      },
    );
  }

  static final _compactSegmentedStyle = SegmentedButton.styleFrom(
    visualDensity: VisualDensity.compact,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  );

  String _ymd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  Future<void> _saveCalendarOrLeaveEntry(_CalendarPayload data) async {
    if (_savingEntry) return;
    setState(() => _savingEntry = true);
    try {
      final date = _ymd(_selectedDate);
      if (_entryMode == 'Leave') {
        if (_leaveEmpIds.isEmpty) {
          throw Exception('กรุณาเลือกพนักงานอย่างน้อย 1 คน');
        }
        final tx = AppTransaction(
          id: 'leave_${DateTime.now().millisecondsSinceEpoch}',
          date: date,
          type: 'Expense',
          category: 'Labor',
          subCategory: 'Leave',
          laborStatus: _leaveType,
          employeeIds: _leaveEmpIds.toList(),
          description: _eventTitleController.text.trim().isEmpty
              ? 'ลางาน'
              : _eventTitleController.text.trim(),
          amount: 0,
          note: _eventNoteController.text.trim(),
        );
        await widget.transactionService.upsertTransaction(tx);
      } else {
        final title = _eventTitleController.text.trim();
        if (title.isEmpty) {
          throw Exception('กรุณากรอกหัวข้อวันหยุด/กิจกรรม');
        }
        final tx = AppTransaction(
          id: 'cal_${DateTime.now().millisecondsSinceEpoch}',
          date: date,
          type: 'Expense',
          category: 'Calendar',
          subCategory: _entryMode,
          description: title,
          amount: 0,
          eventTime: _eventTimeController.text.trim(),
          note: _eventNoteController.text.trim(),
        );
        await widget.transactionService.upsertTransaction(tx);
      }
      if (!mounted) return;
      Navigator.of(context).maybePop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _entryMode == 'Leave'
                ? 'บันทึกลางานสำเร็จ (ซิงก์ไปเว็บแดชบอร์ดแล้ว)'
                : 'บันทึกปฏิทินสำเร็จ (ซิงก์ไปเว็บแดชบอร์ดแล้ว)',
            style: GoogleFonts.kanit(),
          ),
        ),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString(), style: GoogleFonts.kanit())),
      );
    } finally {
      if (mounted) setState(() => _savingEntry = false);
    }
  }

  void _pickDay(_CalendarDay day) {
    final p = day.dateStr.split('-');
    if (p.length != 3) return;
    final selected = DateTime(
      int.parse(p[0]),
      int.parse(p[1]),
      int.parse(p[2]),
    );
    setState(() => _selectedDate = selected);
    _openDayDetails(day);
  }

  void _openDayDetails(_CalendarDay day) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF4F6F9),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return _calendarBottomSheetBody(
          context: context,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _dayDetailHeader(day),
              const SizedBox(height: 12),
              if (day.thaiPublicHolidayNames.isNotEmpty)
                _daySectionCard(
                  icon: Icons.star_outline_rounded,
                  title: 'นักขัตฤกษ์ (ประมาณการ)',
                  subtitle: 'แจ้งเตือนทางปฏิทิน — ไม่ได้หมายว่าองค์กรหยุดครบถ้วน',
                  color: const Color(0xFF5C7C9F),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final name in day.thaiPublicHolidayNames)
                        _dayBulletLine(name),
                    ],
                  ),
                ),
              if (day.weeklyOffLine != null ||
                  day.userHolidayDescriptions.isNotEmpty)
                _daySectionCard(
                  icon: Icons.event_busy_outlined,
                  title: 'วันหยุด / กิจกรรม',
                  color: const Color(0xFFE57373),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (day.weeklyOffLine != null)
                        _dayBulletLine(day.weeklyOffLine!),
                      if (day.weeklyOffMoveReason != null &&
                          day.weeklyOffMoveReason!.isNotEmpty)
                        _dayBulletLine(
                          'เลื่อนหยุด: ${day.weeklyOffMoveReason}',
                          muted: true,
                        ),
                      for (final desc in day.userHolidayDescriptions)
                        _dayBulletLine(desc),
                    ],
                  ),
                ),
              if (day.leaveDetails.isNotEmpty)
                _daySectionCard(
                  icon: Icons.person_off_outlined,
                  title: 'รายการลา (${day.leaveDetails.length})',
                  color: const Color(0xFFFFB74D),
                  child: Column(
                    children: [
                      for (var i = 0; i < day.leaveDetails.length; i++) ...[
                        if (i > 0)
                          const Divider(height: 20, color: Color(0xFFE8ECF0)),
                        _dayLeaveCard(day.leaveDetails[i]),
                      ],
                    ],
                  ),
                ),
              if (day.homeSandLines.isNotEmpty)
                _daySectionCard(
                  icon: Icons.waves_outlined,
                  title: 'ทรายที่ล้างที่บ้าน',
                  color: const Color(0xFF00897B),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final line in day.homeSandLines)
                        _dayBulletLine(line),
                    ],
                  ),
                ),
              if (day.dailyEventLines.isNotEmpty)
                _daySectionCard(
                  icon: Icons.flag_outlined,
                  title: 'เหตุการณ์ประจำวัน',
                  color: const Color(0xFFE65100),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final line in day.dailyEventLines)
                        _dayBulletLine(line),
                    ],
                  ),
                ),
              if (!day.hasAnyPlannerEntry)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  alignment: Alignment.center,
                  child: Column(
                    children: [
                      Icon(
                        Icons.event_available_outlined,
                        size: 40,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'ไม่มีรายการในวันนี้',
                        style: GoogleFonts.kanit(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await _showMoveWeeklyOffSheet();
                },
                icon: const Icon(Icons.swap_horiz_rounded),
                label: Text(
                  'ย้ายหยุดรายสัปดาห์',
                  style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  _openCreateEntrySheet();
                },
                icon: const Icon(Icons.add_circle_outline),
                label: Text('เพิ่มวันหยุด / ลางาน', style: GoogleFonts.kanit()),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _dayDetailHeader(_CalendarDay day) {
    final tags = day.allTags();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3E8EF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _thaiWeekdayLong(_selectedDate),
            style: GoogleFonts.kanit(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF64748B),
            ),
          ),
          Text(
            _formatDateThai(_selectedDate),
            style: GoogleFonts.kanit(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1A2A3C),
              height: 1.15,
            ),
          ),
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: tags
                  .map((t) => _CalendarTagChip(tag: t, compact: false))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _daySectionCard({
    required IconData icon,
    required String title,
    required Color color,
    required Widget child,
    String? subtitle,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8ECF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(15),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.kanit(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: color.withValues(alpha: 0.95),
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          style: GoogleFonts.kanit(
                            fontSize: 11,
                            color: Colors.black54,
                            height: 1.25,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _dayBulletLine(String text, {bool muted = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: muted ? Colors.black26 : const Color(0xFF90A4AE),
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.kanit(
                fontSize: 14,
                height: 1.35,
                color: muted ? Colors.black54 : const Color(0xFF37474F),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayLeaveCard(CalendarLeaveDetail item) {
    final reason = item.reason.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.headline,
          style: GoogleFonts.kanit(
            fontWeight: FontWeight.w800,
            fontSize: 14.5,
            color: const Color(0xFF1A2A3C),
            height: 1.3,
          ),
        ),
        if (item.spanNote != null) ...[
          const SizedBox(height: 2),
          Text(
            item.spanNote!,
            style: GoogleFonts.kanit(fontSize: 12, color: Colors.black54),
          ),
        ],
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFFFE082)),
          ),
          child: Text(
            reason.isNotEmpty ? reason : 'ยังไม่ระบุเหตุผล',
            style: GoogleFonts.kanit(
              fontSize: 13.5,
              height: 1.35,
              color: reason.isNotEmpty
                  ? const Color(0xFF5D4037)
                  : Colors.black45,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showMoveWeeklyOffSheet() async {
    final weeklyOff = await _weeklyOffStore.load(
      client: Supabase.instance.client,
    );
    final map = weeklyOff.weekdayByMonday;
    final reasonMap = weeklyOff.moveReasonByMonday;
    final mondayStr = WeeklyOffCalendarStore.mondayKeyOf(_selectedDate);
    final reasonCtrl = TextEditingController(
      text: reasonMap[mondayStr] ?? '',
    );

    if (!mounted) return;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        builder: (ctx) {
          var sel = map[mondayStr] ?? WeeklyOffCalendarStore.defaultOffWeekday;
          return StatefulBuilder(
            builder: (context, setSt) {
              final needsReason =
                  sel != WeeklyOffCalendarStore.defaultOffWeekday;
              return _calendarBottomSheetBody(
                context: context,
                bottomExtra: 16,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'ย้ายหยุดรายสัปดาห์',
                        style: GoogleFonts.kanit(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'ค่ามาตรฐาน: วันพุธของทุกสัปดาห์ • จันทร์แรกของสัปดาห์นี้: $mondayStr',
                        style: GoogleFonts.kanit(
                          fontSize: 12.5,
                          color: Colors.black54,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (var wd = 1; wd <= 7; wd++)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            sel == wd
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: sel == wd
                                ? Theme.of(context).colorScheme.primary
                                : Colors.black38,
                          ),
                          title: Text(
                            _thaiWeekdayLongFixed(wd),
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
                          onTap: () => setSt(() => sel = wd),
                        ),
                      if (needsReason) ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: reasonCtrl,
                          minLines: 2,
                          maxLines: 4,
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(
                            labelText: 'เหตุผล / สาเหตุที่ย้ายวันหยุด',
                            hintText: 'เช่น งานเร่งด่วนวันพุธ, สลับกับทีมอื่น',
                            labelStyle: GoogleFonts.kanit(),
                            hintStyle: GoogleFonts.kanit(fontSize: 13),
                            border: const OutlineInputBorder(),
                          ),
                          style: GoogleFonts.kanit(fontSize: 15),
                        ),
                      ],
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () async {
                          try {
                            await _weeklyOffStore.setWeekOffWeekday(
                              _selectedDate,
                              sel,
                              moveReason: needsReason
                                  ? reasonCtrl.text
                                  : null,
                              client: Supabase.instance.client,
                            );
                          } on ArgumentError catch (e) {
                            if (!ctx.mounted) return;
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text(
                                  e.message ?? 'กรุณาระบุเหตุผล',
                                  style: GoogleFonts.kanit(),
                                ),
                              ),
                            );
                            return;
                          }
                          if (!ctx.mounted) return;
                          Navigator.of(ctx).pop();
                          if (!mounted) return;
                          final reasonNote = needsReason
                              ? ' • ${reasonCtrl.text.trim()}'
                              : '';
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                sel == WeeklyOffCalendarStore.defaultOffWeekday
                                    ? 'ใช้หยุดวันพุธตามมาตรฐานสำหรับสัปดาห์นี้แล้ว'
                                    : 'ย้ายหยุดเป็น${_thaiWeekdayLongFixed(sel)} สำหรับสัปดาห์นี้แล้ว$reasonNote',
                                style: GoogleFonts.kanit(),
                              ),
                            ),
                          );
                          _reload();
                        },
                        child: Text(
                          'บันทึก',
                          style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      );
    } finally {
      reasonCtrl.dispose();
    }
  }

  /// ชื่อวัน (จันทร์=1 … อาทิตย์=7)
  String _thaiWeekdayLongFixed(int weekday) {
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

  /// ข้อความที่แสดงในปฏิทินสำหรับวันหยุดรายสัปดาห์
  String _companyWeeklyHolidayLine(int offWeekday) {
    if (offWeekday == WeeklyOffCalendarStore.defaultOffWeekday) {
      return 'หยุดรายสัปดาห์ (ค่ามาตรฐานวันพุธ)';
    }
    return 'หยุดรายสัปดาห์ • ${_thaiWeekdayLongFixed(offWeekday)} (เลื่อนจากวันพุธในสัปดาห์นี้)';
  }

  void _openCreateEntrySheet() {
    _eventTitleController.clear();
    _eventTimeController.clear();
    _eventNoteController.clear();
    _leaveEmpIds.clear();
    _entryMode = 'Holiday';
    _leaveType = 'Leave';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return FutureBuilder<_CalendarPayload>(
          future: _future,
          builder: (context, snapshot) {
            final data = snapshot.data;
            return StatefulBuilder(
              builder: (context, setSheetState) {
                final media = MediaQuery.of(context);
                return Padding(
                  padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
                  child: _calendarBottomSheetBody(
                    context: context,
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'เพิ่มข้อมูลปฏิทิน • ${_formatDateThai(_selectedDate)}',
                          style: GoogleFonts.kanit(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SegmentedButton<String>(
                          style: _compactSegmentedStyle,
                          segments: const [
                            ButtonSegment(
                              value: 'Holiday',
                              label: Text('วันหยุด/นัดหมาย'),
                            ),
                            ButtonSegment(
                              value: 'Leave',
                              label: Text('ลางาน'),
                            ),
                          ],
                          selected: {_entryMode},
                          onSelectionChanged: (set) {
                            setSheetState(() => _entryMode = set.first);
                          },
                        ),
                        const SizedBox(height: 10),
                        if (_entryMode == 'Leave') ...[
                          SegmentedButton<String>(
                            style: _compactSegmentedStyle,
                            segments: const [
                              ButtonSegment(
                                value: 'Leave',
                                label: Text('ลากิจ'),
                              ),
                              ButtonSegment(
                                value: 'Sick',
                                label: Text('ลาป่วย'),
                              ),
                              ButtonSegment(
                                value: 'Personal',
                                label: Text('ลาอื่นๆ'),
                              ),
                            ],
                            selected: {_leaveType},
                            onSelectionChanged: (set) {
                              setSheetState(() => _leaveType = set.first);
                            },
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: (data?.employees ?? const <Employee>[])
                                .map((e) {
                                  final id = e.id;
                                  final selected = _leaveEmpIds.contains(id);
                                  final name = e.nickname.isNotEmpty
                                      ? e.nickname
                                      : e.name;
                                  return FilterChip(
                                    label: Text(
                                      name,
                                      style: GoogleFonts.kanit(),
                                    ),
                                    selected: selected,
                                    onSelected: (_) {
                                      setSheetState(() {
                                        if (selected) {
                                          _leaveEmpIds.remove(id);
                                        } else {
                                          _leaveEmpIds.add(id);
                                        }
                                      });
                                    },
                                  );
                                })
                                .toList(),
                          ),
                        ] else ...[
                          TextFormField(
                            controller: _eventTitleController,
                            decoration: const InputDecoration(
                              labelText: 'หัวข้อ',
                              prefixIcon: Icon(Icons.title),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _eventTimeController,
                            decoration: const InputDecoration(
                              labelText: 'เวลา (ไม่บังคับ)',
                              prefixIcon: Icon(Icons.schedule_outlined),
                            ),
                            onTap: () async {
                              final t = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.now(),
                              );
                              if (t == null) return;
                              _eventTimeController.text =
                                  '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                              setSheetState(() {});
                            },
                          ),
                        ],
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _eventNoteController,
                          minLines: 2,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'หมายเหตุ',
                            prefixIcon: Icon(Icons.notes_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _savingEntry || data == null
                              ? null
                              : () => _saveCalendarOrLeaveEntry(data),
                          icon: const Icon(Icons.save_outlined),
                          label: Text(
                            _savingEntry ? 'กำลังบันทึก...' : 'บันทึก',
                            style: GoogleFonts.kanit(),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final y = _monthCursor.year;
    final m = _monthCursor.month;
    final monthLabel = _formatThaiMonthYear(_monthCursor);
    final selectedLabel =
        '${_thaiWeekdayLong(_selectedDate)} ${_formatDateThai(_selectedDate)}';

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! > 550) {
          Navigator.maybePop(context);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          titleSpacing: 12,
          centerTitle: false,
          title: Row(
            children: [
              Expanded(
                child: Text(
                  monthLabel,
                  style: GoogleFonts.kanit(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1A1A1A),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'เดือนก่อน',
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                padding: EdgeInsets.zero,
                onPressed: () => setState(() {
                  _monthCursor = DateTime(y, m - 1, 1);
                }),
                icon: const Icon(Icons.chevron_left, color: Color(0xFF5C6470)),
              ),
              IconButton(
                tooltip: 'เดือนถัดไป',
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                padding: EdgeInsets.zero,
                onPressed: () => setState(() {
                  _monthCursor = DateTime(y, m + 1, 1);
                }),
                icon: const Icon(Icons.chevron_right, color: Color(0xFF5C6470)),
              ),
            ],
          ),
          actions: [
            IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
          ],
        ),
        body: FutureBuilder<_CalendarPayload>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const PageLoadingView(label: 'กำลังโหลดปฏิทิน');
            }
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'โหลดปฏิทินไม่สำเร็จ\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              );
            }

            final data = snapshot.data!;
            final days = _buildMonthDays(
              y,
              m,
              data.transactions,
              data.employees,
              data.weeklyOffByMonday,
              data.weeklyOffMoveReasonByMonday,
            );
            final bottomFabClearance =
                MediaQuery.of(context).padding.bottom + 42.0;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selectedLabel,
                        style: GoogleFonts.kanit(
                          color: const Color(0xFF1A2A3C),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _legendChip(
                            color: const Color(0xFFE57373),
                            label: 'หยุด',
                          ),
                          _legendChip(
                            color: const Color(0xFF5C7C9F),
                            label: 'นักขัตฤกษ์',
                          ),
                          _legendChip(
                            color: const Color(0xFFFFB74D),
                            label: 'ลา',
                          ),
                          _legendChip(
                            color: const Color(0xFF00897B),
                            label: 'ทรายบ้าน',
                          ),
                          _legendChip(
                            color: const Color(0xFFE65100),
                            label: 'เหตุการณ์',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFE8ECF0),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: ColoredBox(
                      color: Colors.white,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
                            child: Row(
                              children: [
                                for (final d in const [
                                  'อา.',
                                  'จ.',
                                  'อ.',
                                  'พ.',
                                  'พฤ.',
                                  'ศ.',
                                  'ส.',
                                ])
                                  Expanded(
                                    child: Center(
                                      child: Text(
                                        d,
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        style: GoogleFonts.kanit(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 10,
                                          color: const Color(0xFF6B7280),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const Divider(height: 1, color: Color(0xFFF0F2F5)),
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                bottom: bottomFabClearance,
                              ),
                              child: LayoutBuilder(
                                builder: (context, gridConstraints) {
                                  const mainGap = 3.0;
                                  const crossGap = 6.0;
                                  const padH = 8.0;
                                  const padTop = 0.0;
                                  final rows = (days.length / 7).ceil().clamp(
                                    1,
                                    12,
                                  );
                                  final innerW =
                                      gridConstraints.maxWidth - padH * 2;
                                  final innerH =
                                      gridConstraints.maxHeight - padTop;
                                  if (innerW <= 8 || innerH <= 8) {
                                    return const SizedBox.shrink();
                                  }
                                  final cellH =
                                      (innerH - mainGap * (rows - 1)) / rows;

                                  return Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      padH,
                                      padTop,
                                      padH,
                                      0,
                                    ),
                                    child: GridView.builder(
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      gridDelegate:
                                          SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount: 7,
                                            mainAxisSpacing: mainGap,
                                            crossAxisSpacing: crossGap,
                                            mainAxisExtent: cellH,
                                          ),
                                      itemCount: days.length,
                                      itemBuilder: (context, index) {
                                        final day = days[index];
                                        if (day == null) {
                                          return const SizedBox.shrink();
                                        }
                                        final d = _dateFromYmd(day.dateStr);
                                        final isSelected =
                                            d.year == _selectedDate.year &&
                                            d.month == _selectedDate.month &&
                                            d.day == _selectedDate.day;
                                        final now = DateTime.now();
                                        final isToday =
                                            d.year == now.year &&
                                            d.month == now.month &&
                                            d.day == now.day;
                                        return _DayCell(
                                          day: day,
                                          selected: isSelected,
                                          today: isToday,
                                          onTap: () => _pickDay(day),
                                        );
                                      },
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openCreateEntrySheet,
          icon: const Icon(Icons.add),
          label: Text('เพิ่มวันหยุด/ลา', style: GoogleFonts.kanit()),
        ),
      ),
    );
  }

  Widget _legendChip({required Color color, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: GoogleFonts.kanit(
          color: color,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  List<_CalendarDay?> _buildMonthDays(
    int year,
    int month,
    List<AppTransaction> transactions,
    List<Employee> employees,
    Map<String, int> weeklyOffByMonday,
    Map<String, String> weeklyOffMoveReasonByMonday,
  ) {
    final firstWeekday = DateTime(year, month, 1).weekday % 7;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final holidayMap = getThaiPublicHolidayMap(year);

    final result = <_CalendarDay?>[];
    for (var i = 0; i < firstWeekday; i++) {
      result.add(null);
    }

    for (var d = 1; d <= daysInMonth; d++) {
      final dateStr =
          '$year-${month.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
      final dayTx = transactions.where((t) => t.date == dateStr).toList();
      final calendarRows = dayTx
          .where((t) => t.category == 'Calendar')
          .toList();
      final autoHoliday = holidayMap[dateStr];
      final thaiPublicHolidayNames = <String>[
        if (autoHoliday != null) autoHoliday.name,
      ];
      final userHolidayDescriptions = calendarRows
          .where((t) => (t.subCategory ?? '').toLowerCase() == 'holiday')
          .map((t) => t.description.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      final dtPlain = DateTime(year, month, d);
      final monKey = WeeklyOffCalendarStore.mondayKeyOf(dtPlain);
      final offWd =
          weeklyOffByMonday[monKey] ?? WeeklyOffCalendarStore.defaultOffWeekday;
      final moveReason = weeklyOffMoveReasonByMonday[monKey];
      final weeklyOffLine = dtPlain.weekday == offWd
          ? _companyWeeklyHolidayLine(offWd)
          : null;

      final leaveRows = transactions.where((t) {
        return isLaborLeaveRecord(t) && laborLeaveCoversCalendarDay(t, dateStr);
      }).toList();
      final leaveNames = calendarLeaveNames(leaveRows, employees);
      final leaveDetails = calendarLeaveDetails(
        leaveRows,
        employees,
        viewingDayKey: dateStr,
      );

      final dailyEventLines = dayTx
          .where(_isDailyEventTransaction)
          .map(_formatDailyEventLine)
          .where((s) => s.isNotEmpty)
          .toList();
      final homeSandLines = calendarHomeSandLines(dayTx);

      result.add(
        _CalendarDay(
          day: d,
          dateStr: dateStr,
          thaiPublicHolidayNames: thaiPublicHolidayNames,
          userHolidayDescriptions: userHolidayDescriptions,
          weeklyOffLine: weeklyOffLine,
          weeklyOffMoveReason: dtPlain.weekday == offWd ? moveReason : null,
          leaveNames: leaveNames,
          leaveDetails: leaveDetails,
          homeSandLines: homeSandLines,
          dailyEventLines: dailyEventLines,
        ),
      );
    }
    return result;
  }

  String _formatThaiMonthYear(DateTime d) {
    const m = [
      'มกราคม',
      'กุมภาพันธ์',
      'มีนาคม',
      'เมษายน',
      'พฤษภาคม',
      'มิถุนายน',
      'กรกฎาคม',
      'สิงหาคม',
      'กันยายน',
      'ตุลาคม',
      'พฤศจิกายน',
      'ธันวาคม',
    ];
    return '${m[d.month - 1]} ${d.year + 543}';
  }

  String _formatDateThai(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yy = d.year + 543;
    return '$dd/$mm/$yy';
  }

  String _thaiWeekdayLong(DateTime d) {
    const names = [
      'วันจันทร์',
      'วันอังคาร',
      'วันพุธ',
      'วันพฤหัสบดี',
      'วันศุกร์',
      'วันเสาร์',
      'วันอาทิตย์',
    ];
    return names[d.weekday - 1];
  }

  DateTime _dateFromYmd(String ymd) {
    final p = ymd.split('-');
    if (p.length != 3) return DateTime.now();
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }
}

class _CalendarPayload {
  const _CalendarPayload({
    required this.transactions,
    required this.employees,
    required this.weeklyOffByMonday,
    required this.weeklyOffMoveReasonByMonday,
  });
  final List<AppTransaction> transactions;
  final List<Employee> employees;
  final Map<String, int> weeklyOffByMonday;
  final Map<String, String> weeklyOffMoveReasonByMonday;
}

class _CalendarDay {
  const _CalendarDay({
    required this.day,
    required this.dateStr,
    required this.thaiPublicHolidayNames,
    required this.userHolidayDescriptions,
    required this.leaveNames,
    required this.leaveDetails,
    required this.dailyEventLines,
    this.weeklyOffLine,
    this.weeklyOffMoveReason,
    this.homeSandLines = const [],
  });

  final int day;
  final String dateStr;
  final List<String> thaiPublicHolidayNames;
  final List<String> userHolidayDescriptions;
  final String? weeklyOffLine;
  final String? weeklyOffMoveReason;
  final List<String> leaveNames;
  final List<CalendarLeaveDetail> leaveDetails;
  final List<String> homeSandLines;
  final List<String> dailyEventLines;

  bool get hasWeeklyOff => weeklyOffLine != null;
  bool get hasHomeSand => homeSandLines.isNotEmpty;
  bool get hasDailyEvents => dailyEventLines.isNotEmpty;

  bool get hasAnyPlannerEntry =>
      thaiPublicHolidayNames.isNotEmpty ||
      weeklyOffLine != null ||
      userHolidayDescriptions.isNotEmpty ||
      leaveDetails.isNotEmpty ||
      homeSandLines.isNotEmpty ||
      dailyEventLines.isNotEmpty;

  int get activityCount {
    var n = 0;
    if (hasWeeklyOff) n++;
    if (userHolidayDescriptions.isNotEmpty) n++;
    if (leaveNames.isNotEmpty) n++;
    if (hasHomeSand) n++;
    if (hasDailyEvents) n++;
    if (thaiPublicHolidayNames.isNotEmpty) n++;
    return n;
  }

  /// ป้ายสรุปทุกประเภท (ใช้ใน bottom sheet)
  List<_CalendarDayTag> allTags() {
    final tags = <_CalendarDayTag>[];
    if (hasWeeklyOff || userHolidayDescriptions.isNotEmpty) {
      final n =
          (hasWeeklyOff ? 1 : 0) + userHolidayDescriptions.length;
      tags.add(
        _CalendarDayTag(
          color: const Color(0xFFE57373),
          label: n > 1 ? 'หยุด · $n' : 'หยุด',
          icon: Icons.event_busy_outlined,
        ),
      );
    }
    if (leaveNames.isNotEmpty) {
      tags.add(
        _CalendarDayTag(
          color: const Color(0xFFFFB74D),
          label: 'ลา ${leaveNames.length}',
          icon: Icons.person_off_outlined,
        ),
      );
    }
    if (hasHomeSand) {
      tags.add(
        const _CalendarDayTag(
          color: Color(0xFF00897B),
          label: 'ทรายบ้าน',
          icon: Icons.waves_outlined,
        ),
      );
    }
    if (hasDailyEvents) {
      tags.add(
        _CalendarDayTag(
          color: const Color(0xFFE65100),
          label: dailyEventLines.length > 1
              ? 'เหตุ ${dailyEventLines.length}'
              : 'เหตุการณ์',
          icon: Icons.flag_outlined,
        ),
      );
    }
    if (thaiPublicHolidayNames.isNotEmpty) {
      tags.add(
        const _CalendarDayTag(
          color: Color(0xFF5C7C9F),
          label: 'นักขัตฤกษ์',
          icon: Icons.star_outline_rounded,
        ),
      );
    }
    return tags;
  }

  /// ป้ายบนเซลล์ — สูงสุด [max] ป้าย + ตัวนับส่วนเกิน
  List<_CalendarDayTag> cellTags({int max = 2}) {
    final all = allTags();
    if (all.length <= max) return all;
    return [
      ...all.take(max),
      _CalendarDayTag(
        color: const Color(0xFF78909C),
        label: '+${all.length - max}',
        icon: Icons.more_horiz_rounded,
      ),
    ];
  }

  List<Color> markerDotColors({int max = 4}) {
    return allTags().map((t) => t.color).take(max).toList();
  }

  Color? primaryAccentColor() {
    if (hasWeeklyOff || userHolidayDescriptions.isNotEmpty) {
      return const Color(0xFFE57373);
    }
    if (leaveNames.isNotEmpty) return const Color(0xFFFFB74D);
    if (hasHomeSand) return const Color(0xFF00897B);
    if (hasDailyEvents) return const Color(0xFFE65100);
    if (thaiPublicHolidayNames.isNotEmpty) return const Color(0xFF5C7C9F);
    return null;
  }
}

class _CalendarDayTag {
  const _CalendarDayTag({
    required this.color,
    required this.label,
    required this.icon,
  });

  final Color color;
  final String label;
  final IconData icon;
}

class _CalendarTagChip extends StatelessWidget {
  const _CalendarTagChip({required this.tag, this.compact = true});

  final _CalendarDayTag tag;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final fs = compact ? 9.0 : 12.0;
    final iconSize = compact ? 11.0 : 14.0;
    final vPad = compact ? 2.0 : 4.0;
    final hPad = compact ? 5.0 : 8.0;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        color: tag.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(compact ? 6 : 999),
        border: Border.all(color: tag.color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(tag.icon, size: iconSize, color: tag.color),
          const SizedBox(width: 3),
          Text(
            tag.label,
            style: GoogleFonts.kanit(
              fontSize: fs,
              fontWeight: FontWeight.w700,
              color: tag.color.withValues(alpha: 0.95),
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.selected,
    required this.today,
    required this.onTap,
  });
  final _CalendarDay day;
  final bool selected;
  final bool today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = day.primaryAccentColor();
    final tags = day.cellTags(max: 2);
    final dots = day.markerDotColors(max: 4);
    final hasActivity = day.activityCount > 0;

    final borderColor = selected
        ? const Color(0xFF1E88E5)
        : today
        ? const Color(0xFF90A4AE)
        : const Color(0xFFE8ECF0);
    final borderW = selected ? 1.8 : 1.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFF0F7FF) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(width: borderW, color: borderColor),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: const Color(0xFF1E88E5).withValues(alpha: 0.12),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (accent != null)
                Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(10),
                    ),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(5, 5, 5, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (today)
                            Container(
                              width: 26,
                              height: 26,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: selected
                                    ? const Color(0xFF1565C0)
                                    : const Color(0xFF263238),
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '${day.day}',
                                style: GoogleFonts.kanit(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  color: Colors.white,
                                  height: 1,
                                ),
                              ),
                            )
                          else
                            Text(
                              '${day.day}',
                              style: GoogleFonts.kanit(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                height: 1,
                                color: selected
                                    ? const Color(0xFF1565C0)
                                    : const Color(0xFF37474F),
                              ),
                            ),
                          const Spacer(),
                          if (dots.isNotEmpty)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final c in dots)
                                  Container(
                                    width: 5,
                                    height: 5,
                                    margin: const EdgeInsets.only(left: 2),
                                    decoration: BoxDecoration(
                                      color: c,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                      if (hasActivity) ...[
                        const SizedBox(height: 3),
                        Expanded(
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: Wrap(
                              spacing: 3,
                              runSpacing: 3,
                              children: [
                                for (final tag in tags)
                                  _CalendarTagChip(tag: tag),
                              ],
                            ),
                          ),
                        ),
                      ] else
                        const Spacer(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
