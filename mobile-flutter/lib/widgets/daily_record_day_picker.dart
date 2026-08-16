import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/app_transaction.dart';
import '../utils/daily_module_transactions.dart';

/// เปิดปฏิทินเลือกวันสำหรับหน้าบันทึกประจำวัน
/// จุดเขียวอมฟ้า = เช็คชื่อ · ฟ้า = รถดรัม · เหลือง = น้ำมัน · ส้ม = เหตุการณ์
Future<DateTime?> showDailyRecordDayPicker({
  required BuildContext context,
  required DateTime initialDate,
  required Iterable<AppTransaction> transactions,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  final first = firstDate ?? DateTime(2020);
  final last = lastDate ?? DateTime.now().add(const Duration(days: 365));
  return showDialog<DateTime>(
    context: context,
    builder: (ctx) => _DailyRecordDayPickerDialog(
      initialDate: initialDate,
      transactions: transactions,
      firstDate: first,
      lastDate: last,
    ),
  );
}

class _DailyRecordDayPickerDialog extends StatefulWidget {
  const _DailyRecordDayPickerDialog({
    required this.initialDate,
    required this.transactions,
    required this.firstDate,
    required this.lastDate,
  });

  final DateTime initialDate;
  final Iterable<AppTransaction> transactions;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<_DailyRecordDayPickerDialog> createState() =>
      _DailyRecordDayPickerDialogState();
}

class _DailyRecordDayPickerDialogState
    extends State<_DailyRecordDayPickerDialog> {
  static const _attendanceDot = Color(0xFF2FB6A6);
  static const _tripDot = Color(0xFF1565C0);
  static const _fuelDot = Color(0xFFFFAB00);
  static const _eventDot = Color(0xFFFF7A1A);
  static const _teal = Color(0xFF0D98A5);

  late DateTime _month;
  late DateTime _selected;
  late Map<String, DailyRecordDayMark> _marks;

  @override
  void initState() {
    super.initState();
    final d = DateTime(
      widget.initialDate.year,
      widget.initialDate.month,
      widget.initialDate.day,
    );
    _selected = d;
    _month = DateTime(d.year, d.month);
    _reloadMarks();
  }

  void _reloadMarks() {
    _marks = dailyRecordDayMarksForMonth(
      year: _month.year,
      month: _month.month,
      transactions: widget.transactions,
    );
  }

  String _ymd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  String _formatBuddhistShort(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year + 543}';
  }

  String _monthTitle(DateTime d) {
    const months = [
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
    return '${months[d.month - 1]} ${d.year + 543}';
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _inRange(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    final first = DateTime(
      widget.firstDate.year,
      widget.firstDate.month,
      widget.firstDate.day,
    );
    final last = DateTime(
      widget.lastDate.year,
      widget.lastDate.month,
      widget.lastDate.day,
    );
    return !day.isBefore(first) && !day.isAfter(last);
  }

  void _shiftMonth(int delta) {
    final next = DateTime(_month.year, _month.month + delta);
    final firstMonth = DateTime(widget.firstDate.year, widget.firstDate.month);
    final lastMonth = DateTime(widget.lastDate.year, widget.lastDate.month);
    if (next.isBefore(firstMonth) || next.isAfter(lastMonth)) return;
    setState(() {
      _month = next;
      _reloadMarks();
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedMark = _marks[_ymd(_selected)];
    final summary = selectedMark?.label ?? 'ยังไม่มีบันทึกประจำวัน';
    final today = DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);

    final firstWeekday = DateTime(_month.year, _month.month, 1).weekday; // 1=Mon
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leading = firstWeekday - 1;
    final cells = <Widget>[];
    for (var i = 0; i < leading; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_month.year, _month.month, day);
      final enabled = _inRange(date);
      final mark = _marks[_ymd(date)];
      final selected = _sameDay(date, _selected);
      final isToday = _sameDay(date, todayDay);
      cells.add(
        _DailyRecordDayCell(
          day: day,
          enabled: enabled,
          selected: selected,
          isToday: isToday,
          hasAttendance: mark?.hasAttendance ?? false,
          hasTrips: mark?.hasTrips ?? false,
          hasFuel: mark?.hasFuel ?? false,
          hasEvent: mark?.hasEvent ?? false,
          attendanceColor: _attendanceDot,
          tripColor: _tripDot,
          fuelColor: _fuelDot,
          eventColor: _eventDot,
          onTap: enabled ? () => setState(() => _selected = date) : null,
        ),
      );
    }

    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      title: Text(
        'เลือกวันที่บันทึกประจำวัน',
        style: GoogleFonts.kanit(
          fontWeight: FontWeight.w800,
          fontSize: 20,
          color: const Color(0xFF1A2433),
        ),
      ),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => _shiftMonth(-1),
                  icon: const Icon(Icons.chevron_left_rounded),
                  color: _teal,
                ),
                Expanded(
                  child: Text(
                    _monthTitle(_month),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.kanit(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      color: const Color(0xFF1A2433),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _shiftMonth(1),
                  icon: const Icon(Icons.chevron_right_rounded),
                  color: _teal,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                for (final w in const ['จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส', 'อา'])
                  Expanded(
                    child: Text(
                      w,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.kanit(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              children: cells,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: const [
                _LegendDot(color: _attendanceDot, label: 'เช็คชื่อ'),
                _LegendDot(color: _tripDot, label: 'รถดรัม'),
                _LegendDot(color: _fuelDot, label: 'น้ำมัน'),
                _LegendDot(color: _eventDot, label: 'เหตุการณ์'),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F9FA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFB6E0E6)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'วันที่ ${_formatBuddhistShort(_selected)}',
                    style: GoogleFonts.kanit(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: const Color(0xFF0A7A88),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    summary,
                    style: GoogleFonts.kanit(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                      color: const Color(0xFF1A2433),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'ยกเลิก',
            style: GoogleFonts.kanit(fontWeight: FontWeight.w700),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          style: FilledButton.styleFrom(backgroundColor: _teal),
          child: Text(
            'ตกลง',
            style: GoogleFonts.kanit(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.kanit(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF4A5A70),
          ),
        ),
      ],
    );
  }
}

class _DailyRecordDayCell extends StatelessWidget {
  const _DailyRecordDayCell({
    required this.day,
    required this.enabled,
    required this.selected,
    required this.isToday,
    required this.hasAttendance,
    required this.hasTrips,
    required this.hasFuel,
    required this.hasEvent,
    required this.attendanceColor,
    required this.tripColor,
    required this.fuelColor,
    required this.eventColor,
    this.onTap,
  });

  final int day;
  final bool enabled;
  final bool selected;
  final bool isToday;
  final bool hasAttendance;
  final bool hasTrips;
  final bool hasFuel;
  final bool hasEvent;
  final Color attendanceColor;
  final Color tripColor;
  final Color fuelColor;
  final Color eventColor;
  final VoidCallback? onTap;

  Widget _dot(Color color) {
    return Container(
      width: 4.5,
      height: 4.5,
      decoration: BoxDecoration(
        color: selected ? Colors.white.withValues(alpha: 0.92) : color,
        shape: BoxShape.circle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? const Color(0xFF0D98A5)
        : (isToday ? const Color(0xFFE6F7F9) : Colors.transparent);
    final fg = selected
        ? Colors.white
        : (enabled ? const Color(0xFF1A2433) : const Color(0xFFB0B8C4));
    final dots = <Widget>[];
    if (hasAttendance) dots.add(_dot(attendanceColor));
    if (hasTrips) {
      if (dots.isNotEmpty) dots.add(const SizedBox(width: 2));
      dots.add(_dot(tripColor));
    }
    if (hasFuel) {
      if (dots.isNotEmpty) dots.add(const SizedBox(width: 2));
      dots.add(_dot(fuelColor));
    }
    if (hasEvent) {
      if (dots.isNotEmpty) dots.add(const SizedBox(width: 2));
      dots.add(_dot(eventColor));
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: isToday && !selected
                ? Border.all(color: const Color(0xFF0D98A5), width: 1.2)
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$day',
                style: GoogleFonts.kanit(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: fg,
                ),
              ),
              const SizedBox(height: 2),
              SizedBox(
                height: 5,
                child: dots.isEmpty
                    ? const SizedBox.shrink()
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: dots,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
