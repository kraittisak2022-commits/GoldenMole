import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Same rules as the web `passwordAuth.ts`: stored as `sha256$<hex>`, `sha256:<hex>`, bare hex,
/// or legacy plain text.
const _hashPrefix = r'sha256$';
const _hashPrefixAlt = 'sha256:';

final _hexOnly = RegExp(r'^[a-f0-9]{64}$', caseSensitive: false);
final _hexAny = RegExp(r'([a-f0-9]{64})', caseSensitive: false);

String? _extractSha256Hex(String raw) {
  final s = raw.trim();
  if (_hexOnly.hasMatch(s)) return s;
  return _hexAny.firstMatch(s)?.group(1);
}

String sha256Hex(String plain) => sha256.convert(utf8.encode(plain)).toString();

bool _timingSafeEqual(String a, String b) {
  if (a.length != b.length) return false;
  var out = 0;
  for (var i = 0; i < a.length; i++) {
    out |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return out == 0;
}

bool isPasswordHashedFormat(String? stored) {
  if (stored == null || stored.isEmpty) return false;
  final s = stored.trim();
  if (s.startsWith(_hashPrefix) && s.length > _hashPrefix.length + 32) return true;
  if (s.startsWith(_hashPrefixAlt) && s.length > _hashPrefixAlt.length + 32) return true;
  return _extractSha256Hex(s) != null;
}

bool verifyStoredPassword(String stored, String inputPlain) {
  if (stored.isEmpty) return false;
  final s = stored.trim();
  if (isPasswordHashedFormat(s)) {
    final expectedRaw = s.startsWith(_hashPrefix)
        ? s.substring(_hashPrefix.length)
        : s.startsWith(_hashPrefixAlt)
            ? s.substring(_hashPrefixAlt.length)
            : (_extractSha256Hex(s) ?? s);
    final expected = (_extractSha256Hex(expectedRaw) ?? expectedRaw).toLowerCase();
    if (_timingSafeEqual(expected, sha256Hex(inputPlain))) return true;
    final trimmed = inputPlain.trim();
    if (trimmed != inputPlain && _timingSafeEqual(expected, sha256Hex(trimmed))) return true;
    return false;
  }
  if (_timingSafeEqual(s, inputPlain)) return true;
  return _timingSafeEqual(s, inputPlain.trim());
}
