import { FormEvent, useId, useState } from 'react';
import { Navigate, useLocation, useNavigate } from 'react-router-dom';
import { Check, Eye, EyeOff, Loader2, Lock, User } from 'lucide-react';
import { SignInError } from '../auth/adminAuthService';
import { useAuth } from '../auth/AuthProvider';
import Button from '../components/ui/Button';
import Card from '../components/ui/Card';
import Field from '../components/ui/Field';
import Input from '../components/ui/Input';
import LoginAmbient from './login/LoginAmbient';
import LoginHeroPanel from './login/LoginHeroPanel';

function inputFillPct(value: string, maxChars = 28) {
  return Math.min(100, (value.length / maxChars) * 100);
}

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
  const [succeeded, setSucceeded] = useState(false);
  const [shake, setShake] = useState(false);
  const [userKeyBurst, setUserKeyBurst] = useState(0);
  const [passKeyBurst, setPassKeyBurst] = useState(0);

  if (status === 'authenticated') {
    return <Navigate to={from} replace />;
  }

  const triggerShake = () => {
    setShake(true);
    window.setTimeout(() => setShake(false), 560);
  };

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError('');
    setIsLoading(true);
    try {
      await signIn(username, password);
      setSucceeded(true);
      await new Promise((resolve) => window.setTimeout(resolve, 250));
      navigate(from, { replace: true });
    } catch (err) {
      if (err instanceof SignInError) {
        setError(err.message);
      } else {
        setError('เกิดข้อผิดพลาด กรุณาลองใหม่');
      }
      triggerShake();
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="relative flex min-h-screen min-h-[100dvh] overflow-hidden bg-page">
      <LoginAmbient />

      <div className="relative z-10 flex w-full flex-col md:flex-row">
        <aside className="relative border-b border-border/60 md:w-[46%] md:min-h-[100dvh] md:border-b-0 md:border-r md:border-border/50">
          <LoginHeroPanel />
        </aside>

        <main className="relative flex flex-1 items-center justify-center px-4 py-8 sm:px-8 md:py-12">
          <div className="w-full max-w-md animate-login-enter" style={{ animationDelay: '120ms' }}>
            <div className={shake ? 'animate-login-shake' : undefined}>
              <div className="mb-6 md:mb-8">
                <p className="text-xs font-medium uppercase tracking-wider text-muted md:hidden">
                  เข้าสู่ระบบ
                </p>
                <h2 className="mt-1 text-2xl font-semibold tracking-tight text-ink">
                  ยินดีต้อนรับกลับ
                </h2>
                <p className="mt-1.5 text-sm text-muted">
                  กรอกชื่อผู้ใช้และรหัสผ่าน SuperAdmin เพื่อดำเนินการต่อ
                </p>
              </div>

              <Card className="relative overflow-hidden shadow-sm shadow-slate-200/60">
                <div
                  className="h-1 w-full animate-login-shimmer"
                  style={{
                    backgroundImage:
                      'linear-gradient(90deg, transparent, var(--color-accent), var(--color-gold), var(--color-accent), transparent)',
                    backgroundSize: '200% 100%',
                  }}
                  aria-hidden
                />

                <div className="pointer-events-none absolute inset-0 overflow-hidden" aria-hidden>
                  <div className="absolute left-0 right-0 h-px bg-gradient-to-r from-transparent via-accent/20 to-transparent animate-login-scan" />
                </div>

                <form
                  onSubmit={handleSubmit}
                  className="relative flex flex-col gap-5 p-6 sm:p-8"
                  noValidate
                  aria-busy={isLoading || succeeded}
                >
                  <Field id={usernameId} label="ชื่อผู้ใช้">
                    <div className="group relative">
                      {userKeyBurst > 0 ? (
                        <div
                          key={userKeyBurst}
                          className="pointer-events-none absolute inset-0 z-[1] rounded-DEFAULT animate-login-keystroke"
                          aria-hidden
                        />
                      ) : null}
                      <span className="pointer-events-none absolute left-3 top-1/2 z-[2] -translate-y-1/2 text-muted transition-colors duration-200 group-focus-within:text-accent">
                        <span key={userKeyBurst} className="inline-flex login-icon-typing">
                          <User size={16} aria-hidden />
                        </span>
                      </span>
                      <Input
                        id={usernameId}
                        name="username"
                        autoComplete="username"
                        placeholder="ชื่อผู้ใช้"
                        value={username}
                        onChange={(e) => setUsername(e.target.value)}
                        onKeyDown={() => setUserKeyBurst((k) => k + 1)}
                        invalid={!!error}
                        aria-invalid={!!error}
                        aria-describedby={error ? formErrorId : undefined}
                        disabled={isLoading || succeeded}
                        className="pl-10"
                      />
                      <div className="mt-1.5 h-0.5 overflow-hidden rounded-full bg-border/60" aria-hidden>
                        <div
                          className={`h-full origin-left rounded-full bg-accent/70 transition-[width] duration-200 ease-out ${
                            username.length > 0 ? 'login-input-bar-pulse' : ''
                          }`}
                          style={{ width: `${inputFillPct(username)}%` }}
                        />
                      </div>
                    </div>
                  </Field>

                  <Field id={passwordId} label="รหัสผ่าน">
                    <div className="group relative">
                      {passKeyBurst > 0 ? (
                        <div
                          key={passKeyBurst}
                          className="pointer-events-none absolute inset-0 z-[1] rounded-DEFAULT animate-login-keystroke"
                          aria-hidden
                        />
                      ) : null}
                      <span className="pointer-events-none absolute left-3 top-1/2 z-[2] -translate-y-1/2 text-muted transition-colors duration-200 group-focus-within:text-accent">
                        <span key={passKeyBurst} className="inline-flex login-icon-typing">
                          <Lock size={16} aria-hidden />
                        </span>
                      </span>
                      <Input
                        id={passwordId}
                        name="password"
                        type={showPassword ? 'text' : 'password'}
                        autoComplete="current-password"
                        placeholder="รหัสผ่าน"
                        value={password}
                        onChange={(e) => setPassword(e.target.value)}
                        onKeyDown={() => setPassKeyBurst((k) => k + 1)}
                        invalid={!!error}
                        aria-invalid={!!error}
                        aria-describedby={error ? formErrorId : undefined}
                        disabled={isLoading || succeeded}
                        className="pl-10 pr-11"
                      />
                      <button
                        type="button"
                        className="absolute right-2 top-1/2 z-[2] flex h-8 w-8 -translate-y-1/2 items-center justify-center rounded-DEFAULT text-muted transition-colors hover:bg-slate-100 hover:text-ink disabled:cursor-not-allowed disabled:opacity-50"
                        onClick={() => setShowPassword((visible) => !visible)}
                        disabled={isLoading || succeeded}
                        aria-label={showPassword ? 'ซ่อนรหัสผ่าน' : 'แสดงรหัสผ่าน'}
                        aria-pressed={showPassword}
                      >
                        {showPassword ? (
                          <EyeOff size={16} aria-hidden />
                        ) : (
                          <Eye size={16} aria-hidden />
                        )}
                      </button>
                      <div className="mt-1.5 h-0.5 overflow-hidden rounded-full bg-border/60" aria-hidden>
                        <div
                          className={`h-full origin-left rounded-full bg-accent/70 transition-[width] duration-200 ease-out ${
                            password.length > 0 ? 'login-input-bar-pulse' : ''
                          }`}
                          style={{ width: `${inputFillPct(password)}%` }}
                        />
                      </div>
                    </div>
                  </Field>

                  {error ? (
                    <p id={formErrorId} role="alert" className="text-sm text-destructive">
                      {error}
                    </p>
                  ) : null}

                  <Button
                    type="submit"
                    className="login-btn-shine w-full"
                    disabled={isLoading || succeeded}
                  >
                    {succeeded ? (
                      <>
                        <Check size={16} aria-hidden />
                        สำเร็จ
                      </>
                    ) : isLoading ? (
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
        </main>
      </div>
    </div>
  );
}
