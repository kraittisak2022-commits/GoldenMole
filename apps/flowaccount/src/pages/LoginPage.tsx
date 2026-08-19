import { FormEvent, useId, useState } from 'react';
import { Navigate, useLocation, useNavigate } from 'react-router-dom';
import { Eye, EyeOff, Loader2, Wallet } from 'lucide-react';
import { SignInError } from '../auth/adminAuthService';
import { useAuth } from '../auth/AuthProvider';
import Button from '../components/ui/Button';
import Card from '../components/ui/Card';
import Field from '../components/ui/Field';
import Input from '../components/ui/Input';

export default function LoginPage() {
  const { status, signIn } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const from = (location.state as { from?: string } | null)?.from || '/';

  const usernameId = useId();
  const passwordId = useId();
  const formErrorId = useId();

  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState('');
  const [isLoading, setIsLoading] = useState(false);

  if (status === 'authenticated') {
    return <Navigate to={from} replace />;
  }

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError('');
    setIsLoading(true);
    try {
      await signIn(username, password);
      navigate(from, { replace: true });
    } catch (err) {
      if (err instanceof SignInError) {
        setError(err.message);
      } else {
        setError('เกิดข้อผิดพลาด กรุณาลองใหม่');
      }
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="relative flex min-h-screen min-h-[100dvh] items-center justify-center overflow-hidden bg-page px-4 py-10">
      <div className="pointer-events-none absolute inset-0" aria-hidden>
        <div className="absolute -left-24 -top-24 h-80 w-80 rounded-full bg-accent/10 blur-3xl" />
        <div className="absolute -bottom-32 -right-16 h-96 w-96 rounded-full bg-accent/5 blur-3xl" />
      </div>

      <div className="relative w-full max-w-md">
        <div className="mb-8 text-center">
          <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-DEFAULT bg-accent text-accent-foreground">
            <Wallet size={22} aria-hidden />
          </div>
          <p className="mt-4 text-xs font-medium uppercase tracking-wider text-muted">GoldenMole</p>
          <h1 className="mt-2 text-3xl font-semibold tracking-tight text-ink">FlowAccount</h1>
          <p className="mt-2 text-sm text-muted">ระบบงานบัญชี — เข้าสู่ระบบด้วยบัญชี SuperAdmin</p>
        </div>

        <Card className="overflow-hidden shadow-sm">
          <div className="h-1 bg-accent" aria-hidden />
          <form onSubmit={handleSubmit} className="flex flex-col gap-5 p-6 sm:p-8" noValidate>
            <Field id={usernameId} label="ชื่อผู้ใช้">
              <Input
                id={usernameId}
                name="username"
                autoComplete="username"
                placeholder="ชื่อผู้ใช้"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                invalid={!!error}
                aria-invalid={!!error}
                aria-describedby={error ? formErrorId : undefined}
                disabled={isLoading}
              />
            </Field>

            <Field id={passwordId} label="รหัสผ่าน">
              <div className="relative">
                <Input
                  id={passwordId}
                  name="password"
                  type={showPassword ? 'text' : 'password'}
                  autoComplete="current-password"
                  placeholder="รหัสผ่าน"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  invalid={!!error}
                  aria-invalid={!!error}
                  aria-describedby={error ? formErrorId : undefined}
                  disabled={isLoading}
                  className="pr-11"
                />
                <button
                  type="button"
                  className="absolute right-2 top-1/2 flex h-8 w-8 -translate-y-1/2 items-center justify-center rounded-DEFAULT text-muted hover:bg-slate-100 hover:text-ink disabled:cursor-not-allowed disabled:opacity-50"
                  onClick={() => setShowPassword((visible) => !visible)}
                  disabled={isLoading}
                  aria-label={showPassword ? 'ซ่อนรหัสผ่าน' : 'แสดงรหัสผ่าน'}
                  aria-pressed={showPassword}
                >
                  {showPassword ? <EyeOff size={16} aria-hidden /> : <Eye size={16} aria-hidden />}
                </button>
              </div>
            </Field>

            {error ? (
              <p id={formErrorId} role="alert" className="text-sm text-destructive">
                {error}
              </p>
            ) : null}

            <Button type="submit" className="w-full" disabled={isLoading}>
              {isLoading ? (
                <>
                  <Loader2 size={16} className="animate-spin" aria-hidden />
                  กำลังเข้าสู่ระบบ…
                </>
              ) : (
                'เข้าสู่ระบบ'
              )}
            </Button>
          </form>
        </Card>

        <p className="mt-6 text-center text-xs text-muted">สิทธิ์เฉพาะ SuperAdmin</p>
      </div>
    </div>
  );
}
