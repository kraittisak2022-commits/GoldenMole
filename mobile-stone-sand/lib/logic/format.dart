import 'package:intl/intl.dart';

final _moneyFmt = NumberFormat('#,##0.00', 'en_US');
final _intFmt = NumberFormat('#,##0.##', 'en_US');

String formatMoney(num? n) => _moneyFmt.format(n ?? 0);
String formatNumber(num? n) => _intFmt.format(n ?? 0);
String formatBaht(num? n) => '${_intFmt.format(n ?? 0)} บาท';

const thMonthsShort = [
  'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', //
  'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.',
];
const thMonths = [
  'มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน', //
  'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม',
];
const _thWeekdays = ['อาทิตย์', 'จันทร์', 'อังคาร', 'พุธ', 'พฤหัสบดี', 'ศุกร์', 'เสาร์'];

final _isoDateRe = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

/// Plain YYYY-MM-DD is a local calendar date, not UTC midnight.
DateTime? toDate(Object? value) {
  if (value is DateTime) return value;
  if (value == null) return null;
  final s = '$value';
  if (s.isEmpty) return null;
  final m = _isoDateRe.firstMatch(s);
  if (m != null) {
    return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }
  return DateTime.tryParse(s)?.toLocal();
}

String _two(int v) => v.toString().padLeft(2, '0');

/// dd/mm/yyyy in the Buddhist year (2569).
String formatDateTh(Object? value) {
  final d = toDate(value);
  if (d == null) return '-';
  return '${_two(d.day)}/${_two(d.month)}/${d.year + 543}';
}

/// e.g. 8 ต.ค. 69
String formatDateShort(Object? value) {
  final d = toDate(value);
  if (d == null) return '-';
  final yy = (d.year + 543).toString();
  return '${d.day} ${thMonthsShort[d.month - 1]} ${yy.substring(yy.length - 2)}';
}

String formatDateTime(Object? value) {
  final d = toDate(value);
  if (d == null) return '-';
  return '${formatDateShort(d)} ${_two(d.hour)}:${_two(d.minute)} น.';
}

/// Local YYYY-MM-DD.
String toIsoDate([DateTime? d]) {
  final v = d ?? DateTime.now();
  return '${v.year.toString().padLeft(4, '0')}-${_two(v.month)}-${_two(v.day)}';
}

String shiftIsoDate(String iso, int days) {
  final d = toDate(iso) ?? DateTime.now();
  return toIsoDate(DateTime(d.year, d.month, d.day + days));
}

({String from, String to}) monthRange(String iso) {
  final d = toDate(iso) ?? DateTime.now();
  return (
    from: toIsoDate(DateTime(d.year, d.month, 1)),
    to: toIsoDate(DateTime(d.year, d.month + 1, 0)),
  );
}

/// e.g. พฤหัสบดี 8 ตุลาคม 2569
String formatDateLongTh(Object? value) {
  final d = toDate(value);
  if (d == null) return '-';
  return '${_thWeekdays[d.weekday % 7]} ${d.day} ${thMonths[d.month - 1]} ${d.year + 543}';
}

String digitsOnly(String phone) => phone.replaceAll(RegExp(r'\D'), '');

/// 0931234567 → 093-123-4567
String formatPhone(String phone) {
  final d = digitsOnly(phone);
  if (d.length == 10) return '${d.substring(0, 3)}-${d.substring(3, 6)}-${d.substring(6)}';
  if (d.length == 9) return '${d.substring(0, 2)}-${d.substring(2, 5)}-${d.substring(5)}';
  return phone.trim();
}

enum DocKind {
  delivery('ใบส่งของ', 'DELIVERY NOTE'),
  receipt('ใบเสร็จรับเงิน', 'RECEIPT'),
  statement('ใบวางบิล / ใบแจ้งยอด', 'BILLING STATEMENT');

  const DocKind(this.th, this.en);
  final String th;
  final String en;
}

final _docNoRe = RegExp(r'^(DO|TS|RE|BL)(\d{2})(\d{2})-(\d{4,})$');

({DocKind kind, int year, int month, int seq})? parseDocNo(String docNo) {
  final m = _docNoRe.firstMatch(docNo.trim());
  if (m == null) return null;
  final month = int.parse(m[3]!);
  if (month < 1 || month > 12) return null;
  final kind = m[1] == 'DO' || m[1] == 'TS'
      ? DocKind.delivery
      : m[1] == 'RE'
          ? DocKind.receipt
          : DocKind.statement;
  return (kind: kind, year: 2000 + int.parse(m[2]!), month: month, seq: int.parse(m[4]!));
}

/// How the delivery fee adds up, e.g. "40 × 10 คิว + 100 × 2 เที่ยว + 50".
String deliveryFeeFormula({
  required num feePerCubic,
  required num cubic,
  required num feePerTrip,
  required int trips,
  required num remoteSurcharge,
}) =>
    [
      if (feePerCubic > 0) '${formatNumber(feePerCubic)} × ${formatNumber(cubic)} คิว',
      if (feePerTrip > 0 || !(feePerCubic > 0)) '${formatNumber(feePerTrip)} × $trips เที่ยว',
      if (remoteSurcharge > 0) formatNumber(remoteSurcharge),
    ].join(' + ');

String googleMapsUrl(double lat, double lng) =>
    'https://www.google.com/maps?q=${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';

const publicAppUrl = 'https://order.goldenmole.pro';

/// Page the driver opens from LINE to confirm delivery and report the cash collected.
String driverJobUrl(String token) => '$publicAppUrl/d/$token';
