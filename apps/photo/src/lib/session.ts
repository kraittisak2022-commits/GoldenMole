import type { StaffUser } from '../../shared/types';

export interface StoredSession {
  token: string;
  user: StaffUser;
  savedAt: string;
}

const KEY = 'photo_session_v1';
/** Matches the server's token lifetime. */
const TTL_MS = 12 * 60 * 60 * 1000;

export function readSession(): StoredSession | null {
  try {
    const parsed = JSON.parse(localStorage.getItem(KEY) ?? 'null') as StoredSession | null;
    if (!parsed?.token || !parsed.user?.id || !parsed.savedAt) return null;
    if (Date.now() - Date.parse(parsed.savedAt) > TTL_MS) {
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
