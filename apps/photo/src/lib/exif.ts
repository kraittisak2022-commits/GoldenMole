const TAG_EXIF_IFD = 0x8769;
const TAG_DATETIME = 0x0132;
const TAG_DATETIME_ORIGINAL = 0x9003;
const TAG_OFFSET_TIME_ORIGINAL = 0x9011;
const TYPE_ASCII = 2;

function ascii(view: DataView, offset: number, length: number): string {
  let out = '';
  for (let i = 0; i < length; i++) {
    const c = view.getUint8(offset + i);
    if (c === 0) break;
    out += String.fromCharCode(c);
  }
  return out;
}

/** `2026:10:12 09:30:00` (+ optional `+07:00`) → ISO; null for blank or zeroed camera dates. */
export function exifDateToIso(raw: string, offset?: string | null): string | null {
  const m = /^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})/.exec(raw.trim());
  if (!m || m[1] === '0000') return null;
  const tz = offset && /^[+-]\d{2}:\d{2}$/.test(offset) ? offset : '+07:00';
  const iso = `${m[1]}-${m[2]}-${m[3]}T${m[4]}:${m[5]}:${m[6]}${tz}`;
  return Number.isNaN(Date.parse(iso)) ? null : new Date(iso).toISOString();
}

function readTiffDate(view: DataView, tiff: number): string | null {
  const little = view.getUint16(tiff) === 0x4949;
  const u16 = (o: number) => view.getUint16(tiff + o, little);
  const u32 = (o: number) => view.getUint32(tiff + o, little);
  if (u16(2) !== 42) return null;

  const readAscii = (ifd: number, tag: number): string | null => {
    const count = u16(ifd);
    for (let i = 0; i < count; i++) {
      const entry = ifd + 2 + i * 12;
      if (u16(entry) !== tag) continue;
      if (u16(entry + 2) !== TYPE_ASCII) return null;
      const length = u32(entry + 4);
      const at = length <= 4 ? tiff + entry + 8 : tiff + u32(entry + 8);
      return ascii(view, at, length);
    }
    return null;
  };
  const readPointer = (ifd: number, tag: number): number | null => {
    const count = u16(ifd);
    for (let i = 0; i < count; i++) {
      const entry = ifd + 2 + i * 12;
      if (u16(entry) === tag) return u32(entry + 8);
    }
    return null;
  };

  const ifd0 = u32(4);
  const exifIfd = readPointer(ifd0, TAG_EXIF_IFD);
  if (exifIfd !== null) {
    const original = readAscii(exifIfd, TAG_DATETIME_ORIGINAL);
    if (original) return exifDateToIso(original, readAscii(exifIfd, TAG_OFFSET_TIME_ORIGINAL));
  }
  const fallback = readAscii(ifd0, TAG_DATETIME);
  return fallback ? exifDateToIso(fallback) : null;
}

/** Capture time from a JPEG's EXIF block (the first ~128 KB is enough), or null. */
export function readExifDate(buffer: ArrayBuffer): string | null {
  try {
    const view = new DataView(buffer);
    if (view.byteLength < 4 || view.getUint16(0) !== 0xffd8) return null;
    let offset = 2;
    while (offset + 4 <= view.byteLength) {
      if (view.getUint8(offset) !== 0xff) return null;
      const marker = view.getUint8(offset + 1);
      if (marker === 0xda || marker === 0xd9) return null;
      const length = view.getUint16(offset + 2);
      if (marker === 0xe1 && ascii(view, offset + 4, 4) === 'Exif') return readTiffDate(view, offset + 10);
      offset += 2 + length;
    }
    return null;
  } catch {
    return null;
  }
}
