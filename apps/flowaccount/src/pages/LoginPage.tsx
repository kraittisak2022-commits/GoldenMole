import { FormEvent, useId, useState } from 'react';
import { Navigate, useLocation, useNavigate } from 'react-router-dom';
import { Loader2 } from 'lucide-react';
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
    <div className="flex min-h-screen min-h-[100dvh] items-center justify-center bg-page px-4 py-10">
      <div className="w-full max-w-md">
        <div className="mb-8 text-center">
          <p className="text-xs font-medium uppercase tracking-wider text-muted">GoldenMole</p>
          <h1 className="mt-2 text-3xl font-semibold tracking-tight text-ink">FlowAccount</h1>
          <p className="mt-2 text-sm text-muted">ระบบงานบัญชี — เข้าสู่ระบบด้วยบัญชี SuperAdmin</p>
        </div>

        <Card className="p-6 sm:p-8">
          <form onSubmit={handleSubmit} className="flex flex-col gap-5" noValidate>
            <Field id={usernameId} label="ชื่อผู้ใช้">
              <Input
                id={usernameId}
                name="username"
                autoComplete="username"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                invalid={!!error}
                aria-invalid={!!error}
                aria-describedby={error ? formErrorId : undefined}
                disabled={isLoading}
              />
            </Field>

            <Field id={passwordId} label="รหัสผ่าน">
              <Input
                id={passwordId}
                name="password"
                type="password"
                autoComplete="current-password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                invalid={!!error}
                aria-invalid={!!error}
                aria-describedby={error ? formErrorId : undefined}
                disabled={isLoading}
              />
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
      </div>
    </div>
  );
}
