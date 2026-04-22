/**
 * รหัสผ่านแบบฝั่งไคลเอนต์ — เก็บใน DB เป็น SHA-256 (hex) นำหน้า sha256$
 * รองรับบัญชีเก่าที่ยังเก็บ plain — อัปเกรดเป็นแฮชหลังล็อกอินสำเร็จ
 */

const HASH_PREFIX = 'sha256$';
const HASH_PREFIX_ALT = 'sha256:';

function looksLikeSha256Hex(raw: string): boolean {
    return /^[a-f0-9]{64}$/i.test(raw.trim());
}

function extractSha256Hex(raw: string): string | null {
    const s = raw.trim();
    if (looksLikeSha256Hex(s)) return s;
    const m = s.match(/([a-f0-9]{64})/i);
    return m ? m[1] : null;
}

async function sha256Hex(plain: string): Promise<string> {
    const data = new TextEncoder().encode(plain);
    const hash = await crypto.subtle.digest('SHA-256', data);
    return Array.from(new Uint8Array(hash))
        .map(b => b.toString(16).padStart(2, '0'))
        .join('');
}

function timingSafeEqualString(a: string, b: string): boolean {
    if (a.length !== b.length) return false;
    let out = 0;
    for (let i = 0; i < a.length; i++) out |= a.charCodeAt(i) ^ b.charCodeAt(i);
    return out === 0;
}

export function isPasswordHashedFormat(stored: string | undefined | null): boolean {
    if (!stored) return false;
    const s = stored.trim();
    if (s.startsWith(HASH_PREFIX) && s.length > HASH_PREFIX.length + 32) return true;
    if (s.startsWith(HASH_PREFIX_ALT) && s.length > HASH_PREFIX_ALT.length + 32) return true;
    // Legacy format: SHA-256 hex without prefix or embedded in wrapper string
    if (extractSha256Hex(s)) return true;
    return false;
}

export function needsPasswordRehash(stored: string | undefined | null): boolean {
    if (!stored) return false;
    return !isPasswordHashedFormat(stored);
}

export async function hashPasswordForStorage(plain: string): Promise<string> {
    const hex = await sha256Hex(plain);
    return `${HASH_PREFIX}${hex}`;
}

export async function verifyStoredPassword(stored: string, inputPlain: string): Promise<boolean> {
    if (!stored) return false;
    const s = stored.trim();
    if (isPasswordHashedFormat(s)) {
        const expectedHexRaw = s.startsWith(HASH_PREFIX)
            ? s.slice(HASH_PREFIX.length)
            : s.startsWith(HASH_PREFIX_ALT)
                ? s.slice(HASH_PREFIX_ALT.length)
                : (extractSha256Hex(s) || s);
        const expectedHex = (extractSha256Hex(expectedHexRaw) || expectedHexRaw).toLowerCase();
        const actualHex = await sha256Hex(inputPlain);
        if (timingSafeEqualString(expectedHex, actualHex.toLowerCase())) return true;
        // รองรับกรอกช่องว่างหัวท้ายโดยไม่ตั้งใจจากมือถือ/คีย์บอร์ด
        const trimmed = inputPlain.trim();
        if (trimmed !== inputPlain) {
            const actualTrimmed = await sha256Hex(trimmed);
            if (timingSafeEqualString(expectedHex, actualTrimmed.toLowerCase())) return true;
        }
        return false;
    }
    // Legacy/plain passwords: รองรับข้อมูลเก่าที่อาจมีช่องว่างหัวท้ายโดยไม่ได้ตั้งใจ
    if (timingSafeEqualString(s, inputPlain)) return true;
    return timingSafeEqualString(s, inputPlain.trim());
}

export const NEW_PASSWORD_MIN_LENGTH = 8;

export function validateNewPasswordPolicy(plain: string): { ok: true } | { ok: false; message: string } {
    const t = plain.trim();
    if (t.length < NEW_PASSWORD_MIN_LENGTH) {
        return { ok: false, message: `รหัสผ่านต้องมีอย่างน้อย ${NEW_PASSWORD_MIN_LENGTH} ตัวอักษร` };
    }
    return { ok: true };
}
