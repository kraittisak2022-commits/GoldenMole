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
import { clearSession, readSession, saveSession, type StoneSandSession } from './session';

type AuthStatus = 'anonymous' | 'authenticated';

interface AuthContextValue {
  user: StoneSandSession | null;
  status: AuthStatus;
  /** Hides edit/delete actions only; the database itself does not enforce roles. */
  isSuperAdmin: boolean;
  signIn: (username: string, password: string) => Promise<void>;
  signOut: () => void;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<StoneSandSession | null>(() => readSession());

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
    void checkSession(userId).then(({ allowed, role }) => {
      if (cancelled) return;
      if (!allowed) return signOut();
      if (role) {
        setUser((prev) => {
          if (!prev || prev.role === role) return prev;
          const next = { ...prev, role };
          saveSession(next);
          return next;
        });
      }
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
      signIn,
      signOut,
    }),
    [user, signIn, signOut],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
}
