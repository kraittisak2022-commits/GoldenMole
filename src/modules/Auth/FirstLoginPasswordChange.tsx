import { useState } from 'react';
import { Lock, Eye, EyeOff, Shield, Loader2, Sun, Moon, KeyRound } from 'lucide-react';
import { validateNewPasswordPolicy } from '../../utils/passwordAuth';

interface FirstLoginPasswordChangeProps {
    displayName: string;
    username: string;
    darkMode: boolean;
    onToggleDarkMode: () => void;
    onComplete: (newPassword: string) => Promise<void>;
}

const FirstLoginPasswordChange = ({
    displayName,
    username,
    darkMode,
    onToggleDarkMode,
    onComplete,
}: FirstLoginPasswordChangeProps) => {
    const [password, setPassword] = useState('');
    const [confirm, setConfirm] = useState('');
    const [showPassword, setShowPassword] = useState(false);
    const [error, setError] = useState('');
    const [loading, setLoading] = useState(false);

    const inputBase =
        'w-full rounded-2xl pl-12 pr-4 text-[15px] transition-all duration-200 focus:outline-none focus:ring-2 focus:ring-offset-0 ';

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault();
        setError('');
        if (password !== confirm) {
            setError('รหัสผ่านใหม่ไม่ตรงกัน');
            return;
        }
        const policy = validateNewPasswordPolicy(password);
        if (!policy.ok) {
            setError(policy.message);
            return;
        }
        setLoading(true);
        try {
            await onComplete(password);
        } catch {
            setError('ไม่สามารถบันทึกรหัสผ่านได้ กรุณาลองอีกครั้ง');
        } finally {
            setLoading(false);
        }
    };

    return (
        <div
            className={`relative flex min-h-screen min-h-[100dvh] flex-col items-center justify-center overflow-hidden px-4 py-10 transition-colors duration-500 ${darkMode ? 'app-shell-dark' : 'app-shell-light'}`}
        >
            <button
                type="button"
                onClick={onToggleDarkMode}
                aria-label={darkMode ? 'สลับเป็นโหมดสว่าง' : 'สลับเป็นโหมดมืด'}
                className={`fixed right-4 top-4 z-50 flex h-11 w-11 items-center justify-center rounded-2xl border shadow-lg backdrop-blur-md transition-all ${darkMode
                    ? 'border-white/10 bg-white/[0.07] text-amber-200/90 hover:border-cyan-400/30'
                    : 'border-stone-200/80 bg-white/70 text-stone-600'
                    }`}
            >
                {darkMode ? <Sun size={18} /> : <Moon size={18} />}
            </button>

            <main className="relative z-10 w-full max-w-[440px]">
                <article
                    className={`relative overflow-hidden rounded-[1.75rem] border shadow-2xl ${darkMode
                        ? 'border-white/[0.09] bg-slate-950/55 shadow-black/40'
                        : 'border-stone-200/70 bg-white/90'
                        }`}
                    style={{ backdropFilter: 'blur(28px)' }}
                >
                    <div className="px-6 pb-8 pt-8 sm:px-8">
                        <div className="mb-6 flex justify-center">
                            <div
                                className={`flex h-14 w-14 items-center justify-center rounded-2xl ${darkMode ? 'bg-cyan-500/15 text-cyan-300' : 'bg-amber-100 text-amber-700'}`}
                            >
                                <KeyRound size={28} />
                            </div>
                        </div>
                        <header className="mb-6 text-center">
                            <h1 className={`text-xl font-bold ${darkMode ? 'text-white' : 'text-stone-900'}`}>
                                ตั้งรหัสผ่านใหม่
                            </h1>
                            <p className={`mt-2 text-sm leading-relaxed ${darkMode ? 'text-slate-400' : 'text-stone-600'}`}>
                                บัญชี <span className="font-semibold text-amber-600 dark:text-amber-400/90">@{username}</span> ({displayName}) ต้องเปลี่ยนรหัสผ่านก่อนเข้าใช้งานครั้งแรก
                            </p>
                        </header>

                        <form onSubmit={handleSubmit} className="space-y-4">
                            <div>
                                <label className={`mb-1.5 block text-[11px] font-semibold uppercase tracking-[0.14em] ${darkMode ? 'text-slate-400' : 'text-stone-500'}`}>
                                    รหัสผ่านใหม่
                                </label>
                                <div className="group relative">
                                    <div className={`pointer-events-none absolute left-4 top-1/2 z-[1] -translate-y-1/2 ${darkMode ? 'text-slate-500' : 'text-stone-400'}`}>
                                        <Lock size={18} />
                                    </div>
                                    <input
                                        type={showPassword ? 'text' : 'password'}
                                        autoComplete="new-password"
                                        value={password}
                                        onChange={e => setPassword(e.target.value)}
                                        className={`${inputBase} h-[52px] pr-12 ${darkMode
                                            ? 'border border-white/[0.1] bg-white/[0.05] text-white placeholder:text-slate-500 focus:border-cyan-500/35 focus:ring-cyan-500/25'
                                            : 'border border-stone-200/90 bg-white/90 text-stone-900 focus:border-amber-400/80 focus:ring-amber-400/25'
                                            }`}
                                        placeholder="อย่างน้อย 8 ตัวอักษร"
                                    />
                                    <button
                                        type="button"
                                        onClick={() => setShowPassword(!showPassword)}
                                        className={`absolute right-3 top-1/2 z-[1] -translate-y-1/2 rounded-lg p-1.5 ${darkMode ? 'text-slate-500 hover:bg-white/10' : 'text-stone-400 hover:bg-stone-100'}`}
                                    >
                                        {showPassword ? <EyeOff size={18} /> : <Eye size={18} />}
                                    </button>
                                </div>
                            </div>
                            <div>
                                <label className={`mb-1.5 block text-[11px] font-semibold uppercase tracking-[0.14em] ${darkMode ? 'text-slate-400' : 'text-stone-500'}`}>
                                    ยืนยันรหัสผ่าน
                                </label>
                                <div className="relative">
                                    <div className={`pointer-events-none absolute left-4 top-1/2 z-[1] -translate-y-1/2 ${darkMode ? 'text-slate-500' : 'text-stone-400'}`}>
                                        <Lock size={18} />
                                    </div>
                                    <input
                                        type={showPassword ? 'text' : 'password'}
                                        autoComplete="new-password"
                                        value={confirm}
                                        onChange={e => setConfirm(e.target.value)}
                                        className={`${inputBase} h-[52px] ${darkMode
                                            ? 'border border-white/[0.1] bg-white/[0.05] text-white placeholder:text-slate-500 focus:border-cyan-500/35 focus:ring-cyan-500/25'
                                            : 'border border-stone-200/90 bg-white/90 text-stone-900 focus:border-amber-400/80 focus:ring-amber-400/25'
                                            }`}
                                        placeholder="พิมพ์รหัสเดิมอีกครั้ง"
                                    />
                                </div>
                            </div>

                            {error && (
                                <div
                                    role="alert"
                                    className={`flex gap-3 rounded-2xl border px-4 py-3 text-sm ${darkMode
                                        ? 'border-red-500/30 bg-red-500/[0.08] text-red-200/95'
                                        : 'border-red-200 bg-red-50 text-red-800'
                                        }`}
                                >
                                    <Shield size={18} className="mt-0.5 shrink-0" />
                                    <span>{error}</span>
                                </div>
                            )}

                            <button
                                type="submit"
                                disabled={loading || !password || !confirm}
                                className={`mt-2 flex w-full items-center justify-center gap-2 rounded-2xl py-3.5 text-[15px] font-bold text-white shadow-lg transition-all disabled:cursor-not-allowed disabled:opacity-55 ${darkMode
                                    ? 'bg-gradient-to-r from-sky-600 to-violet-600 hover:brightness-110'
                                    : 'bg-gradient-to-r from-amber-600 to-amber-800 hover:brightness-105'
                                    }`}
                            >
                                {loading ? (
                                    <>
                                        <Loader2 size={20} className="animate-spin" />
                                        กำลังบันทึก...
                                    </>
                                ) : (
                                    'บันทึกรหัสผ่านและเข้าสู่ระบบ'
                                )}
                            </button>
                        </form>
                    </div>
                </article>
            </main>
        </div>
    );
};

export default FirstLoginPasswordChange;
