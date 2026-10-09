final _splitRe = RegExp('[,\\n،;]+');
final _spaceRe = RegExp(r'\s+');

/// "เสี่ยบาส, บาส\nเฮียบาส" → ['เสี่ยบาส', 'บาส', 'เฮียบาส'] (trimmed, no blanks or repeats).
List<String> parseAliases(String text) {
  final seen = <String>{};
  final out = <String>[];
  for (final raw in text.split(_splitRe)) {
    final name = raw.trim().replaceAll(_spaceRe, ' ');
    final key = name.toLowerCase();
    if (name.isEmpty || seen.contains(key)) continue;
    seen.add(key);
    out.add(name);
  }
  return out;
}

String formatAliases(List<String> aliases) => aliases.join(', ');

/// Alias that matched the query, so the result can show why it came up.
String? matchedAlias(String name, List<String> aliases, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty || name.toLowerCase().contains(q)) return null;
  for (final a in aliases) {
    if (a.toLowerCase().contains(q)) return a;
  }
  return null;
}

bool matchesCustomer(String name, List<String> aliases, String phone, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final digits = q.replaceAll(RegExp(r'\D'), '');
  return name.toLowerCase().contains(q) ||
      aliases.any((a) => a.toLowerCase().contains(q)) ||
      (digits.length >= 3 && phone.contains(digits));
}
