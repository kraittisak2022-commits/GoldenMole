import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/app_transaction.dart';
import '../models/employee.dart';
import '../services/employee_service.dart';
import '../services/transaction_service.dart';
import '../utils/thai_holidays.dart';
import '../widgets/page_loading_view.dart';

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

  Future<_CalendarPayload> _load() async {
    final transactions = await widget.transactionService.fetchTransactions();
    final employees = await widget.employeeService.fetchEmployees();
    return _CalendarPayload(transactions: transactions, employees: employees);
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

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
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${_thaiWeekdayLong(_selectedDate)} • ${_formatDateThai(_selectedDate)}',
                style: GoogleFonts.kanit(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              if (day.holidays.isNotEmpty)
                _infoBlock(
                  title: 'วันหยุด',
                  color: const Color(0xFFE57373),
                  lines: day.holidays,
                ),
              if (day.leaveNames.isNotEmpty)
                _infoBlock(
                  title: 'รายการลา',
                  color: const Color(0xFFFFB74D),
                  lines: day.leaveNames,
                ),
              if (day.holidays.isEmpty && day.leaveNames.isEmpty)
                Text(
                  'ไม่มีข้อมูลวันหยุดหรือการลาในวันนี้',
                  style: GoogleFonts.kanit(color: Colors.black54),
                ),
              const SizedBox(height: 10),
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
                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    6,
                    16,
                    MediaQuery.of(context).viewInsets.bottom + 20,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
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
                          segments: const [
                            ButtonSegment(
                              value: 'Holiday',
                              label: Text('วันหยุด/นัดหมาย'),
                              icon: Icon(Icons.event),
                            ),
                            ButtonSegment(
                              value: 'Leave',
                              label: Text('ลางาน'),
                              icon: Icon(Icons.badge_outlined),
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

  Widget _infoBlock({
    required String title,
    required Color color,
    required List<String> lines,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.kanit(color: color, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          ...lines.map(
            (e) =>
                Text('• $e', style: GoogleFonts.kanit(color: Colors.black87)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final y = _monthCursor.year;
    final m = _monthCursor.month;
    final monthLabel = _formatThaiMonthYear(_monthCursor);

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! > 550) {
          Navigator.maybePop(context);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F4FA),
        appBar: AppBar(
          title: Text(
            'ปฏิทิน',
            style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
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
            );
            final monthHolidayCount = days
                .whereType<_CalendarDay>()
                .where((d) => d.holidays.isNotEmpty)
                .length;
            final monthLeaveCount = days.whereType<_CalendarDay>().fold<int>(
              0,
              (sum, d) => sum + d.leaveNames.length,
            );
            final selectedLabel =
                '${_thaiWeekdayLong(_selectedDate)} ${_formatDateThai(_selectedDate)}';
            return Column(
              children: [
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF203245), Color(0xFF2A415C)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              monthLabel,
                              style: GoogleFonts.kanit(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'เดือนก่อน',
                            onPressed: () => setState(() {
                              _monthCursor = DateTime(y, m - 1, 1);
                            }),
                            icon: const Icon(
                              Icons.chevron_left,
                              color: Colors.white,
                            ),
                          ),
                          IconButton(
                            tooltip: 'เดือนถัดไป',
                            onPressed: () => setState(() {
                              _monthCursor = DateTime(y, m + 1, 1);
                            }),
                            icon: const Icon(
                              Icons.chevron_right,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'วันที่เลือก: $selectedLabel',
                        style: GoogleFonts.kanit(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _miniStat(
                            icon: Icons.celebration_outlined,
                            label: 'วันหยุด',
                            value: '$monthHolidayCount วัน',
                          ),
                          _miniStat(
                            icon: Icons.badge_outlined,
                            label: 'ลางาน',
                            value: '$monthLeaveCount คน',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Row(
                    children: [
                      _legendChip(
                        color: const Color(0xFFE57373),
                        label: 'วันหยุด',
                      ),
                      const SizedBox(width: 8),
                      _legendChip(
                        color: const Color(0xFFFFB74D),
                        label: 'ลางาน',
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _openCreateEntrySheet,
                        icon: const Icon(Icons.add_circle_outline, size: 18),
                        label: Text('เพิ่มข้อมูล', style: GoogleFonts.kanit()),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      for (final d in const [
                        'อา',
                        'จ',
                        'อ',
                        'พ',
                        'พฤ',
                        'ศ',
                        'ส',
                      ])
                        Expanded(
                          child: Center(
                            child: Text(
                              d,
                              style: GoogleFonts.kanit(
                                fontWeight: FontWeight.w700,
                                color: Colors.black54,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6,
                          childAspectRatio: 0.75,
                        ),
                    itemCount: days.length,
                    itemBuilder: (context, index) {
                      final day = days[index];
                      if (day == null) return const SizedBox.shrink();
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

  Widget _miniStat({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            '$label $value',
            style: GoogleFonts.kanit(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendChip({required Color color, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: GoogleFonts.kanit(
          color: color,
          fontSize: 12.5,
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
      final holidays = <String>[
        if (autoHoliday != null) autoHoliday.name,
        ...calendarRows
            .where((t) => (t.subCategory ?? '').toLowerCase() == 'holiday')
            .map((t) => t.description),
      ];

      final leaveRows = dayTx.where((t) {
        final laborStatus = (t.laborStatus ?? '').toLowerCase();
        return t.category == 'Labor' &&
            (laborStatus == 'leave' ||
                laborStatus == 'sick' ||
                laborStatus == 'personal');
      }).toList();
      final leaveEmpIds = <String>{};
      for (final row in leaveRows) {
        leaveEmpIds.addAll(row.employeeIds);
      }
      final leaveNames = leaveEmpIds.map((id) {
        final emp = employees
            .where((e) => e.id == id)
            .cast<Employee?>()
            .firstWhere((e) => e != null, orElse: () => null);
        if (emp == null) return 'ไม่ทราบชื่อ';
        return emp.nickname.isNotEmpty ? emp.nickname : emp.name;
      }).toList();

      result.add(
        _CalendarDay(
          day: d,
          dateStr: dateStr,
          holidays: holidays,
          leaveNames: leaveNames,
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
  const _CalendarPayload({required this.transactions, required this.employees});
  final List<AppTransaction> transactions;
  final List<Employee> employees;
}

class _CalendarDay {
  const _CalendarDay({
    required this.day,
    required this.dateStr,
    required this.holidays,
    required this.leaveNames,
  });

  final int day;
  final String dateStr;
  final List<String> holidays;
  final List<String> leaveNames;
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
    final isHoliday = day.holidays.isNotEmpty;
    final hasLeave = day.leaveNames.isNotEmpty;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAF4FF) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            width: selected ? 1.5 : 1,
            color: selected
                ? const Color(0xFF1E88E5)
                : today
                ? const Color(0xFF90CAF9)
                : isHoliday
                ? const Color(0xFFE57373)
                : hasLeave
                ? const Color(0xFFFFB74D)
                : Colors.grey.shade300,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${day.day}',
              style: GoogleFonts.kanit(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: selected ? const Color(0xFF1565C0) : Colors.black87,
              ),
            ),
            const SizedBox(height: 2),
            if (isHoliday)
              Text(
                'วันหยุด',
                style: GoogleFonts.kanit(
                  fontSize: 10,
                  color: Colors.red.shade600,
                ),
              ),
            if (hasLeave)
              Text(
                'ลา ${day.leaveNames.length}',
                style: GoogleFonts.kanit(
                  fontSize: 10,
                  color: Colors.orange.shade700,
                ),
              ),
            const SizedBox(height: 2),
            if (day.leaveNames.isNotEmpty)
              Expanded(
                child: Text(
                  day.leaveNames.take(2).join(', '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.kanit(fontSize: 9, color: Colors.black54),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
