import 'format.dart';

const thWeekdaysShort = ['อา', 'จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส'];

/// [month] is 1–12.
typedef YearMonth = ({int year, int month});

YearMonth yearMonthOf(String iso) {
  final p = iso.split('-');
  return (year: int.parse(p[0]), month: int.parse(p[1]));
}

YearMonth shiftMonth(YearMonth ym, int by) {
  final d = DateTime(ym.year, ym.month + by);
  return (year: d.year, month: d.month);
}

bool sameMonth(String iso, YearMonth ym) => yearMonthOf(iso) == ym;

/// Six weeks of ISO dates, Sunday first, that cover the month.
List<String> monthGrid(YearMonth ym) {
  final lead = DateTime(ym.year, ym.month).weekday % 7;
  return List.generate(42, (i) => toIsoDate(DateTime(ym.year, ym.month, 1 - lead + i)));
}
