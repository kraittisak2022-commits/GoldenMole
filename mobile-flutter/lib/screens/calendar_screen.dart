import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_transaction.dart';
import '../models/employee.dart';
import '../services/employee_service.dart';
import '../services/local_data_cache.dart';
import '../services/transaction_service.dart';
import '../services/weekly_off_calendar_store.dart';
import '../utils/daily_module_transactions.dart';
import '../utils/mobile_error_screen_tracker.dart';
import '../utils/mobile_screen_ids.dart';
import '../utils/thai_holidays.dart';
import '../widgets/empty_state_view.dart';
import '../widgets/list_page_skeleton.dart';

String _calendarFirstGlyph(String text) {
  final t = text.trim();
  if (t.isEmpty) return '?';
  return String.fromCharCode(t.runes.first);
}

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
    this.embedded = false,
    this.externalSelectedDay,
    this.onDaySelected,
  });

  final TransactionService transactionService;
  final EmployeeService employeeService;

  /// When true, render as an in-home panel (no Scaffold / AppBar / swipe-back).
  final bool embedded;

  /// Sync selected day from the parent home screen.
  final DateTime? externalSelectedDay;

  /// Notify home when user picks a day on the month grid.
  final ValueChanged<DateTime>? onDaySelected;

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
    MobileErrorScreenTracker.set(
      page: 'ปฏิทิน',
      pageId: MobileScreenIds.pageCalendar,
      stepId: MobileScreenIds.stepCalendarMain,
    );
    final external = widget.externalSelectedDay;
    if (external != null) {
      _selectedDate = DateTime(external.year, external.month, external.day);
      _monthCursor = DateTime(external.year, external.month, 1);
    }
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant CalendarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final external = widget.externalSelectedDay;
    if (external == null) return;
    final next = DateTime(external.year, external.month, external.day);
    final sameDay = next.year == _selectedDate.year &&
        next.month == _selectedDate.month &&
        next.day == _selectedDate.day;
    if (sameDay) return;
    setState(() {
      _selectedDate = next;
      if (_monthCursor.year != next.year || _monthCursor.month != next.month) {
        _monthCursor = DateTime(next.year, next.month, 1);
      }
    });
  }

  @override
  void dispose() {
    _eventTitleController.dispose();
    _eventTimeController.dispose();
    _eventNoteController.dispose();
    super.dispose();
  }

  Future<_CalendarPayload> _load({bool forceRefresh = false}) async {
    late final List<AppTransaction> transactions;
    late final List<Employee> employees;
    if (!forceRefresh) {
      final cachedTx = await LocalDataCache.readTransactionsFullAny();
      final cachedEmp = await LocalDataCache.readEmployeesAny();
      transactions = (cachedTx != null && cachedTx.isNotEmpty)
          ? cachedTx
          : await widget.transactionService.fetchTransactions(
              forceRefresh: false,
            );
      employees = (cachedEmp != null && cachedEmp.isNotEmpty)
          ? cachedEmp
          : await widget.employeeService.fetchEmployees(forceRefresh: false);
    } else {
      transactions = await widget.transactionService.fetchTransactions(
        forceRefresh: true,
      );
      employees = await widget.employeeService.fetchEmployees(
        forceRefresh: true,
      );
    }
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

  /// Phone vertical layout — same gate as daily menus / attendance.
  bool _phonePortrait(BuildContext context) {
    final s = MediaQuery.sizeOf(context);
    return s.shortestSide < 600 && s.height >= s.width;
  }

  String _ymd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  _CalendarDay? _findCalendarDay(List<_CalendarDay?> days, DateTime d) {
    final key = _ymd(d);
    for (final cell in days) {
      if (cell != null && cell.dateStr == key) return cell;
    }
    return null;
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
    widget.onDaySelected?.call(selected);
    _openDayDetails(day);
  }

  void _openDayDetails(_CalendarDay day) {
    final phonePortrait = _phonePortrait(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF4F6F9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(phonePortrait ? 18 : 24),
        ),
      ),
      builder: (context) {
        return _calendarBottomSheetBody(
          context: context,
          padding: EdgeInsets.fromLTRB(
            phonePortrait ? 12 : 16,
            phonePortrait ? 2 : 4,
            phonePortrait ? 12 : 16,
            0,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _dayDetailHeader(day, compact: phonePortrait),
              SizedBox(height: phonePortrait ? 8 : 12),
              if (day.thaiPublicHolidayNames.isNotEmpty)
                _daySectionCard(
                  icon: Icons.star_outline_rounded,
                  title: phonePortrait
                      ? 'นักขัตฤกษ์'
                      : 'นักขัตฤกษ์ (ประมาณการ)',
                  subtitle: phonePortrait
                      ? 'แจ้งเตือนทางปฏิทิน'
                      : 'แจ้งเตือนทางปฏิทิน — ไม่ได้หมายว่าองค์กรหยุดครบถ้วน',
                  color: const Color(0xFF5C7C9F),
                  compact: phonePortrait,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final name in day.thaiPublicHolidayNames)
                        _dayBulletLine(name, compact: phonePortrait),
                    ],
                  ),
                ),
              if (day.weeklyOffLine != null ||
                  day.userHolidayDescriptions.isNotEmpty)
                _daySectionCard(
                  icon: Icons.event_busy_outlined,
                  title: 'วันหยุด / กิจกรรม',
                  color: const Color(0xFFE57373),
                  compact: phonePortrait,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (day.weeklyOffLine != null)
                        _dayBulletLine(
                          day.weeklyOffLine!,
                          compact: phonePortrait,
                        ),
                      if (day.weeklyOffMoveReason != null &&
                          day.weeklyOffMoveReason!.isNotEmpty)
                        _dayBulletLine(
                          'เลื่อนหยุด: ${day.weeklyOffMoveReason}',
                          muted: true,
                          compact: phonePortrait,
                        ),
                      for (final desc in day.userHolidayDescriptions)
                        _dayBulletLine(desc, compact: phonePortrait),
                    ],
                  ),
                ),
              if (day.leaveDetails.isNotEmpty)
                _daySectionCard(
                  icon: Icons.person_off_outlined,
                  title: 'รายการลา (${day.leaveDetails.length})',
                  color: const Color(0xFFFFB74D),
                  compact: phonePortrait,
                  child: Column(
                    children: [
                      for (var i = 0; i < day.leaveDetails.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: phonePortrait ? 14 : 20,
                            color: const Color(0xFFE8ECF0),
                          ),
                        _dayLeaveCard(
                          day.leaveDetails[i],
                          compact: phonePortrait,
                        ),
                      ],
                    ],
                  ),
                ),
              if (day.homeSandLines.isNotEmpty)
                _daySectionCard(
                  icon: Icons.waves_outlined,
                  title: 'ทรายที่ล้างที่บ้าน',
                  color: const Color(0xFF00897B),
                  compact: phonePortrait,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final line in day.homeSandLines)
                        _dayBulletLine(line, compact: phonePortrait),
                    ],
                  ),
                ),
              if (day.dailyEventLines.isNotEmpty)
                _daySectionCard(
                  icon: Icons.flag_outlined,
                  title: 'เหตุการณ์ประจำวัน',
                  color: const Color(0xFFE65100),
                  compact: phonePortrait,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final line in day.dailyEventLines)
                        _dayBulletLine(line, compact: phonePortrait),
                    ],
                  ),
                ),
              if (!day.hasAnyPlannerEntry)
                const EmptyStateView(
                  icon: Icons.event_available_outlined,
                  title: 'ไม่มีรายการในวันนี้',
                  subtitle: 'เพิ่มงานหรือเหตุการณ์ได้จากปุ่มด้านล่าง',
                  compact: true,
                ),
              SizedBox(height: phonePortrait ? 6 : 8),
              OutlinedButton.icon(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await _showMoveWeeklyOffSheet();
                },
                icon: Icon(
                  Icons.swap_horiz_rounded,
                  size: phonePortrait ? 18 : 22,
                ),
                label: Text(
                  phonePortrait ? 'ย้ายหยุดสัปดาห์' : 'ย้ายหยุดรายสัปดาห์',
                  style: GoogleFonts.kanit(
                    fontWeight: FontWeight.w700,
                    fontSize: phonePortrait ? 13.5 : 14,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: Size.fromHeight(phonePortrait ? 42 : 48),
                  visualDensity: phonePortrait
                      ? VisualDensity.compact
                      : VisualDensity.standard,
                ),
              ),
              SizedBox(height: phonePortrait ? 6 : 8),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  _openCreateEntrySheet();
                },
                icon: Icon(
                  Icons.add_circle_outline,
                  size: phonePortrait ? 18 : 22,
                ),
                label: Text(
                  phonePortrait ? 'เพิ่มวันหยุด/ลา' : 'เพิ่มวันหยุด / ลางาน',
                  style: GoogleFonts.kanit(
                    fontSize: phonePortrait ? 13.5 : 14,
                  ),
                ),
                style: FilledButton.styleFrom(
                  minimumSize: Size.fromHeight(phonePortrait ? 44 : 48),
                  visualDensity: phonePortrait
                      ? VisualDensity.compact
                      : VisualDensity.standard,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _dayDetailHeader(_CalendarDay day, {bool compact = false}) {
    final tags = day.allTags();
    return Container(
      padding: EdgeInsets.all(compact ? 10 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(compact ? 12 : 16),
        border: Border.all(color: const Color(0xFFE3E8EF)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: compact ? 6 : 10,
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
              fontSize: compact ? 12 : 13,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF64748B),
            ),
          ),
          Text(
            _formatDateThai(_selectedDate),
            style: GoogleFonts.kanit(
              fontSize: compact ? 18 : 22,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1A2A3C),
              height: 1.15,
            ),
          ),
          if (tags.isNotEmpty) ...[
            SizedBox(height: compact ? 6 : 10),
            Wrap(
              spacing: compact ? 4 : 6,
              runSpacing: compact ? 4 : 6,
              children: tags
                  .map(
                    (t) => _CalendarTagChip(
                      tag: t,
                      // Day-detail chips stay readable; cell chips stay tiny.
                      compact: false,
                    ),
                  )
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
    bool compact = false,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: compact ? 8 : 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(compact ? 12 : 16),
        border: Border.all(color: const Color(0xFFE8ECF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(
              compact ? 10 : 12,
              compact ? 8 : 10,
              compact ? 10 : 12,
              compact ? 8 : 10,
            ),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(compact ? 11 : 15),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: compact ? 17 : 20, color: color),
                SizedBox(width: compact ? 6 : 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.kanit(
                          fontWeight: FontWeight.w800,
                          fontSize: compact ? 13.5 : 15,
                          color: color.withValues(alpha: 0.95),
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          style: GoogleFonts.kanit(
                            fontSize: compact ? 10.5 : 11,
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
            padding: EdgeInsets.fromLTRB(
              compact ? 10 : 12,
              compact ? 8 : 10,
              compact ? 10 : 12,
              compact ? 10 : 12,
            ),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _dayBulletLine(
    String text, {
    bool muted = false,
    bool compact = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 4 : 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: compact ? 6 : 7),
            child: Container(
              width: compact ? 4 : 5,
              height: compact ? 4 : 5,
              decoration: BoxDecoration(
                color: muted ? Colors.black26 : const Color(0xFF90A4AE),
                shape: BoxShape.circle,
              ),
            ),
          ),
          SizedBox(width: compact ? 6 : 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.kanit(
                fontSize: compact ? 13 : 14,
                height: 1.35,
                color: muted ? Colors.black54 : const Color(0xFF37474F),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayLeaveCard(CalendarLeaveDetail item, {bool compact = false}) {
    final reason = item.reason.trim();
    final initial = _calendarFirstGlyph(item.headline);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: compact ? 34 : 38,
          height: compact ? 34 : 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFB74D), Color(0xFFF57C00)],
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF57C00).withValues(alpha: 0.25),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            initial,
            style: GoogleFonts.kanit(
              fontWeight: FontWeight.w800,
              fontSize: compact ? 14 : 16,
              color: Colors.white,
            ),
          ),
        ),
        SizedBox(width: compact ? 8 : 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.headline,
                style: GoogleFonts.kanit(
                  fontWeight: FontWeight.w800,
                  fontSize: compact ? 13.5 : 14.5,
                  color: const Color(0xFF1A2A3C),
                  height: 1.3,
                ),
              ),
              if (item.spanNote != null) ...[
                const SizedBox(height: 2),
                Text(
                  item.spanNote!,
                  style: GoogleFonts.kanit(
                    fontSize: compact ? 11 : 12,
                    color: Colors.black54,
                  ),
                ),
              ],
              SizedBox(height: compact ? 4 : 6),
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 8 : 10,
                  vertical: compact ? 6 : 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(compact ? 8 : 10),
                  border: Border.all(color: const Color(0xFFFFE082)),
                ),
                child: Text(
                  reason.isNotEmpty ? reason : 'ยังไม่ระบุเหตุผล',
                  style: GoogleFonts.kanit(
                    fontSize: compact ? 12.5 : 13.5,
                    height: 1.35,
                    color: reason.isNotEmpty
                        ? const Color(0xFF5D4037)
                        : Colors.black45,
                  ),
                ),
              ),
            ],
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
                        'ค่ามาตรฐาน: วันพฤหัสบดีของทุกสัปดาห์ • จันทร์แรกของสัปดาห์นี้: $mondayStr',
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
                            hintText: 'เช่น งานเร่งด่วนวันพฤหัสบดี, สลับกับทีมอื่น',
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
                                    ? 'ใช้หยุดวันพฤหัสบดีตามมาตรฐานสำหรับสัปดาห์นี้แล้ว'
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
      return 'หยุดรายสัปดาห์ (ค่ามาตรฐานวันพฤหัสบดี)';
    }
    return 'หยุดรายสัปดาห์ • ${_thaiWeekdayLongFixed(offWeekday)} (เลื่อนจากวันพฤหัสบดีในสัปดาห์นี้)';
  }

  void _openCreateEntrySheet() {
    _eventTitleController.clear();
    _eventTimeController.clear();
    _eventNoteController.clear();
    _leaveEmpIds.clear();
    _entryMode = 'Holiday';
    _leaveType = 'Leave';
    final phonePortrait = _phonePortrait(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(phonePortrait ? 18 : 24),
        ),
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
                    padding: EdgeInsets.fromLTRB(
                      phonePortrait ? 12 : 16,
                      phonePortrait ? 4 : 6,
                      phonePortrait ? 12 : 16,
                      0,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          phonePortrait
                              ? 'เพิ่ม • ${_formatDateThai(_selectedDate)}'
                              : 'เพิ่มข้อมูลปฏิทิน • ${_formatDateThai(_selectedDate)}',
                          style: GoogleFonts.kanit(
                            fontSize: phonePortrait ? 16 : 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: phonePortrait ? 8 : 12),
                        SegmentedButton<String>(
                          style: _compactSegmentedStyle,
                          segments: [
                            ButtonSegment(
                              value: 'Holiday',
                              label: Text(
                                phonePortrait ? 'หยุด/นัด' : 'วันหยุด/นัดหมาย',
                              ),
                            ),
                            const ButtonSegment(
                              value: 'Leave',
                              label: Text('ลางาน'),
                            ),
                          ],
                          selected: {_entryMode},
                          onSelectionChanged: (set) {
                            setSheetState(() => _entryMode = set.first);
                          },
                        ),
                        SizedBox(height: phonePortrait ? 8 : 10),
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
                          SizedBox(height: phonePortrait ? 8 : 10),
                          Wrap(
                            spacing: phonePortrait ? 6 : 8,
                            runSpacing: phonePortrait ? 6 : 8,
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
                                      style: GoogleFonts.kanit(
                                        fontSize: phonePortrait ? 13 : 14,
                                      ),
                                    ),
                                    visualDensity: phonePortrait
                                        ? VisualDensity.compact
                                        : VisualDensity.standard,
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
                            style: GoogleFonts.kanit(
                              fontSize: phonePortrait ? 14.5 : 16,
                            ),
                            decoration: InputDecoration(
                              labelText: 'หัวข้อ',
                              isDense: phonePortrait,
                              prefixIcon: Icon(
                                Icons.title,
                                size: phonePortrait ? 20 : 24,
                              ),
                            ),
                          ),
                          SizedBox(height: phonePortrait ? 6 : 8),
                          TextFormField(
                            controller: _eventTimeController,
                            style: GoogleFonts.kanit(
                              fontSize: phonePortrait ? 14.5 : 16,
                            ),
                            decoration: InputDecoration(
                              labelText: 'เวลา (ไม่บังคับ)',
                              isDense: phonePortrait,
                              prefixIcon: Icon(
                                Icons.schedule_outlined,
                                size: phonePortrait ? 20 : 24,
                              ),
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
                        SizedBox(height: phonePortrait ? 6 : 8),
                        TextFormField(
                          controller: _eventNoteController,
                          minLines: phonePortrait ? 2 : 2,
                          maxLines: phonePortrait ? 2 : 3,
                          style: GoogleFonts.kanit(
                            fontSize: phonePortrait ? 14.5 : 16,
                          ),
                          decoration: InputDecoration(
                            labelText: 'หมายเหตุ',
                            isDense: phonePortrait,
                            prefixIcon: Icon(
                              Icons.notes_outlined,
                              size: phonePortrait ? 20 : 24,
                            ),
                          ),
                        ),
                        SizedBox(height: phonePortrait ? 10 : 12),
                        FilledButton.icon(
                          onPressed: _savingEntry || data == null
                              ? null
                              : () => _saveCalendarOrLeaveEntry(data),
                          icon: Icon(
                            Icons.save_outlined,
                            size: phonePortrait ? 18 : 22,
                          ),
                          label: Text(
                            _savingEntry ? 'กำลังบันทึก...' : 'บันทึก',
                            style: GoogleFonts.kanit(
                              fontSize: phonePortrait ? 14 : 15,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            minimumSize: Size.fromHeight(
                              phonePortrait ? 44 : 48,
                            ),
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

  Widget _monthNavRow(String monthLabel, int y, int m, {bool compact = false}) {
    final btnSize = compact ? 36.0 : 40.0;
    final iconSize = compact ? 22.0 : 24.0;
    return Row(
      children: [
        Expanded(
          child: Text(
            monthLabel,
            style: GoogleFonts.kanit(
              fontSize: compact
                  ? (widget.embedded ? 15.0 : 17.0)
                  : (widget.embedded ? 17.0 : 20.0),
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1A1A1A),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          tooltip: 'เดือนก่อน',
          constraints: BoxConstraints(minWidth: btnSize, minHeight: btnSize),
          padding: EdgeInsets.zero,
          visualDensity: compact ? VisualDensity.compact : null,
          onPressed: () => setState(() {
            _monthCursor = DateTime(y, m - 1, 1);
          }),
          icon: Icon(
            Icons.chevron_left,
            size: iconSize,
            color: const Color(0xFF5C6470),
          ),
        ),
        IconButton(
          tooltip: 'เดือนถัดไป',
          constraints: BoxConstraints(minWidth: btnSize, minHeight: btnSize),
          padding: EdgeInsets.zero,
          visualDensity: compact ? VisualDensity.compact : null,
          onPressed: () => setState(() {
            _monthCursor = DateTime(y, m + 1, 1);
          }),
          icon: Icon(
            Icons.chevron_right,
            size: iconSize,
            color: const Color(0xFF5C6470),
          ),
        ),
        IconButton(
          onPressed: _reload,
          constraints: BoxConstraints(minWidth: btnSize, minHeight: btnSize),
          padding: EdgeInsets.zero,
          visualDensity: compact ? VisualDensity.compact : null,
          icon: Icon(Icons.refresh, size: iconSize),
        ),
      ],
    );
  }

  Widget _calendarBody({required double bottomClearance}) {
    final y = _monthCursor.year;
    final m = _monthCursor.month;
    final phonePortrait = _phonePortrait(context);
    final selectedLabel =
        '${_thaiWeekdayLong(_selectedDate)} ${_formatDateThai(_selectedDate)}';

    return FutureBuilder<_CalendarPayload>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(
            height: phonePortrait ? 180 : 220,
            child: const ListPageSkeleton(rowCount: 3, showHeaderBlock: false),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
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
        final grid = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                phonePortrait ? 10 : 12,
                phonePortrait ? 2 : 4,
                phonePortrait ? 10 : 12,
                phonePortrait ? 6 : 8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.embedded) ...[
                    _monthNavRow(
                      _formatThaiMonthYear(_monthCursor),
                      y,
                      m,
                      compact: phonePortrait,
                    ),
                    SizedBox(height: phonePortrait ? 2 : 4),
                  ],
                  Text(
                    selectedLabel,
                    style: GoogleFonts.kanit(
                      color: const Color(0xFF1A2A3C),
                      fontSize: phonePortrait ? 12 : 13,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: phonePortrait ? 6 : 8),
                  Wrap(
                    spacing: phonePortrait ? 4 : 6,
                    runSpacing: phonePortrait ? 4 : 6,
                    children: [
                      _legendChip(
                        color: const Color(0xFFD32F2F),
                        label: phonePortrait ? 'หยุดสัปดาห์' : 'หยุดรายสัปดาห์',
                        compact: phonePortrait,
                      ),
                      _legendChip(
                        color: const Color(0xFFE57373),
                        label: 'นัด/หยุด',
                        compact: phonePortrait,
                      ),
                      _legendChip(
                        color: const Color(0xFF5C7C9F),
                        label: phonePortrait ? 'นักขัต' : 'นักขัตฤกษ์',
                        compact: phonePortrait,
                      ),
                      _legendChip(
                        color: const Color(0xFFFFB74D),
                        label: 'ลางาน',
                        compact: phonePortrait,
                      ),
                      _legendChip(
                        color: const Color(0xFF00897B),
                        label: phonePortrait ? 'ทราย' : 'ทรายบ้าน',
                        compact: phonePortrait,
                      ),
                      _legendChip(
                        color: const Color(0xFFE65100),
                        label: phonePortrait ? 'เหตุ' : 'เหตุการณ์',
                        compact: phonePortrait,
                      ),
                    ],
                  ),
                  SizedBox(height: phonePortrait ? 8 : 10),
                  _CalendarWeekStrip(
                    monthDays: days,
                    selectedDate: _selectedDate,
                    compact: phonePortrait,
                    onSelectDate: (d) {
                      final key = _ymd(d);
                      _CalendarDay? hit;
                      for (final cell in days) {
                        if (cell != null && cell.dateStr == key) {
                          hit = cell;
                          break;
                        }
                      }
                      if (hit != null) {
                        _pickDay(hit);
                        return;
                      }
                      setState(() => _selectedDate = d);
                      widget.onDaySelected?.call(d);
                    },
                  ),
                  SizedBox(height: phonePortrait ? 8 : 10),
                  _CalendarSelectedDayPanel(
                    day: _findCalendarDay(days, _selectedDate),
                    compact: phonePortrait,
                    onOpenDetails: () {
                      final hit = _findCalendarDay(days, _selectedDate);
                      if (hit != null) _openDayDetails(hit);
                    },
                  ),
                ],
              ),
            ),
            const Divider(
              height: 1,
              thickness: 1,
              color: Color(0xFFE8ECF0),
            ),
            if (widget.embedded)
              Padding(
                padding: EdgeInsets.only(top: phonePortrait ? 4 : 8),
                child: _calendarGridBlock(
                  days: days,
                  bottomClearance: 0,
                  fixedGridHeight: phonePortrait ? 200 : 240,
                  compact: phonePortrait,
                ),
              )
            else
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: phonePortrait ? 4 : 8),
                  child: _calendarGridBlock(
                    days: days,
                    bottomClearance: bottomClearance,
                    fixedGridHeight: null,
                    compact: phonePortrait,
                  ),
                ),
              ),
          ],
        );
        return grid;
      },
    );
  }

  Widget _calendarGridBlock({
    required List<_CalendarDay?> days,
    required double bottomClearance,
    required double? fixedGridHeight,
    bool compact = false,
  }) {
    return ColoredBox(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(compact ? 2 : 4, 0, compact ? 2 : 4, 0),
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
                          fontSize: compact ? 9 : 10,
                          color: const Color(0xFF6B7280),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF0F2F5)),
          if (fixedGridHeight != null)
            SizedBox(
              height: fixedGridHeight,
              child: _monthGrid(days: days, compact: compact),
            )
          else
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: bottomClearance),
                child: _monthGrid(days: days, compact: compact),
              ),
            ),
          if (widget.embedded) ...[
            SizedBox(height: compact ? 6 : 8),
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 10 : 12,
                0,
                compact ? 10 : 12,
                compact ? 6 : 8,
              ),
              child: FilledButton.icon(
                onPressed: _openCreateEntrySheet,
                icon: Icon(Icons.add, size: compact ? 16 : 18),
                label: Text(
                  compact ? 'เพิ่มหยุด/ลา' : 'เพิ่มวันหยุด/ลา',
                  style: GoogleFonts.kanit(
                    fontWeight: FontWeight.w700,
                    fontSize: compact ? 13.5 : 14,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0D98A5),
                  minimumSize: Size.fromHeight(compact ? 38 : 42),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(compact ? 12 : 14),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _monthGrid({
    required List<_CalendarDay?> days,
    bool compact = false,
  }) {
    return LayoutBuilder(
      builder: (context, gridConstraints) {
        final mainGap = compact ? 2.0 : 3.0;
        final crossGap = compact ? 3.0 : 6.0;
        final padH = compact ? 4.0 : 8.0;
        const padTop = 0.0;
        final rows = (days.length / 7).ceil().clamp(1, 12);
        final innerW = gridConstraints.maxWidth - padH * 2;
        final innerH = gridConstraints.maxHeight - padTop;
        if (innerW <= 8 || innerH <= 8) {
          return const SizedBox.shrink();
        }
        final cellH = (innerH - mainGap * (rows - 1)) / rows;

        return Padding(
          padding: EdgeInsets.fromLTRB(padH, padTop, padH, 0),
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
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
              final isSelected = d.year == _selectedDate.year &&
                  d.month == _selectedDate.month &&
                  d.day == _selectedDate.day;
              final now = DateTime.now();
              final isToday = d.year == now.year &&
                  d.month == now.month &&
                  d.day == now.day;
              return _DayCell(
                day: day,
                selected: isSelected,
                today: isToday,
                compact: compact,
                onTap: () => _pickDay(day),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final y = _monthCursor.year;
    final m = _monthCursor.month;
    final monthLabel = _formatThaiMonthYear(_monthCursor);
    final phonePortrait = _phonePortrait(context);
    final bottomFabClearance =
        MediaQuery.of(context).padding.bottom + (phonePortrait ? 36.0 : 42.0);

    if (widget.embedded) {
      return Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(phonePortrait ? 16 : 22),
        clipBehavior: Clip.antiAlias,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(phonePortrait ? 16 : 22),
            border: Border.all(color: const Color(0xFFE7ECF3)),
          ),
          child: _calendarBody(bottomClearance: 0),
        ),
      );
    }

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
          toolbarHeight: phonePortrait ? 48 : kToolbarHeight,
          titleSpacing: phonePortrait ? 8 : 12,
          centerTitle: false,
          title: _monthNavRow(monthLabel, y, m, compact: phonePortrait),
        ),
        body: _calendarBody(bottomClearance: bottomFabClearance),
        floatingActionButton: phonePortrait
            ? FloatingActionButton(
                onPressed: _openCreateEntrySheet,
                tooltip: 'เพิ่มวันหยุด/ลา',
                child: const Icon(Icons.add),
              )
            : FloatingActionButton.extended(
                onPressed: _openCreateEntrySheet,
                icon: const Icon(Icons.add),
                label: Text('เพิ่มวันหยุด/ลา', style: GoogleFonts.kanit()),
              ),
      ),
    );
  }

  Widget _legendChip({
    required Color color,
    required String label,
    bool compact = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 1 : 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: GoogleFonts.kanit(
          color: color,
          fontSize: compact ? 10.5 : 11.5,
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
    if (hasWeeklyOff) {
      final moved = weeklyOffMoveReason != null &&
          weeklyOffMoveReason!.trim().isNotEmpty;
      tags.add(
        _CalendarDayTag(
          color: const Color(0xFFD32F2F),
          label: moved ? 'หยุดสัปดาห์ (เลื่อน)' : 'หยุดสัปดาห์',
          icon: Icons.beach_access_outlined,
        ),
      );
    }
    if (userHolidayDescriptions.isNotEmpty) {
      final n = userHolidayDescriptions.length;
      tags.add(
        _CalendarDayTag(
          color: const Color(0xFFE57373),
          label: n > 1 ? 'นัด/หยุด · $n' : 'นัด/หยุด',
          icon: Icons.event_outlined,
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
    if (hasWeeklyOff) return const Color(0xFFD32F2F);
    if (userHolidayDescriptions.isNotEmpty) {
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
    this.compact = false,
  });
  final _CalendarDay day;
  final bool selected;
  final bool today;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final accent = day.primaryAccentColor();
    final tags = day.cellTags(max: compact ? 1 : 2);
    final dots = day.markerDotColors(max: compact ? 3 : 4);
    final hasActivity = day.activityCount > 0;
    final showTags = hasActivity && tags.isNotEmpty;
    final weeklyTint = day.hasWeeklyOff;

    final borderColor = selected
        ? const Color(0xFF1E88E5)
        : today
        ? const Color(0xFF90A4AE)
        : const Color(0xFFE8ECF0);
    final borderW = selected ? (compact ? 1.5 : 1.8) : 1.0;
    final radius = compact ? 8.0 : 10.0;
    final accentW = compact ? 2.0 : 3.0;
    final dayFs = compact ? (today ? 11.0 : 13.0) : (today ? 13.0 : 16.0);
    final todayBox = compact ? 20.0 : 26.0;
    final pad = compact
        ? const EdgeInsets.fromLTRB(3, 3, 3, 2)
        : const EdgeInsets.fromLTRB(5, 5, 5, 4);
    final dotSize = compact ? 4.0 : 5.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFFF0F7FF)
                : weeklyTint
                    ? const Color(0xFFFFF5F5)
                    : Colors.white,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(width: borderW, color: borderColor),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: const Color(0xFF1E88E5).withValues(alpha: 0.12),
                      blurRadius: compact ? 4 : 6,
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
                  width: accentW,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.horizontal(
                      left: Radius.circular(radius),
                    ),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: pad,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (today)
                            Container(
                              width: todayBox,
                              height: todayBox,
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
                                  fontSize: dayFs,
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
                                fontSize: dayFs,
                                height: 1,
                                color: selected
                                    ? const Color(0xFF1565C0)
                                    : const Color(0xFF37474F),
                              ),
                            ),
                          const Spacer(),
                          if (dots.isNotEmpty && !compact)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final c in dots)
                                  Container(
                                    width: dotSize,
                                    height: dotSize,
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
                      if (compact && showTags) ...[
                        const SizedBox(height: 2),
                        _CalendarTagChip(tag: tags.first, compact: true),
                      ] else if (compact && dots.isNotEmpty) ...[
                        const Spacer(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (final c in dots)
                              Container(
                                width: dotSize,
                                height: dotSize,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: c,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                      ] else if (showTags) ...[
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

class _CalendarWeekStrip extends StatelessWidget {
  const _CalendarWeekStrip({
    required this.monthDays,
    required this.selectedDate,
    required this.onSelectDate,
    this.compact = false,
  });

  final List<_CalendarDay?> monthDays;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onSelectDate;
  final bool compact;

  _CalendarDay? _dayFor(DateTime d) {
    final key =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    for (final cell in monthDays) {
      if (cell != null && cell.dateStr == key) return cell;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final monday =
        selectedDate.subtract(Duration(days: selectedDate.weekday - 1));
    const labels = ['จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส', 'อา'];

    return Container(
      padding: EdgeInsets.all(compact ? 8 : 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF8FAFC), Color(0xFFEFF6FF)],
        ),
        borderRadius: BorderRadius.circular(compact ? 12 : 14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.date_range_rounded,
                size: compact ? 16 : 18,
                color: const Color(0xFF2563EB),
              ),
              const SizedBox(width: 6),
              Text(
                'สัปดาห์นี้',
                style: GoogleFonts.kanit(
                  fontWeight: FontWeight.w800,
                  fontSize: compact ? 12.5 : 13.5,
                  color: const Color(0xFF1E3A5F),
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 6 : 8),
          Row(
            children: List.generate(7, (i) {
              final d = monday.add(Duration(days: i));
              final cell = _dayFor(d);
              final selected = d.year == selectedDate.year &&
                  d.month == selectedDate.month &&
                  d.day == selectedDate.day;
              final today = _isToday(d);
              final weeklyOff = cell?.hasWeeklyOff ?? false;
              final leaveN = cell?.leaveNames.length ?? 0;
              final bg = selected
                  ? const Color(0xFF2563EB)
                  : weeklyOff
                      ? const Color(0xFFFFEBEE)
                      : Colors.white;
              final border = selected
                  ? const Color(0xFF1D4ED8)
                  : weeklyOff
                      ? const Color(0xFFEF9A9A)
                      : const Color(0xFFE2E8F0);

              return Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: compact ? 2 : 3),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(compact ? 10 : 12),
                      onTap: () => onSelectDate(d),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: EdgeInsets.symmetric(
                          vertical: compact ? 6 : 8,
                        ),
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius:
                              BorderRadius.circular(compact ? 10 : 12),
                          border: Border.all(color: border, width: 1.2),
                          boxShadow: selected
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF2563EB)
                                        .withValues(alpha: 0.22),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ]
                              : null,
                        ),
                        child: Column(
                          children: [
                            Text(
                              labels[i],
                              style: GoogleFonts.kanit(
                                fontSize: compact ? 9.5 : 10.5,
                                fontWeight: FontWeight.w700,
                                color: selected
                                    ? Colors.white70
                                    : const Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${d.day}',
                              style: GoogleFonts.kanit(
                                fontSize: compact ? 14 : 16,
                                fontWeight: FontWeight.w800,
                                color: selected
                                    ? Colors.white
                                    : today
                                        ? const Color(0xFF0D47A1)
                                        : const Color(0xFF1E293B),
                              ),
                            ),
                            SizedBox(height: compact ? 3 : 4),
                            if (weeklyOff)
                              Icon(
                                Icons.beach_access_rounded,
                                size: compact ? 12 : 14,
                                color: selected
                                    ? Colors.white
                                    : const Color(0xFFD32F2F),
                              )
                            else if (leaveN > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? Colors.white.withValues(alpha: 0.22)
                                      : const Color(0xFFFFB74D)
                                          .withValues(alpha: 0.22),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  'ลา$leaveN',
                                  style: GoogleFonts.kanit(
                                    fontSize: compact ? 8.5 : 9.5,
                                    fontWeight: FontWeight.w800,
                                    color: selected
                                        ? Colors.white
                                        : const Color(0xFFE65100),
                                  ),
                                ),
                              )
                            else
                              SizedBox(height: compact ? 12 : 14),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  bool _isToday(DateTime d) {
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }
}

class _CalendarSelectedDayPanel extends StatelessWidget {
  const _CalendarSelectedDayPanel({
    required this.day,
    required this.onOpenDetails,
    this.compact = false,
  });

  final _CalendarDay? day;
  final VoidCallback onOpenDetails;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (day == null) return const SizedBox.shrink();

    final leave = day!.leaveDetails;
    final weekly = day!.weeklyOffLine;
    final moved = day!.weeklyOffMoveReason?.trim() ?? '';
    final empty = leave.isEmpty && weekly == null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(compact ? 12 : 14),
        onTap: onOpenDetails,
        child: Container(
          padding: EdgeInsets.all(compact ? 10 : 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(compact ? 12 : 14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'สรุปวันที่เลือก',
                    style: GoogleFonts.kanit(
                      fontWeight: FontWeight.w800,
                      fontSize: compact ? 13 : 14,
                      color: const Color(0xFF1E293B),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.open_in_new_rounded,
                    size: compact ? 16 : 18,
                    color: const Color(0xFF64748B),
                  ),
                ],
              ),
              if (weekly != null) ...[
                SizedBox(height: compact ? 8 : 10),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 10 : 12,
                    vertical: compact ? 8 : 10,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFEBEE), Color(0xFFFFF5F5)],
                    ),
                    borderRadius: BorderRadius.circular(compact ? 10 : 12),
                    border: Border.all(
                      color: const Color(0xFFEF9A9A).withValues(alpha: 0.7),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD32F2F).withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.beach_access_rounded,
                          size: compact ? 18 : 20,
                          color: const Color(0xFFD32F2F),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'วันหยุดรายสัปดาห์',
                              style: GoogleFonts.kanit(
                                fontWeight: FontWeight.w800,
                                fontSize: compact ? 12.5 : 13.5,
                                color: const Color(0xFFB71C1C),
                              ),
                            ),
                            Text(
                              weekly,
                              style: GoogleFonts.kanit(
                                fontSize: compact ? 11.5 : 12.5,
                                height: 1.3,
                                color: const Color(0xFF5D4037),
                              ),
                            ),
                            if (moved.isNotEmpty)
                              Text(
                                'เหตุผลเลื่อน: $moved',
                                style: GoogleFonts.kanit(
                                  fontSize: compact ? 10.5 : 11.5,
                                  color: const Color(0xFF78909C),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (leave.isNotEmpty) ...[
                SizedBox(height: compact ? 8 : 10),
                Text(
                  'คนลางาน (${leave.length})',
                  style: GoogleFonts.kanit(
                    fontWeight: FontWeight.w700,
                    fontSize: compact ? 12 : 13,
                    color: const Color(0xFFE65100),
                  ),
                ),
                SizedBox(height: compact ? 6 : 8),
                Wrap(
                  spacing: compact ? 6 : 8,
                  runSpacing: compact ? 6 : 8,
                  children: [
                    for (final item in leave.take(6))
                      _LeaveNameChip(
                        label: item.headline,
                        compact: compact,
                      ),
                    if (leave.length > 6)
                      _LeaveNameChip(
                        label: '+${leave.length - 6}',
                        compact: compact,
                        muted: true,
                      ),
                  ],
                ),
              ],
              if (empty)
                Padding(
                  padding: EdgeInsets.only(top: compact ? 6 : 8),
                  child: Text(
                    'ไม่มีลางานหรือหยุดสัปดาห์ — แตะเพื่อดูรายละเอียดวัน',
                    style: GoogleFonts.kanit(
                      fontSize: compact ? 11.5 : 12.5,
                      color: const Color(0xFF94A3B8),
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

class _LeaveNameChip extends StatelessWidget {
  const _LeaveNameChip({
    required this.label,
    this.compact = false,
    this.muted = false,
  });

  final String label;
  final bool compact;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final initial = _calendarFirstGlyph(label);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: muted ? const Color(0xFFF1F5F9) : const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: muted ? const Color(0xFFCBD5E1) : const Color(0xFFFFCC80),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!muted)
            Container(
              width: compact ? 20 : 22,
              height: compact ? 20 : 22,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFFFFB74D), Color(0xFFF57C00)],
                ),
              ),
              child: Text(
                initial,
                style: GoogleFonts.kanit(
                  fontSize: compact ? 10 : 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          if (!muted) const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.kanit(
              fontSize: compact ? 11.5 : 12.5,
              fontWeight: FontWeight.w700,
              color: muted ? const Color(0xFF64748B) : const Color(0xFF5D4037),
            ),
          ),
        ],
      ),
    );
  }
}
