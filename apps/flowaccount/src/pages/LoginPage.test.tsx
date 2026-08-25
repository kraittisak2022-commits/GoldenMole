import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { describe, expect, it, vi } from 'vitest';
import { SignInError } from '../auth/adminAuthService';
import LoginPage from './LoginPage';

const signIn = vi.fn();

vi.mock('../auth/AuthProvider', () => ({
  useAuth: () => ({
    status: 'anonymous',
    user: null,
    signIn,
    signOut: vi.fn(),
  }),
}));

function renderLogin() {
  return render(
    <MemoryRouter>
      <LoginPage />
    </MemoryRouter>,
  );
}

describe('LoginPage', () => {
  it('renders brand, form fields, and SuperAdmin footer', () => {
    renderLogin();
    expect(screen.getByText('GoldenMole')).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'FlowAccount' })).toBeInTheDocument();
    expect(screen.getByLabelText('ชื่อผู้ใช้')).toBeInTheDocument();
    expect(screen.getByLabelText('รหัสผ่าน')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'เข้าสู่ระบบ' })).toBeInTheDocument();
    expect(screen.getByText('สิทธิ์เฉพาะ SuperAdmin')).toBeInTheDocument();
  });

  it('toggles password visibility from the keyboard-accessible button', async () => {
    const user = userEvent.setup();
    renderLogin();

    const password = screen.getByLabelText('รหัสผ่าน');
    expect(password).toHaveAttribute('type', 'password');

    const toggle = screen.getByRole('button', { name: 'แสดงรหัสผ่าน' });
    expect(toggle).toHaveAttribute('aria-pressed', 'false');

    await user.click(toggle);
    expect(password).toHaveAttribute('type', 'text');
    expect(screen.getByRole('button', { name: 'ซ่อนรหัสผ่าน' })).toHaveAttribute(
      'aria-pressed',
      'true',
    );

    await user.click(screen.getByRole('button', { name: 'ซ่อนรหัสผ่าน' }));
    expect(password).toHaveAttribute('type', 'password');
  });

  it('submits username and password through signIn', async () => {
    const user = userEvent.setup();
    signIn.mockResolvedValue(undefined);
    renderLogin();

    await user.type(screen.getByLabelText('ชื่อผู้ใช้'), 'boss');
    await user.type(screen.getByLabelText('รหัสผ่าน'), 'secret');
    await user.click(screen.getByRole('button', { name: 'เข้าสู่ระบบ' }));

    expect(signIn).toHaveBeenCalledWith('boss', 'secret');
  });

  it('shows an alert when signIn fails', async () => {
    const user = userEvent.setup();
    signIn.mockRejectedValue(
      new SignInError('bad_password', 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง'),
    );
    renderLogin();

    await user.type(screen.getByLabelText('ชื่อผู้ใช้'), 'boss');
    await user.type(screen.getByLabelText('รหัสผ่าน'), 'wrong');
    await user.click(screen.getByRole('button', { name: 'เข้าสู่ระบบ' }));

    await waitFor(() => {
      expect(screen.getByRole('alert')).toHaveTextContent('ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง');
    });
  });
});
