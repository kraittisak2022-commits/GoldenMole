import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  useState,
  type ReactNode,
} from 'react';
import { signInWithAdminUsers } from './adminAuthService';
import {
  clearSession,
  readSession,
  saveSession,
  type FlowAccountSession,
} from './session';

type AuthStatus = 'anonymous' | 'authenticated';

interface AuthContextValue {
  user: FlowAccountSession | null;
  status: AuthStatus;
  signIn: (username: string, password: string) => Promise<void>;
  signOut: () => void;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<FlowAccountSession | null>(() => readSession());

  const signIn = useCallback(async (username: string, password: string) => {
    const session = await signInWithAdminUsers(username, password);
    saveSession(session);
    setUser(session);
  }, []);

  const signOut = useCallback(() => {
    clearSession();
    setUser(null);
  }, []);

  const value = useMemo<AuthContextValue>(
    () => ({
      user,
      status: user ? 'authenticated' : 'anonymous',
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
