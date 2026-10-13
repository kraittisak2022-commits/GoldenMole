import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'photo_album_format.dart';

/// Size and capture time sent with an upload (apps/photo/src/lib/fileMeta.ts).
/// 0×0 lets the server read the size from Drive (photos, where Drive applies EXIF rotation).
class PhotoFileMeta {
  const PhotoFileMeta({this.width = 0, this.height = 0, this.takenAt});

  final int width;
  final int height;
  final String? takenAt;
}

typedef PhotoByteReader = Future<Uint8List> Function(int offset, int length);

const _exifScanBytes = 128 * 1024;
const _maxBoxesPerLevel = 256;

/// Seconds between 1904-01-01 (QuickTime epoch) and 1970-01-01.
const _quickTimeEpochOffset = 2082844800;

Future<PhotoFileMeta> readPhotoFileMeta(File file, String mimeType) async {
  String? fallback;
  try {
    fallback = (await file.lastModified()).toUtc().toIso8601String();
  } catch (_) {}

  if (mimeType.startsWith('video/')) {
    RandomAccessFile? raf;
    try {
      raf = await file.open();
      final size = await raf.length();
      final opened = raf;
      final meta = await readMp4Meta((offset, length) async {
        await opened.setPosition(offset);
        return opened.read(length);
      }, size);
      return PhotoFileMeta(width: meta.width, height: meta.height, takenAt: meta.takenAt ?? fallback);
    } catch (_) {
      return PhotoFileMeta(takenAt: fallback);
    } finally {
      await raf?.close();
    }
  }

  if (mimeType == 'image/jpeg') {
    try {
      final builder = BytesBuilder(copy: false);
      await for (final chunk in file.openRead(0, _exifScanBytes)) {
        builder.add(chunk);
      }
      return PhotoFileMeta(takenAt: readExifDate(builder.takeBytes()) ?? fallback);
    } catch (_) {}
  }
  return PhotoFileMeta(takenAt: fallback);
}

typedef _Box = ({String type, int start, int end});

/// Child boxes of an ISO-BMFF (MP4/MOV) range.
Future<List<_Box>> _boxes(PhotoByteReader read, int from, int to) async {
  final boxes = <_Box>[];
  var pos = from;
  while (pos + 8 <= to && boxes.length < _maxBoxesPerLevel) {
    final h = await read(pos, 16);
    if (h.length < 8) break;
    final view = ByteData.sublistView(h);
    var size = view.getUint32(0);
    var header = 8;
    if (size == 1) {
      if (h.length < 16) break;
      size = view.getUint32(8) * 0x100000000 + view.getUint32(12);
      header = 16;
    } else if (size == 0) {
      size = to - pos;
    }
    if (size < header) break;
    final type = String.fromCharCodes(h.sublist(4, 8));
    boxes.add((type: type, start: pos + header, end: math.min(pos + size, to)));
    pos += size;
  }
  return boxes;
}

int _u64(ByteData v, int o) => v.getUint32(o) * 0x100000000 + v.getUint32(o + 4);

/// Recording time (mvhd) and display size (first video tkhd, quarter turns swapped) of an MP4/MOV.
Future<PhotoFileMeta> readMp4Meta(PhotoByteReader read, int fileSize) async {
  final top = await _boxes(read, 0, fileSize);
  final moov = top.where((b) => b.type == 'moov').firstOrNull;
  if (moov == null) return const PhotoFileMeta();
  final children = await _boxes(read, moov.start, moov.end);

  String? takenAt;
  final mvhd = children.where((b) => b.type == 'mvhd').firstOrNull;
  if (mvhd != null) {
    final bytes = await read(mvhd.start, 16);
    if (bytes.length >= 12) {
      final v = ByteData.sublistView(bytes);
      final created = bytes[0] == 1 && bytes.length >= 12 ? _u64(v, 4) : v.getUint32(4);
      final seconds = created - _quickTimeEpochOffset;
      final at = DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
      if (created > 0 && at.year >= 2000) takenAt = at.toIso8601String();
    }
  }

  var width = 0;
  var height = 0;
  for (final trak in children.where((b) => b.type == 'trak')) {
    final tkhd = (await _boxes(read, trak.start, trak.end)).where((b) => b.type == 'tkhd').firstOrNull;
    if (tkhd == null) continue;
    final bytes = await read(tkhd.start, 96);
    if (bytes.isEmpty) continue;
    final matrix = bytes[0] == 1 ? 52 : 40;
    if (bytes.length < matrix + 44) continue;
    final v = ByteData.sublistView(bytes);
    final w = v.getUint32(matrix + 36) >> 16;
    final h = v.getUint32(matrix + 40) >> 16;
    if (w == 0 || h == 0) continue;
    final quarterTurn = v.getInt32(matrix) == 0 && v.getInt32(matrix + 16) == 0;
    width = quarterTurn ? h : w;
    height = quarterTurn ? w : h;
    break;
  }
  return PhotoFileMeta(width: width, height: height, takenAt: takenAt);
}
