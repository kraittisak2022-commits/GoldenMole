import 'dart:typed_data';

/// Thai date/text helpers for the album screens — same output as apps/photo/src/lib/format.ts.

const kPhotoAlbumRootFolder = 'GoldenMole Photos';

const _thaiMonthsShort = [
  'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
  'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.',
];

const _thaiMonthsLong = [
  'มกราคม', 'กุมภาพันธ์', 'มีนาคม', 'เมษายน', 'พฤษภาคม', 'มิถุนายน',
  'กรกฎาคม', 'สิงหาคม', 'กันยายน', 'ตุลาคม', 'พฤศจิกายน', 'ธันวาคม',
];

const _thaiWeekdaysShort = ['จ.', 'อ.', 'พ.', 'พฤ.', 'ศ.', 'ส.', 'อา.'];

String _two(int v) => v.toString().padLeft(2, '0');

String photoYmd(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

DateTime? _parseYmd(String ymd) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(ymd);
  if (m == null) return null;
  return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

/// Wall-clock time in Thailand for an ISO timestamp.
DateTime? bangkokTime(String iso) {
  final t = DateTime.tryParse(iso);
  return t?.toUtc().add(const Duration(hours: 7));
}

/// `2026-10-06` → `6 ต.ค. 2569`
String formatPhotoAlbumDate(String ymd) {
  final d = _parseYmd(ymd);
  if (d == null) return ymd;
  return '${d.day} ${_thaiMonthsShort[d.month - 1]} ${d.year + 543}';
}

/// `2026-10-06` → `6 ตุลาคม 2569`
String formatPhotoAlbumDateLong(String ymd) {
  final d = _parseYmd(ymd);
  if (d == null) return ymd;
  return '${d.day} ${_thaiMonthsLong[d.month - 1]} ${d.year + 543}';
}

/// Day heading in the photo grid: `อ. 13 ต.ค. 2569`
String formatPhotoDayHeading(String iso) {
  final d = bangkokTime(iso);
  if (d == null) return '';
  return '${_thaiWeekdaysShort[d.weekday - 1]} ${d.day} ${_thaiMonthsShort[d.month - 1]} ${d.year + 543}';
}

/// `13 ต.ค. 2569 14:05`
String formatPhotoDateTime(String iso) {
  final d = bangkokTime(iso);
  if (d == null) return '';
  return '${d.day} ${_thaiMonthsShort[d.month - 1]} ${d.year + 543} ${_two(d.hour)}:${_two(d.minute)}';
}

/// Where the album folder lives in Drive: `GoldenMole Photos / 2569 / 10-ตุลาคม`
String photoDrivePathLabel(String ymd) {
  final d = _parseYmd(ymd);
  if (d == null) return kPhotoAlbumRootFolder;
  return '$kPhotoAlbumRootFolder / ${d.year + 543} / ${_two(d.month)}-${_thaiMonthsLong[d.month - 1]}';
}

String formatPhotoBytes(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round().clamp(1, 1024)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

/// `IMG_1.JPG` → (`IMG_1`, `.JPG`); a name without an extension keeps an empty one.
(String, String) splitPhotoExtension(String name) {
  final m = RegExp(r'^(.+?)(\.[A-Za-z0-9]{1,8})$').firstMatch(name);
  return m == null ? (name, '') : (m[1]!, m[2]!);
}

/// Oldest capture first; undated files fall back to upload time (apps/photo/shared/mediaOrder.ts).
List<T> sortPhotoMedia<T>(
  Iterable<T> media, {
  required String? Function(T) takenAt,
  required String Function(T) createdAt,
}) {
  int timeOf(T m) => DateTime.tryParse(takenAt(m) ?? createdAt(m))?.millisecondsSinceEpoch ?? 0;
  final list = [...media];
  list.sort((a, b) {
    final byTime = timeOf(a).compareTo(timeOf(b));
    return byTime != 0 ? byTime : createdAt(a).compareTo(createdAt(b));
  });
  return list;
}

class PhotoDaySection<T> {
  PhotoDaySection(this.key, this.at);

  /// Thai calendar day `YYYY-MM-DD`.
  final String key;

  /// ISO time of the first item, for the heading.
  final String at;

  /// Items with their index in the full list.
  final List<(T, int)> items = [];
}

/// Consecutive items on the same Thai calendar day share a section.
List<PhotoDaySection<T>> groupPhotosByDay<T>(
  List<T> media, {
  required String? Function(T) takenAt,
  required String Function(T) createdAt,
}) {
  final sections = <PhotoDaySection<T>>[];
  for (var i = 0; i < media.length; i++) {
    final at = takenAt(media[i]) ?? createdAt(media[i]);
    final d = bangkokTime(at);
    final key = d == null ? '' : photoYmd(d);
    if (sections.isEmpty || sections.last.key != key) sections.add(PhotoDaySection<T>(key, at));
    sections.last.items.add((media[i], i));
  }
  return sections;
}

// MARK: - EXIF capture time (port of apps/photo/src/lib/exif.ts)

/// `2026:10:12 09:30:00` (+ optional `+07:00`) → ISO UTC; null for blank or zeroed camera dates.
String? exifDateToIso(String raw, [String? offset]) {
  final m = RegExp(r'^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})').firstMatch(raw.trim());
  if (m == null || m[1] == '0000') return null;
  final tz = offset != null && RegExp(r'^[+-]\d{2}:\d{2}$').hasMatch(offset) ? offset : '+07:00';
  final t = DateTime.tryParse('${m[1]}-${m[2]}-${m[3]}T${m[4]}:${m[5]}:${m[6]}$tz');
  return t?.toUtc().toIso8601String();
}

/// Capture time from a JPEG's EXIF block (the first ~128 KB is enough), or null.
String? readExifDate(Uint8List bytes) {
  try {
    final view = ByteData.sublistView(bytes);
    if (view.lengthInBytes < 4 || view.getUint16(0) != 0xffd8) return null;
    var offset = 2;
    while (offset + 4 <= view.lengthInBytes) {
      if (view.getUint8(offset) != 0xff) return null;
      final marker = view.getUint8(offset + 1);
      if (marker == 0xda || marker == 0xd9) return null;
      final length = view.getUint16(offset + 2);
      if (marker == 0xe1 && _ascii(view, offset + 4, 4) == 'Exif') return _readTiffDate(view, offset + 10);
      offset += 2 + length;
    }
    return null;
  } catch (_) {
    return null;
  }
}

String _ascii(ByteData view, int offset, int length) {
  final out = StringBuffer();
  for (var i = 0; i < length; i++) {
    final c = view.getUint8(offset + i);
    if (c == 0) break;
    out.writeCharCode(c);
  }
  return out.toString();
}

String? _readTiffDate(ByteData view, int tiff) {
  final endian = view.getUint16(tiff) == 0x4949 ? Endian.little : Endian.big;
  int u16(int o) => view.getUint16(tiff + o, endian);
  int u32(int o) => view.getUint32(tiff + o, endian);
  if (u16(2) != 42) return null;

  String? readAscii(int ifd, int tag) {
    final count = u16(ifd);
    for (var i = 0; i < count; i++) {
      final entry = ifd + 2 + i * 12;
      if (u16(entry) != tag) continue;
      if (u16(entry + 2) != 2) return null;
      final length = u32(entry + 4);
      final at = length <= 4 ? tiff + entry + 8 : tiff + u32(entry + 8);
      return _ascii(view, at, length);
    }
    return null;
  }

  int? readPointer(int ifd, int tag) {
    final count = u16(ifd);
    for (var i = 0; i < count; i++) {
      final entry = ifd + 2 + i * 12;
      if (u16(entry) == tag) return u32(entry + 8);
    }
    return null;
  }

  final ifd0 = u32(4);
  final exifIfd = readPointer(ifd0, 0x8769);
  if (exifIfd != null) {
    final original = readAscii(exifIfd, 0x9003);
    if (original != null && original.isNotEmpty) {
      return exifDateToIso(original, readAscii(exifIfd, 0x9011));
    }
  }
  final fallback = readAscii(ifd0, 0x0132);
  return fallback == null ? null : exifDateToIso(fallback);
}
