import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { AuthProvider, useAuth } from './AuthProvider';
import { RequireAuth } from './RequireAuth';
import { clearSession, saveSession } from './session';

const signInWithAdminUsers = vi.fn();

vi.mock('./adminAuthService', async () => {
  class SignInError extends Error {
    code: string;
    constructor(code: string, message: string) {
      super(message);
      this.name = 'SignInError';
      this.code = code;
    }
  }
  return {
    SignInError,
    signInWithAdminUsers: (username: string, password: string) =>
      signInWithAdminUsers(username, password),
  };
});

function LoginView() {
  const { signIn, status } = useAuth();
  return (
    <div>
      <p>login-view</p>
      <p>status:{status}</p>
      <button
        type="button"
        onClick={() => {
          void signIn('boss', 'ok');
        }}
      >
        do-login
      </button>
    </div>
  );
}

function PrivateView() {
  const { signOut, user } = useAuth();
  return (
    <div>
      <p>private:{user?.displayName ?? 'none'}</p>
      <button type="button" onClick={signOut}>
        do-logout
      </button>
    </div>
  );
}

function renderRoutes(initial: string) {
  return render(
    <AuthProvider>
      <MemoryRouter initialEntries={[initial]}>
        <Routes>
          <Route path="/login" element={<LoginView />} />
          <Route
            path="/"
            element={
              <RequireAuth>
                <PrivateView />
              </RequireAuth>
            }
          />
        </Routes>
      </MemoryRouter>
    </AuthProvider>,
  );
}

describe('AuthProvider + RequireAuth', () => {
  afterEach(() => {
    clearSession();
    signInWithAdminUsers.mockReset();
  });

  it('redirects unauthenticated users to /login', () => {
    renderRoutes('/');
    expect(screen.getByText('login-view')).toBeInTheDocument();
  });

  it('allows a persisted SuperAdmin session on the private route', () => {
    saveSession({
      id: '1',
      username: 'boss',
      displayName: 'Boss',
      role: 'SuperAdmin',
      loginAt: new Date().toISOString(),
    });
    renderRoutes('/');
    expect(screen.getByText('private:Boss')).toBeInTheDocument();
  });

  it('logs out and clears private content', async () => {
    const user = userEvent.setup();
    saveSession({
      id: '1',
      username: 'boss',
      displayName: 'Boss',
      role: 'SuperAdmin',
      loginAt: new Date().toISOString(),
    });
    renderRoutes('/');
    expect(screen.getByText('private:Boss')).toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: 'do-logout' }));
    await waitFor(() => {
      expect(screen.getByText('login-view')).toBeInTheDocument();
    });
  });

  it('marks status authenticated after successful signIn', async () => {
    const user = userEvent.setup();
    signInWithAdminUsers.mockResolvedValue({
      id: '1',
      username: 'boss',
      displayName: 'Boss',
      role: 'SuperAdmin',
      loginAt: new Date().toISOString(),
    });
    renderRoutes('/login');
    await user.click(screen.getByRole('button', { name: 'do-login' }));
    await waitFor(() => {
      expect(screen.getByText('status:authenticated')).toBeInTheDocument();
    });
  });
});
