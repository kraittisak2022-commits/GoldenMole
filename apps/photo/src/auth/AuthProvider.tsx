import { createContext, ReactNode, useCallback, useContext, useEffect, useMemo, useState } from 'react';
import type { StaffUser } from '../../shared/types';
import { api, ApiError, SIGNED_OUT_EVENT } from '../lib/api';
import { clearSession, readSession, saveSession } from '../lib/session';

interface AuthValue {
  user: StaffUser | null;
  signIn: (username: string, password: string) => Promise<void>;
  signOut: () => void;
}

const AuthContext = createContext<AuthValue | null>(null);
const RENEW_EVERY_MS = 6 * 60 * 60 * 1000;

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<StaffUser | null>(() => readSession()?.user ?? null);

  // Swap the token for a fresh one on open and whenever the app comes back to the screen, so people
  // who use the site regularly never see the login page; network errors keep the current session.
  useEffect(() => {
    let renewedAt = 0;
    const renew = () => {
      if (document.visibilityState !== 'visible' || !readSession() || Date.now() - renewedAt < RENEW_EVERY_MS) return;
      renewedAt = Date.now();
      api<{ user: StaffUser; token?: string }>('/api/auth/me')
        .then(({ user: fresh, token }) => {
          if (token) saveSession(token, fresh);
          setUser(fresh);
        })
        .catch((err) => {
          if (err instanceof ApiError && (err.status === 401 || err.status === 403)) {
            clearSession();
            setUser(null);
          } else {
            renewedAt = 0;
          }
        });
    };
    renew();
    document.addEventListener('visibilitychange', renew);
    return () => document.removeEventListener('visibilitychange', renew);
  }, []);

  useEffect(() => {
    const onSignedOut = () => setUser(null);
    window.addEventListener(SIGNED_OUT_EVENT, onSignedOut);
    return () => window.removeEventListener(SIGNED_OUT_EVENT, onSignedOut);
  }, []);

  const signIn = useCallback(async (username: string, password: string) => {
    const res = await api<{ token: string; user: StaffUser }>('/api/auth/login', { method: 'POST', body: { username, password } });
    saveSession(res.token, res.user);
    setUser(res.user);
  }, []);

  const signOut = useCallback(() => {
    clearSession();
    setUser(null);
  }, []);

  const value = useMemo(() => ({ user, signIn, signOut }), [user, signIn, signOut]);
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth outside AuthProvider');
  return ctx;
}
