import { FormEvent, useState } from 'react';
import { Link, Navigate, useLocation, useNavigate } from 'react-router-dom';
import { Eye, EyeOff } from 'lucide-react';
import { useAuth } from '../auth/AuthProvider';
import { LogoMark } from '../components/Logo';
import Button from '../components/ui/Button';
import IconButton from '../components/ui/IconButton';
import TextField from '../components/ui/TextField';
import { errorMessage } from '../lib/errors';

export default function LoginPage() {
  const { user, signIn } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const from = (location.state as { from?: string } | null)?.from ?? '/';
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  if (user) return <Navigate to={from} replace />;

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    if (!username.trim() || !password) {
      setError('กรอกชื่อผู้ใช้และรหัสผ่าน');
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await signIn(username, password);
      navigate(from, { replace: true });
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setBusy(false);
    }
  };

  return (
    <main className="flex min-h-[100dvh] flex-col items-center justify-center bg-container px-4 py-10 sm:bg-page">
      <form
        onSubmit={submit}
        noValidate
        className="fade-in w-full max-w-md rounded-[28px] bg-surface px-6 py-10 sm:border sm:border-border/70 sm:px-10"
      >
        <LogoMark size={40} />
        <h1 className="mt-6 text-[2rem] font-normal leading-tight text-ink">ลงชื่อเข้าใช้</h1>
        <p className="mt-2 text-base text-muted">ใช้บัญชีเดียวกับระบบ GoldenMole เพื่อจัดการอัลบั้มรูป</p>

        <div className="mt-8 space-y-5">
          <TextField
            label="ชื่อผู้ใช้"
            autoComplete="username"
            autoCapitalize="none"
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            autoFocus
          />
          <TextField
            label="รหัสผ่าน"
            type={showPassword ? 'text' : 'password'}
            autoComplete="current-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            error={error}
            trailing={
              <IconButton label={showPassword ? 'ซ่อนรหัสผ่าน' : 'แสดงรหัสผ่าน'} onClick={() => setShowPassword((v) => !v)} className="mr-1">
                {showPassword ? <EyeOff size={20} aria-hidden /> : <Eye size={20} aria-hidden />}
              </IconButton>
            }
          />
        </div>

        <div className="mt-10 flex justify-end">
          <Button type="submit" disabled={busy} className="min-w-28">
            {busy ? 'กำลังเข้าสู่ระบบ…' : 'ถัดไป'}
          </Button>
        </div>
      </form>
      <nav className="mt-6 flex gap-6 text-xs">
        <Link to="/privacy" className="text-muted hover:text-primary hover:underline">นโยบายความเป็นส่วนตัว</Link>
        <Link to="/terms" className="text-muted hover:text-primary hover:underline">ข้อกำหนดการใช้งาน</Link>
      </nav>
    </main>
  );
}
