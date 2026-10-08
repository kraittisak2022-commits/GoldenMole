import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react';
import { checkSession, signInWithAdminUsers } from './adminAuthService';
import { setLockedSource } from '../data/sourceScope';
import type { OrderSource } from '../types';
import { clearSession, readSession, saveSession, type StoneSandSession } from './session';

type AuthStatus = 'anonymous' | 'authenticated';

interface AuthContextValue {
  user: StoneSandSession | null;
  status: AuthStatus;
  /** Hides edit/delete actions only; the database itself does not enforce roles. */
  isSuperAdmin: boolean;
  /** The only order source this account may see, or null for both. */
  lockedSource: OrderSource | null;
  signIn: (username: string, password: string) => Promise<void>;
  signOut: () => void;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<StoneSandSession | null>(() => readSession());
  const lockedSource = user?.orderSource ?? null;
  // Before children render, so their first queries are already limited.
  setLockedSource(lockedSource);

  const signIn = useCallback(async (username: string, password: string) => {
    const session = await signInWithAdminUsers(username, password);
    saveSession(session);
    setUser(session);
  }, []);

  const signOut = useCallback(() => {
    clearSession();
    setUser(null);
  }, []);

  const userId = user?.id;
  useEffect(() => {
    if (!userId) return;
    let cancelled = false;
    void checkSession(userId).then(({ allowed, role, orderSource }) => {
      if (cancelled) return;
      if (!allowed) return signOut();
      if (!role) return;
      const prev = readSession();
      if (!prev) return;
      const next = { ...prev, role, orderSource: orderSource ?? null };
      if (prev.role === next.role && (prev.orderSource ?? null) === next.orderSource) return;
      saveSession(next);
      // Pages already loaded data for the old source limit.
      if ((prev.orderSource ?? null) !== next.orderSource) return window.location.reload();
      setUser(next);
    });
    return () => {
      cancelled = true;
    };
  }, [userId, signOut]);

  const value = useMemo<AuthContextValue>(
    () => ({
      user,
      status: user ? 'authenticated' : 'anonymous',
      isSuperAdmin: user?.role === 'SuperAdmin',
      lockedSource,
      signIn,
      signOut,
    }),
    [user, lockedSource, signIn, signOut],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
}