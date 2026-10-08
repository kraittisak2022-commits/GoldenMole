import { FormEvent, KeyboardEvent, useEffect, useState } from 'react';
import { Navigate, useLocation, useNavigate } from 'react-router-dom';
import { Eye, EyeOff, Loader2, Lock, User } from 'lucide-react';
import { useAuth } from '../auth/AuthProvider';
import Button from '../components/ui/Button';
import Field from '../components/ui/Field';
import Input from '../components/ui/Input';
import { ErrorBox } from '../components/ui/States';

const HERO_THEME = '#1E3A5F';

/** Neutral app mark (same glyph as the public icons) — never the company logo. */
function AppMark() {
  return (
    <span className="flex h-16 w-16 items-center justify-center rounded-2xl bg-white/10 ring-1 ring-white/20 backdrop-blur-sm short:h-12 short:w-12">
      <svg viewBox="4 8 36 34" className="h-9 w-9 short:h-7 short:w-7" aria-hidden>
        <path d="M14 34 25.5 13 38 34Z" fill="currentColor" opacity="0.55" />
        <path d="M5 34 17 10 29 34Z" fill="currentColor" />
        <rect x="5" y="37" width="33" height="3" rx="1.5" fill="currentColor" />
      </svg>
    </span>
  );
}

function HeroPiles() {
  return (
    <svg
      viewBox="0 0 400 120"
      preserveAspectRatio="none"
      className="pointer-events-none absolute inset-x-0 bottom-0 h-28 w-full text-white lg:h-64"
      aria-hidden
    >
      <path d="M0 120 90 46 150 92 230 30 320 100 400 64V120Z" fill="currentColor" opacity="0.05" />
      <path d="M0 120 60 84 130 110 210 70 300 112 400 90V120Z" fill="currentColor" opacity="0.06" />
    </svg>
  );
}

/** Tints the mobile browser bar to match the hero while the login page is shown. */
function useThemeColor(color: string) {
  useEffect(() => {
    const meta = document.head.querySelector<HTMLMetaElement>('meta[name="theme-color"]');
    if (!meta) return;
    const previous = meta.content;
    meta.content = color;
    return () => {
      meta.content = previous;
    };
  }, [color]);
}

export default function LoginPage() {
  const { status, signIn } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [capsLock, setCapsLock] = useState(false);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  useThemeColor(HERO_THEME);

  const from = (location.state as { from?: string } | null)?.from || '/';
  if (status === 'authenticated') return <Navigate to={from} replace />;

  const onSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setError('');
    setBusy(true);
    try {
      await signIn(username, password);
      navigate(from, { replace: true });
    } catch (err) {
      setError(err instanceof Error ? err.message : 'เข้าสู่ระบบไม่สำเร็จ');
    } finally {
      setBusy(false);
    }
  };

  const trackCapsLock = (e: KeyboardEvent<HTMLInputElement>) => setCapsLock(e.getModifierState('CapsLock'));

  return (
    <div className="flex min-h-[100dvh] flex-col bg-subtle lg:grid lg:grid-cols-[1.1fr_1fr]">
      <header className="login-hero relative overflow-hidden px-6 pb-20 pt-[calc(env(safe-area-inset-top)+3.5rem)] text-white short:pb-14 short:pt-6 lg:flex lg:flex-col lg:justify-between lg:p-14">
        <HeroPiles />
        <div className="relative flex flex-col items-center text-center lg:items-start lg:text-left">
          <AppMark />
          <h1 className="mt-5 text-2xl font-semibold tracking-tight short:mt-3 short:text-xl lg:mt-8 lg:text-4xl lg:leading-tight">
            ระบบจัดการออเดอร์
            <br className="hidden lg:block" /> หิน-ทราย
          </h1>
          <p className="mt-2 text-sm text-white/70 short:hidden lg:mt-3 lg:text-base">สำหรับเจ้าหน้าที่เท่านั้น</p>
        </div>
        <p className="relative hidden text-sm text-white/50 lg:block">© {new Date().getFullYear() + 543}</p>
      </header>

      <main className="relative -mt-10 flex flex-1 justify-center px-4 pb-8 lg:mt-0 lg:items-center lg:bg-surface lg:px-12 lg:pb-0">
        <div className="login-card h-fit w-full max-w-sm rounded-2xl bg-surface p-6 shadow-xl shadow-ink/5 ring-1 ring-border xs:p-7 lg:p-0 lg:shadow-none lg:ring-0">
          <h2 className="text-xl font-semibold tracking-tight lg:text-2xl">เข้าสู่ระบบ</h2>
          <p className="mt-1 text-sm text-muted">กรอกชื่อผู้ใช้และรหัสผ่านเพื่อใช้งาน</p>

          <form onSubmit={onSubmit} className="mt-6 flex flex-col gap-4" noValidate>
            <Field id="username" label="ชื่อผู้ใช้">
              <div className="relative">
                <User size={18} className="pointer-events-none absolute left-3.5 top-1/2 -translate-y-1/2 text-muted" aria-hidden />
                <Input
                  id="username"
                  autoComplete="username"
                  autoCapitalize="none"
                  autoCorrect="off"
                  spellCheck={false}
                  value={username}
                  onChange={(e) => {
                    setUsername(e.target.value);
                    setError('');
                  }}
                  invalid={Boolean(error)}
                  className="pl-11"
                />
              </div>
            </Field>
            <Field id="password" label="รหัสผ่าน">
              <div className="relative">
                <Lock size={18} className="pointer-events-none absolute left-3.5 top-1/2 -translate-y-1/2 text-muted" aria-hidden />
                <Input
                  id="password"
                  type={showPassword ? 'text' : 'password'}
                  autoComplete="current-password"
                  value={password}
                  onChange={(e) => {
                    setPassword(e.target.value);
                    setError('');
                  }}
                  onKeyUp={trackCapsLock}
                  onKeyDown={trackCapsLock}
                  onBlur={() => setCapsLock(false)}
                  invalid={Boolean(error)}
                  className="pl-11 pr-12"
                />
                <button
                  type="button"
                  onClick={() => setShowPassword((v) => !v)}
                  aria-label={showPassword ? 'ซ่อนรหัสผ่าน' : 'แสดงรหัสผ่าน'}
                  aria-pressed={showPassword}
                  className="absolute right-1.5 top-1/2 flex h-9 w-9 -translate-y-1/2 items-center justify-center rounded-lg text-muted transition hover:bg-subtle hover:text-ink"
                >
                  {showPassword ? <EyeOff size={18} aria-hidden /> : <Eye size={18} aria-hidden />}
                </button>
              </div>
              {capsLock ? <p className="text-xs font-medium text-warning">Caps Lock เปิดอยู่</p> : null}
            </Field>
            {error ? <ErrorBox message={error} /> : null}
            <Button type="submit" size="lg" disabled={busy} className="mt-2 w-full shadow-lg shadow-primary/20">
              {busy ? (
                <>
                  <Loader2 size={18} className="animate-spin" aria-hidden />
                  กำลังเข้าสู่ระบบ…
                </>
              ) : (
                'เข้าสู่ระบบ'
              )}
            </Button>
          </form>
        </div>
      </main>
      <p className="pb-[calc(env(safe-area-inset-bottom)+1rem)] text-center text-xs text-muted/70 lg:hidden">
        © {new Date().getFullYear() + 543}
      </p>
    </div>
  );
}
