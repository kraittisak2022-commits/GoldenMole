import { describe, expect, it } from 'vitest';
import { checkUpload, guessMimeType, MAX_IMAGE_BYTES, MAX_VIDEO_BYTES, normalizeTitle, normalizeUploaderName, renamedFileName, splitExtension } from './limits';

describe('renamedFileName', () => {
  it('keeps the original extension', () => {
    expect(renamedFileName('เทปูน ชั้น 2', 'IMG_0001.JPG')).toBe('เทปูน ชั้น 2.JPG');
    expect(renamedFileName('เทปูน.jpg', 'IMG_0001.JPG')).toBe('เทปูน.JPG');
    expect(renamedFileName('clip', 'VID.mov')).toBe('clip.mov');
  });

  it('cleans whitespace and control characters, and refuses an empty name', () => {
    expect(renamedFileName('  a \n b\u0007 ', 'x.png')).toBe('a b.png');
    expect(renamedFileName('   ', 'x.png')).toBeNull();
    expect(renamedFileName('.png', 'x.png')).toBeNull();
    expect(renamedFileName(42, 'x.png')).toBeNull();
  });

  it('stays within 200 characters including the extension', () => {
    expect(renamedFileName('a'.repeat(300), 'x.jpeg')).toHaveLength(200);
  });

  it('splits names without an extension', () => {
    expect(splitExtension('README')).toEqual(['README', '']);
    expect(splitExtension('a.b.heic')).toEqual(['a.b', '.heic']);
  });
});

describe('guessMimeType', () => {
  it('keeps the browser type when present', () => {
    expect(guessMimeType('a.bin', 'image/png')).toBe('image/png');
  });

  it('falls back to the extension when the browser leaves it empty', () => {
    expect(guessMimeType('IMG_0001.HEIC', '')).toBe('image/heic');
    expect(guessMimeType('clip.mkv', '')).toBe('video/x-matroska');
    expect(guessMimeType('report.pdf', '')).toBe('');
  });
});

describe('checkUpload', () => {
  it('accepts images and videos within their limits', () => {
    expect(checkUpload({ mimeType: 'image/jpeg', size: MAX_IMAGE_BYTES })).toEqual({ ok: true, kind: 'image' });
    expect(checkUpload({ mimeType: 'video/mp4', size: MAX_VIDEO_BYTES })).toEqual({ ok: true, kind: 'video' });
  });

  it('refuses other types, empty files and oversized files', () => {
    expect(checkUpload({ mimeType: 'application/pdf', size: 10 })).toEqual({ ok: false, error: 'bad_type' });
    expect(checkUpload({ mimeType: '', size: 10 })).toEqual({ ok: false, error: 'bad_type' });
    expect(checkUpload({ mimeType: 'image/png', size: 0 })).toEqual({ ok: false, error: 'empty_file' });
    expect(checkUpload({ mimeType: 'image/png', size: NaN })).toEqual({ ok: false, error: 'empty_file' });
    expect(checkUpload({ mimeType: 'image/png', size: MAX_IMAGE_BYTES + 1 })).toEqual({ ok: false, error: 'too_large' });
    expect(checkUpload({ mimeType: 'video/quicktime', size: MAX_VIDEO_BYTES + 1 })).toEqual({ ok: false, error: 'too_large' });
  });
});

describe('normalizers', () => {
  it('collapses whitespace in titles and rejects empty or long ones', () => {
    expect(normalizeTitle('  เทปูน \n ชั้น 2 ')).toBe('เทปูน ชั้น 2');
    expect(normalizeTitle('   ')).toBeNull();
    expect(normalizeTitle('x'.repeat(201))).toBeNull();
    expect(normalizeTitle(42)).toBeNull();
  });

  it('trims uploader names to 60 characters', () => {
    expect(normalizeUploaderName(' ช่าง  สมชาย ')).toBe('ช่าง สมชาย');
    expect(normalizeUploaderName('a'.repeat(80))).toHaveLength(60);
    expect(normalizeUploaderName('')).toBeNull();
  });
});
