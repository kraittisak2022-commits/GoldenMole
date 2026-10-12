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

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<StaffUser | null>(() => readSession()?.user ?? null);

  useEffect(() => {
    if (!readSession()) return;
    api<{ user: StaffUser }>('/api/auth/me')
      .then(({ user: fresh }) => setUser(fresh))
      .catch((err) => {
        if (err instanceof ApiError && (err.status === 401 || err.status === 403)) {
          clearSession();
          setUser(null);
        }
      });
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
