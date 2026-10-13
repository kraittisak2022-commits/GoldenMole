import type { StaffUser } from '../../shared/types';

export interface StoredSession {
  token: string;
  user: StaffUser;
  savedAt: string;
}

const KEY = 'photo_session_v1';

/** Expiry (epoch ms) from the server-signed `<payload>.<signature>` token, or 0 when unreadable. */
export function tokenExpiresAt(token: string): number {
  try {
    const payload = token.split('.')[0].replace(/-/g, '+').replace(/_/g, '/');
    const exp = (JSON.parse(atob(payload)) as { exp?: unknown }).exp;
    return typeof exp === 'number' ? exp : 0;
  } catch {
    return 0;
  }
}

export function readSession(now = Date.now()): StoredSession | null {
  try {
    const parsed = JSON.parse(localStorage.getItem(KEY) ?? 'null') as StoredSession | null;
    if (!parsed?.token || !parsed.user?.id || !parsed.savedAt) return null;
    if (tokenExpiresAt(parsed.token) <= now) {
      clearSession();
      return null;
    }
    return parsed;
  } catch {
    return null;
  }
}

export function saveSession(token: string, user: StaffUser): StoredSession {
  const session = { token, user, savedAt: new Date().toISOString() };
  try {
    localStorage.setItem(KEY, JSON.stringify(session));
  } catch {
    // private mode: the session lasts for this tab only
  }
  return session;
}

export function clearSession(): void {
  try {
    localStorage.removeItem(KEY);
  } catch {
    // ignore
  }
}
