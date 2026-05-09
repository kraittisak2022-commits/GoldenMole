/// Normalize Thai mobile to 10 digits starting with 0.
String? normalizeThaiPhone(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final d = raw.replaceAll(RegExp(r'\D'), '');
  if (d.isEmpty) return null;
  if (d.length == 10 && d.startsWith('0')) return d;
  if (d.length == 11 && d.startsWith('66')) return '0${d.substring(2)}';
  if (d.length >= 10) {
    final tail = d.substring(d.length - 10);
    return tail.startsWith('0') ? tail : null;
  }
  return null;
}
