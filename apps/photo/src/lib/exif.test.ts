import { describe, expect, it } from 'vitest';
import { exifDateToIso, readExifDate } from './exif';

/** A minimal JPEG: SOI, an APP1 Exif segment with IFD0 → ExifIFD holding DateTimeOriginal (+ offset), then SOS. */
function jpegWithExif(date: string, offset: string | null, little: boolean): ArrayBuffer {
  const tiff: number[] = [];
  const u16 = (v: number) => (little ? [v & 0xff, v >> 8] : [v >> 8, v & 0xff]);
  const u32 = (v: number) => (little ? [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, v >>> 24] : [v >>> 24, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff]);
  const ascii = (s: string) => [...s].map((c) => c.charCodeAt(0)).concat(0);

  const exifEntries = offset ? 2 : 1;
  const ifd0 = 8;
  const exifIfd = ifd0 + 2 + 12 + 4;
  const dataStart = exifIfd + 2 + exifEntries * 12 + 4;
  const dateBytes = ascii(date);
  const offsetBytes = offset ? ascii(offset) : [];

  tiff.push(...(little ? [0x49, 0x49] : [0x4d, 0x4d]), ...u16(42), ...u32(ifd0));
  tiff.push(...u16(1), ...u16(0x8769), ...u16(4), ...u32(1), ...u32(exifIfd), ...u32(0));
  tiff.push(...u16(exifEntries), ...u16(0x9003), ...u16(2), ...u32(dateBytes.length), ...u32(dataStart));
  if (offset) tiff.push(...u16(0x9011), ...u16(2), ...u32(offsetBytes.length), ...u32(dataStart + dateBytes.length));
  tiff.push(...u32(0), ...dateBytes, ...offsetBytes);

  const app1 = [...ascii('Exif'), 0, ...tiff];
  const length = app1.length + 2;
  const bytes = [0xff, 0xd8, 0xff, 0xe1, length >> 8, length & 0xff, ...app1, 0xff, 0xda, 0, 2];
  return new Uint8Array(bytes).buffer;
}

describe('exifDateToIso', () => {
  it('reads camera time as Thai time unless an offset is given', () => {
    expect(exifDateToIso('2026:10:12 09:30:00')).toBe('2026-10-12T02:30:00.000Z');
    expect(exifDateToIso('2026:10:12 09:30:00', '+09:00')).toBe('2026-10-12T00:30:00.000Z');
    expect(exifDateToIso('0000:00:00 00:00:00')).toBeNull();
    expect(exifDateToIso('')).toBeNull();
  });
});

describe('readExifDate', () => {
  it('finds DateTimeOriginal in big- and little-endian files', () => {
    expect(readExifDate(jpegWithExif('2026:10:12 09:30:00', null, false))).toBe('2026-10-12T02:30:00.000Z');
    expect(readExifDate(jpegWithExif('2026:10:12 09:30:00', '+00:00', true))).toBe('2026-10-12T09:30:00.000Z');
  });

  it('returns null for non-JPEG or truncated data', () => {
    expect(readExifDate(new Uint8Array([0x89, 0x50, 0x4e, 0x47]).buffer)).toBeNull();
    expect(readExifDate(jpegWithExif('2026:10:12 09:30:00', null, true).slice(0, 30))).toBeNull();
  });
});
