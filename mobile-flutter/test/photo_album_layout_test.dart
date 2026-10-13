import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/services/photo_album_service.dart';
import 'package:mobile_flutter/services/photo_upload_manager.dart';
import 'package:mobile_flutter/utils/photo_album_format.dart';
import 'package:mobile_flutter/utils/photo_file_meta.dart';

double _rowWidth(PhotoRow row, double gap) =>
    row.items.fold<double>(0, (s, i) => s + i.width) + gap * (row.items.length - 1);

List<int> _u32(int v) => [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];
List<int> _box(String type, List<int> body) => [..._u32(body.length + 8), ...type.codeUnits, ...body];

/// ftyp, then moov with mvhd (v0) and a video trak whose tkhd is 1920×1080 turned a quarter.
Uint8List _mp4({required int created, required bool rotated}) {
  final mvhd = [0, 0, 0, 0, ..._u32(created), ..._u32(created), ..._u32(600), ..._u32(0), ...List.filled(80, 0)];
  const one = 0x00010000;
  const minusOne = 0xFFFF0000;
  final matrix = rotated
      ? [..._u32(0), ..._u32(one), ..._u32(0), ..._u32(minusOne), ..._u32(0), ..._u32(0), ..._u32(0), ..._u32(0), ..._u32(0x40000000)]
      : [..._u32(one), ..._u32(0), ..._u32(0), ..._u32(0), ..._u32(one), ..._u32(0), ..._u32(0), ..._u32(0), ..._u32(0x40000000)];
  final tkhd = [
    0, 0, 0, 3,
    ..._u32(created), ..._u32(created), ..._u32(1), ..._u32(0), ..._u32(0),
    ...List.filled(8, 0),
    0, 0, 0, 0, 0, 0, 0, 0,
    ...matrix,
    ..._u32(1920 << 16), ..._u32(1080 << 16),
  ];
  final audioTkhd = [0, 0, 0, 3, ...List.filled(72, 0), ..._u32(0), ..._u32(0)];
  return Uint8List.fromList([
    ..._box('ftyp', 'isom'.codeUnits),
    ..._box('moov', [
      ..._box('mvhd', mvhd),
      ..._box('trak', _box('tkhd', audioTkhd)),
      ..._box('trak', _box('tkhd', tkhd)),
    ]),
  ]);
}

Future<PhotoFileMeta> _read(Uint8List bytes) => readMp4Meta(
      (offset, length) async => Uint8List.sublistView(
        bytes,
        offset.clamp(0, bytes.length),
        (offset + length).clamp(0, bytes.length),
      ),
      bytes.length,
    );

void main() {
  group('justifiedPhotoRows', () {
    test('fills full rows to the container width and keeps every item once', () {
      final aspects = [1.5, 0.75, 1.0, 1.78, 1.33, 0.56, 1.5, 1.0];
      final rows = justifiedPhotoRows(aspects, 800, 200, 4);
      for (final row in rows.take(rows.length - 1)) {
        expect(_rowWidth(row, 4), closeTo(800, 1e-6));
      }
      expect(rows.expand((r) => r.items.map((i) => i.index)), List.generate(aspects.length, (i) => i));
    });

    test('leaves the last row at the target height instead of stretching it', () {
      final rows = justifiedPhotoRows([1], 800, 200, 4);
      expect(rows.single.height, 200);
      expect(rows.single.items.single.width, 200);
    });

    test('clamps extreme or missing aspect ratios', () {
      final row = justifiedPhotoRows([20, 0.01, double.nan], 10000, 100, 0).single;
      expect(row.items.map((i) => i.width), [300, 40, 100]);
    });

    test('returns nothing before the container has a width', () {
      expect(justifiedPhotoRows([1, 1], 0, 200, 4), isEmpty);
    });

    test('uses shorter rows on small screens', () {
      expect(photoTargetRowHeight(375), 120);
      expect(photoTargetRowHeight(800), 180);
      expect(photoTargetRowHeight(1400), 220);
    });
  });

  group('readMp4Meta', () {
    // 2026-10-12T02:30:00Z in seconds since 1904.
    const created = 1791772200 + 2082844800;

    test('reads recording time and swaps size for a quarter turn', () async {
      final meta = await _read(_mp4(created: created, rotated: true));
      expect(meta.takenAt, '2026-10-12T02:30:00.000Z');
      expect((meta.width, meta.height), (1080, 1920));
    });

    test('keeps landscape size and ignores a blank recording time', () async {
      final meta = await _read(_mp4(created: 0, rotated: false));
      expect(meta.takenAt, isNull);
      expect((meta.width, meta.height), (1920, 1080));
    });

    test('returns nothing for files without a movie box', () async {
      final meta = await _read(Uint8List.fromList([0xff, 0xd8, 0xff, 0xe1, 0, 4]));
      expect((meta.width, meta.height, meta.takenAt), (0, 0, null));
    });
  });

  test('picked files respect the web size limits', () {
    expect(const PickedPhotoMedia('/a.jpg', 1024).withinLimit, isTrue);
    expect(const PickedPhotoMedia('/a.jpg', kPhotoMaxImageBytes + 1).withinLimit, isFalse);
    expect(const PickedPhotoMedia('/a.mp4', kPhotoMaxImageBytes + 1).withinLimit, isTrue);
    expect(const PickedPhotoMedia('/a.mov', kPhotoMaxVideoBytes + 1).withinLimit, isFalse);
    expect(const PickedPhotoMedia('/a.jpg', 0).withinLimit, isFalse);
  });
}
