import { verifyStoredPassword } from './passwordAuth';

export const SHARE_PIN_MIN_LENGTH = 4;
export const SHARE_PIN_MAX_LENGTH = 6;
export const SHARE_PIN_MAX_FAIL = 5;
export const SHARE_PIN_LOCK_MS = 90 * 1000;
const SHARE_SESSION_KEY = 'cm_share_unlock_v1';
const SHARE_FAIL_KEY = 'cm_share_pin_fail_v1';

export function isValidSharePinFormat(pin: string): boolean {
    return /^\d{4,6}$/.test(pin.trim());
}

export async function verifySharePin(storedHash: string | null, inputPin: string): Promise<boolean> {
    if (!storedHash) return false;
    return verifyStoredPassword(storedHash, inputPin);
}

interface ShareFailState {
    token: string;
    failedAttempts: number;
    lockUntil?: number;
}

function readFailState(token: string): ShareFailState {
    try {
        const raw = sessionStorage.getItem(SHARE_FAIL_KEY);
        if (!raw) return { token, failedAttempts: 0 };
        const parsed = JSON.parse(raw) as ShareFailState;
        if (parsed.token !== token) return { token, failedAttempts: 0 };
        return parsed;
    } catch {
        return { token, failedAttempts: 0 };
    }
}

function writeFailState(state: ShareFailState) {
    sessionStorage.setItem(SHARE_FAIL_KEY, JSON.stringify(state));
}

export function getSharePinLockRemainMs(token: string): number {
    const state = readFailState(token);
    if (!state.lockUntil) return 0;
    return Math.max(0, state.lockUntil - Date.now());
}

/** Verify PIN without counting failed attempts (for auto-unlock while typing). */
export async function verifySharePinOnly(storedHash: string | null, inputPin: string): Promise<boolean> {
    return verifySharePin(storedHash, inputPin);
}

export async function attemptSharePinUnlock(
    token: string,
    storedHash: string | null,
    inputPin: string,
): Promise<{ ok: true } | { ok: false; message: string; lockRemainMs?: number }> {
    const lockRemain = getSharePinLockRemainMs(token);
    if (lockRemain > 0) {
        return { ok: false, message: 'PIN ถูกล็อกชั่วคราว', lockRemainMs: lockRemain };
    }

    const valid = await verifySharePin(storedHash, inputPin);
    if (valid) {
        writeFailState({ token, failedAttempts: 0 });
        setShareUnlockSession(token);
        return { ok: true };
    }

    const prev = readFailState(token);
    const failedAttempts = (prev.failedAttempts || 0) + 1;
    const next: ShareFailState = { token, failedAttempts };
    if (failedAttempts >= SHARE_PIN_MAX_FAIL) {
        next.lockUntil = Date.now() + SHARE_PIN_LOCK_MS;
    }
    writeFailState(next);

    if (next.lockUntil) {
        return {
            ok: false,
            message: 'PIN ผิดเกินกำหนด ล็อกชั่วคราว 90 วินาที',
            lockRemainMs: SHARE_PIN_LOCK_MS,
        };
    }
    return { ok: false, message: 'PIN ไม่ถูกต้อง' };
}

export function isShareSessionUnlocked(token: string): boolean {
    try {
        const raw = sessionStorage.getItem(SHARE_SESSION_KEY);
        if (!raw) return false;
        const parsed = JSON.parse(raw) as { token: string; at: number };
        if (parsed.token !== token) return false;
        // Session lasts until tab is closed (sessionStorage)
        return true;
    } catch {
        return false;
    }
}

export function setShareUnlockSession(token: string) {
    sessionStorage.setItem(SHARE_SESSION_KEY, JSON.stringify({ token, at: Date.now() }));
}

export function markSharePinUnlocked(token: string) {
    writeFailState({ token, failedAttempts: 0 });
    setShareUnlockSession(token);
}

export function clearShareUnlockSession() {
    sessionStorage.removeItem(SHARE_SESSION_KEY);
    sessionStorage.removeItem(SHARE_FAIL_KEY);
}
