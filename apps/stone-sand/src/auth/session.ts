import type { OrderSource } from '../types';

export type AdminRole = 'SuperAdmin' | 'Admin' | 'Assistant';

export interface StoneSandSession {
  id: string;
  username: string;
  displayName: string;
  role: AdminRole;
  /** Only this order source is visible; null = both. Missing in sessions saved before it existed. */
  orderSource?: OrderSource | null;
  loginAt: string;
}

const SESSION_KEY = 'stone_sand_session_v1';
/** 12 hours */
export const SESSION_TTL_MS = 12 * 60 * 60 * 1000;

export function saveSession(session: StoneSandSession): void {
  try {
    localStorage.setItem(SESSION_KEY, JSON.stringify(session));
  } catch {
    // ignore quota / private mode
  }
}

export function clearSession(): void {
  try {
    localStorage.removeItem(SESSION_KEY);
  } catch {
    // ignore
  }
}

export function readSession(): StoneSandSession | null {
  try {
    const raw = localStorage.getItem(SESSION_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as StoneSandSession;
    if (!parsed?.id || !parsed?.username || !parsed?.role || !parsed?.loginAt) return null;
    const loginAt = Date.parse(parsed.loginAt);
    if (Number.isNaN(loginAt) || Date.now() - loginAt > SESSION_TTL_MS) {
      clearSession();
      return null;
    }
    return parsed;
  } catch {
    return null;
  }
}
