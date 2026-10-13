import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/services/photo_album_service.dart';
import 'package:mobile_flutter/utils/photo_album_format.dart';

/// A minimal JPEG: SOI, an APP1 Exif segment with IFD0 → ExifIFD holding DateTimeOriginal (+ offset), then SOS.
Uint8List _jpegWithExif(String date, String? offset, {required bool little}) {
  List<int> u16(int v) => little ? [v & 0xff, v >> 8] : [v >> 8, v & 0xff];
  List<int> u32(int v) => little
      ? [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]
      : [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];
  List<int> ascii(String s) => [...s.codeUnits, 0];

  final exifEntries = offset != null ? 2 : 1;
  const ifd0 = 8;
  const exifIfd = ifd0 + 2 + 12 + 4;
  final dataStart = exifIfd + 2 + exifEntries * 12 + 4;
  final dateBytes = ascii(date);
  final offsetBytes = offset != null ? ascii(offset) : <int>[];

  final tiff = <int>[
    ...(little ? [0x49, 0x49] : [0x4d, 0x4d]), ...u16(42), ...u32(ifd0),
    ...u16(1), ...u16(0x8769), ...u16(4), ...u32(1), ...u32(exifIfd), ...u32(0),
    ...u16(exifEntries), ...u16(0x9003), ...u16(2), ...u32(dateBytes.length), ...u32(dataStart),
    if (offset != null) ...[
      ...u16(0x9011), ...u16(2), ...u32(offsetBytes.length), ...u32(dataStart + dateBytes.length),
    ],
    ...u32(0), ...dateBytes, ...offsetBytes,
  ];
  final app1 = [...ascii('Exif'), 0, ...tiff];
  final length = app1.length + 2;
  return Uint8List.fromList([0xff, 0xd8, 0xff, 0xe1, length >> 8, length & 0xff, ...app1, 0xff, 0xda, 0, 2]);
}

PhotoMediaItem _media(String id, {String? takenAt, required String createdAt}) => PhotoMediaItem(
      id: id,
      kind: 'image',
      name: '$id.jpg',
      takenAt: takenAt,
      createdAt: createdAt,
      src: const PhotoMediaSources(thumb: '', thumbFallback: '', large: '', download: ''),
    );

void main() {
  test('Thai dates match the web format', () {
    expect(formatPhotoAlbumDate('2026-10-06'), '6 ต.ค. 2569');
    expect(formatPhotoAlbumDateLong('2026-10-06'), '6 ตุลาคม 2569');
    expect(formatPhotoDayHeading('2026-10-13T07:05:00.000Z'), 'อ. 13 ต.ค. 2569');
    expect(formatPhotoDateTime('2026-10-13T07:05:00.000Z'), '13 ต.ค. 2569 14:05');
    expect(photoDrivePathLabel('2026-10-06'), 'GoldenMole Photos / 2569 / 10-ตุลาคม');
    expect(photoYmd(DateTime(2026, 1, 5)), '2026-01-05');
  });

  test('splitPhotoExtension keeps the extension apart', () {
    expect(splitPhotoExtension('IMG_1.JPG'), ('IMG_1', '.JPG'));
    expect(splitPhotoExtension('report'), ('report', ''));
    expect(splitPhotoExtension('a.b.mp4'), ('a.b', '.mp4'));
  });

  test('media sorts oldest capture first and groups by Thai day', () {
    final media = sortPhotoMediaItems([
      _media('late', takenAt: '2026-10-13T10:00:00.000Z', createdAt: '2026-10-14T01:00:00.000Z'),
      _media('undated', createdAt: '2026-10-12T20:00:00.000Z'),
      _media('early', takenAt: '2026-10-12T16:30:00.000Z', createdAt: '2026-10-14T01:00:00.000Z'),
    ]);
    expect(media.map((m) => m.id), ['early', 'undated', 'late']);

    final days = groupPhotosByDay(media, takenAt: (m) => m.takenAt, createdAt: (m) => m.createdAt);
    expect(days.map((d) => d.key), ['2026-10-12', '2026-10-13']);
    expect(days.first.items.map((e) => e.$2), [0]);
    expect(days.last.items.map((e) => e.$1.id), ['undated', 'late']);
  });

  test('exifDateToIso reads camera time as Thai time unless an offset is given', () {
    expect(exifDateToIso('2026:10:12 09:30:00'), '2026-10-12T02:30:00.000Z');
    expect(exifDateToIso('2026:10:12 09:30:00', '+09:00'), '2026-10-12T00:30:00.000Z');
    expect(exifDateToIso('0000:00:00 00:00:00'), isNull);
    expect(exifDateToIso(''), isNull);
  });

  test('readExifDate finds DateTimeOriginal in big- and little-endian files', () {
    expect(readExifDate(_jpegWithExif('2026:10:12 09:30:00', null, little: false)), '2026-10-12T02:30:00.000Z');
    expect(readExifDate(_jpegWithExif('2026:10:12 09:30:00', '+00:00', little: true)), '2026-10-12T09:30:00.000Z');
  });

  test('readExifDate returns null for non-JPEG or truncated data', () {
    expect(readExifDate(Uint8List.fromList([0x89, 0x50, 0x4e, 0x47])), isNull);
    expect(readExifDate(Uint8List.sublistView(_jpegWithExif('2026:10:12 09:30:00', null, little: true), 0, 30)), isNull);
  });

  test('video files use video mime types and a VID_ name', () {
    expect(photoPathIsVideo('/x/clip.MOV'), isTrue);
    expect(photoPathIsVideo('/x/a.jpg'), isFalse);
    expect(photoUploadFileName(DateTime(2026, 10, 6, 9, 5, 7), 1, 'mp4', video: true), 'VID_20261006_090507_2.mp4');
  });

  test('direct download URL comes from the Drive file id', () {
    const item = PhotoMediaItem(
      id: 'm1',
      kind: 'image',
      name: 'a.jpg',
      createdAt: '',
      src: PhotoMediaSources(
        thumb: '',
        thumbFallback: '',
        large: '',
        download: 'https://drive.google.com/uc?export=download&id=FILE123',
      ),
    );
    expect(
      item.directDownloadUrl.toString(),
      'https://drive.usercontent.google.com/download?id=FILE123&export=download&confirm=t',
    );
  });
}
