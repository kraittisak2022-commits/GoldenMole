/**
 * รหัสผ่านแบบฝั่งไคลเอนต์ — เก็บใน DB เป็น SHA-256 (hex) นำหน้า sha256$
 * รองรับบัญชีเก่าที่ยังเก็บ plain — อัปเกรดเป็นแฮชหลังล็อกอินสำเร็จ
 */

const HASH_PREFIX = 'sha256$';

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
    return !!stored?.startsWith(HASH_PREFIX) && stored.length > HASH_PREFIX.length + 32;
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
    if (isPasswordHashedFormat(stored)) {
        const expectedHex = stored.slice(HASH_PREFIX.length);
        const actualHex = await sha256Hex(inputPlain);
        return timingSafeEqualString(expectedHex.toLowerCase(), actualHex.toLowerCase());
    }
    // Legacy/plain passwords: รองรับข้อมูลเก่าที่อาจมีช่องว่างหัวท้ายโดยไม่ได้ตั้งใจ
    if (timingSafeEqualString(stored, inputPlain)) return true;
    return timingSafeEqualString(stored.trim(), inputPlain.trim());
}

export const NEW_PASSWORD_MIN_LENGTH = 8;

export function validateNewPasswordPolicy(plain: string): { ok: true } | { ok: false; message: string } {
    const t = plain.trim();
    if (t.length < NEW_PASSWORD_MIN_LENGTH) {
        return { ok: false, message: `รหัสผ่านต้องมีอย่างน้อย ${NEW_PASSWORD_MIN_LENGTH} ตัวอักษร` };
    }
    return { ok: true };
}
