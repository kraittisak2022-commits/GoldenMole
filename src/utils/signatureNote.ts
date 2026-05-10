/** Prefix เดียวกับแอป Android (`quick_input_screen.dart`) เพื่อให้ parse ร่วมกันได้ */
export const SIGNATURE_NOTE_PREFIX = 'mobile_signature:';

export type EmbeddedSignatureMeta = {
    source?: string;
    signedAt?: string;
    signedBy?: string;
    paths?: number[][][];
};

export const parseSignatureNote = (note?: string): EmbeddedSignatureMeta | null => {
    if (!note) return null;
    const raw = String(note).trim();
    if (!raw.startsWith(SIGNATURE_NOTE_PREFIX)) return null;
    const payload = raw.slice(SIGNATURE_NOTE_PREFIX.length).trim();
    if (!payload) return null;
    try {
        const parsed = JSON.parse(payload) as EmbeddedSignatureMeta;
        if (!parsed || typeof parsed !== 'object') return null;
        return parsed;
    } catch {
        return null;
    }
};

export const formatSignatureDateTime = (iso?: string) => {
    if (!iso) return '';
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return '';
    return d.toLocaleString('th-TH', {
        timeZone: 'Asia/Bangkok',
        day: '2-digit',
        month: '2-digit',
        year: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
    });
};

export const hasSignaturePaths = (meta: EmbeddedSignatureMeta | null) =>
    !!meta &&
    Array.isArray(meta.paths) &&
    meta.paths.some(path => Array.isArray(path) && path.length >= 2);

export const signatureSourceLabel = (meta: EmbeddedSignatureMeta | null) => {
    const s = (meta?.source || '').toLowerCase();
    if (s === 'web') return 'เว็บ';
    if (s === 'android') return 'มือถือ (Android)';
    return 'ลายเซ็น';
};

export const buildSignatureNoteJson = (opts: {
    source: 'web' | 'android';
    signedBy: string;
    paths: number[][][];
}): string => {
    const now = new Date().toISOString();
    const payload = {
        source: opts.source,
        signedAt: now,
        signedBy: opts.signedBy,
        paths: opts.paths,
    };
    return `${SIGNATURE_NOTE_PREFIX}${JSON.stringify(payload)}`;
};
