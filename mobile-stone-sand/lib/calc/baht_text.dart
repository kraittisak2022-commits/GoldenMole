const _digits = ['ศูนย์', 'หนึ่ง', 'สอง', 'สาม', 'สี่', 'ห้า', 'หก', 'เจ็ด', 'แปด', 'เก้า'];
const _places = ['', 'สิบ', 'ร้อย', 'พัน', 'หมื่น', 'แสน'];

/// Reads up to 6 digits (no leading zeros). [hasHigher] = a higher group (ล้าน) precedes it.
String _readGroup(String digits, bool hasHigher) {
  final sb = StringBuffer();
  final len = digits.length;
  for (var i = 0; i < len; i++) {
    final d = int.parse(digits[i]);
    final place = len - i - 1;
    if (d == 0) continue;
    if (place == 1 && d == 1) {
      sb.write('สิบ');
    } else if (place == 1 && d == 2) {
      sb.write('ยี่สิบ');
    } else if (place == 0 && d == 1 && (len > 1 || hasHigher)) {
      sb.write('เอ็ด');
    } else {
      sb.write(_digits[d] + _places[place]);
    }
  }
  return sb.toString();
}

String _readInteger(int n, [bool hasHigher = false]) {
  final s = n.toString();
  if (s.length <= 6) return _readGroup(s, hasHigher);
  final head = int.parse(s.substring(0, s.length - 6));
  final tail = int.parse(s.substring(s.length - 6));
  return '${_readInteger(head, hasHigher)}ล้าน${tail != 0 ? _readGroup(tail.toString(), true) : ''}';
}

/// Thai amount in words, e.g. 11875 → "หนึ่งหมื่นหนึ่งพันแปดร้อยเจ็ดสิบห้าบาทถ้วน".
String bahtText(num amount) {
  if (!amount.isFinite) return '';
  final negative = amount < 0;
  final totalSatang = (amount.abs() * 100 + 0.5).floor();
  final baht = totalSatang ~/ 100;
  final satang = totalSatang % 100;
  if (baht == 0 && satang == 0) return 'ศูนย์บาทถ้วน';
  var out = baht > 0 ? '${_readInteger(baht)}บาท' : '';
  out += satang > 0 ? '${_readInteger(satang)}สตางค์' : 'ถ้วน';
  return (negative ? 'ลบ' : '') + out;
}
