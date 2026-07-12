import { useCallback, useEffect, useState } from 'react';
import { Lock, Shield } from 'lucide-react';
import Card from '../../components/ui/Card';
import Button from '../../components/ui/Button';
import {
    SHARE_PIN_MAX_LENGTH,
    SHARE_PIN_MIN_LENGTH,
    attemptSharePinUnlock,
    getSharePinLockRemainMs,
} from '../../utils/shareAuth';

interface SharePinGateProps {
    token: string;
    pinHash: string | null;
    onUnlocked: () => void;
}

const SharePinGate = ({ token, pinHash, onUnlocked }: SharePinGateProps) => {
    const [pinInput, setPinInput] = useState('');
    const [error, setError] = useState<string | null>(null);
    const [lockRemain, setLockRemain] = useState(0);
    const [submitting, setSubmitting] = useState(false);

    useEffect(() => {
        const tick = () => setLockRemain(Math.ceil(getSharePinLockRemainMs(token) / 1000));
        tick();
        const id = window.setInterval(tick, 500);
        return () => window.clearInterval(id);
    }, [token]);

    const touchFeedback = useCallback(() => {
        if (typeof navigator !== 'undefined' && 'vibrate' in navigator) {
            navigator.vibrate(12);
        }
    }, []);

    const appendDigit = useCallback((digit: string) => {
        if (!/^\d$/.test(digit)) return;
        setPinInput((prev) => (prev.length >= SHARE_PIN_MAX_LENGTH ? prev : `${prev}${digit}`));
        setError(null);
    }, []);

    const backspace = useCallback(() => {
        setPinInput((prev) => prev.slice(0, -1));
        setError(null);
    }, []);

    const clearInput = useCallback(() => {
        setPinInput('');
        setError(null);
    }, []);

    const submit = useCallback(async () => {
        if (pinInput.length < SHARE_PIN_MIN_LENGTH || submitting) return;
        setSubmitting(true);
        const result = await attemptSharePinUnlock(token, pinHash, pinInput);
        setSubmitting(false);
        if (result.ok) {
            setPinInput('');
            onUnlocked();
            return;
        }
        setError(result.message);
        setPinInput('');
        if (result.lockRemainMs) {
            setLockRemain(Math.ceil(result.lockRemainMs / 1000));
        }
    }, [onUnlocked, pinHash, pinInput, submitting, token]);

    return (
        <div className="flex min-h-[100dvh] items-center justify-center bg-gradient-to-br from-slate-950 via-slate-900 to-indigo-950 px-4 py-safe-top pb-safe-bottom">
            <Card className="w-full max-w-sm overflow-hidden border border-white/10 bg-white/95 p-0 shadow-2xl">
                <div className="bg-gradient-to-r from-indigo-600 via-violet-600 to-indigo-700 px-6 py-5 text-white">
                    <div className="flex items-center gap-2">
                        <Shield size={20} />
                        <h1 className="text-xl font-extrabold tracking-tight">แดชบอร์ด Real-time</h1>
                    </div>
                    <p className="mt-1 text-sm text-indigo-100">กรอกรหัส PIN เพื่อดูข้อมูลแบบเรียลไทม์</p>
                </div>

                <div className="p-5">
                    <div className="mb-4 rounded-2xl border border-slate-200/80 bg-gradient-to-b from-white to-slate-50 p-3 shadow-inner">
                        <div className="mb-1 flex items-center justify-between px-1">
                            <span className="flex items-center gap-1.5 text-[11px] font-semibold uppercase tracking-wide text-slate-500">
                                <Lock size={12} />
                                PIN
                            </span>
                            <span className="text-[11px] font-medium text-slate-400">{pinInput.length}/{SHARE_PIN_MAX_LENGTH}</span>
                        </div>
                        <div className="flex items-center justify-center gap-2">
                            {Array.from({ length: SHARE_PIN_MAX_LENGTH }).map((_, idx) => {
                                const filled = idx < pinInput.length;
                                const active = idx === pinInput.length && pinInput.length < SHARE_PIN_MAX_LENGTH;
                                return (
                                    <div
                                        key={idx}
                                        className={`flex h-11 w-10 items-center justify-center rounded-xl border text-lg font-black transition-all ${
                                            filled
                                                ? 'border-indigo-400/80 bg-indigo-50 text-indigo-600 shadow-[0_0_0_3px_rgba(99,102,241,0.18)]'
                                                : active
                                                  ? 'border-violet-300 bg-violet-50 text-violet-500 shadow-[0_0_0_2px_rgba(139,92,246,0.18)]'
                                                  : 'border-slate-200 bg-white text-transparent'
                                        }`}
                                    >
                                        {filled ? '•' : ' '}
                                    </div>
                                );
                            })}
                        </div>
                    </div>

                    <p className="mb-3 text-center text-xs font-medium text-slate-500">
                        แตะตัวเลขบนหน้าจอ — เหมาะสำหรับมือถือ
                    </p>

                    {lockRemain > 0 && (
                        <p className="mb-3 rounded-lg border border-rose-300/60 bg-rose-50 px-3 py-2 text-center text-xs font-semibold text-rose-600">
                            ล็อกอยู่ {lockRemain} วินาที
                        </p>
                    )}

                    {error && (
                        <p className="mb-3 rounded-lg border border-amber-300/60 bg-amber-50 px-3 py-2 text-center text-xs font-semibold text-amber-700">
                            {error}
                        </p>
                    )}

                    <div className="grid touch-manipulation select-none grid-cols-3 gap-2">
                        {['1', '2', '3', '4', '5', '6', '7', '8', '9', 'ล้าง', '0', 'OK'].map((key) => {
                            const isAction = key === 'ล้าง' || key === 'OK';
                            return (
                                <button
                                    key={key}
                                    type="button"
                                    disabled={
                                        lockRemain > 0 ||
                                        submitting ||
                                        (key === 'OK' && pinInput.length < SHARE_PIN_MIN_LENGTH)
                                    }
                                    onClick={() => {
                                        touchFeedback();
                                        if (key === 'ล้าง') {
                                            clearInput();
                                            return;
                                        }
                                        if (key === 'OK') {
                                            void submit();
                                            return;
                                        }
                                        appendDigit(key);
                                    }}
                                    className={`min-h-[56px] rounded-xl border text-base font-bold transition-all active:scale-[0.98] ${
                                        isAction
                                            ? 'border-indigo-300 bg-indigo-50 text-indigo-700 hover:bg-indigo-100'
                                            : 'border-slate-200 bg-white text-slate-800 hover:border-slate-300 hover:bg-slate-50'
                                    } disabled:cursor-not-allowed disabled:opacity-45`}
                                >
                                    {key}
                                </button>
                            );
                        })}
                    </div>

                    <div className="mt-2 flex gap-2">
                        <button
                            type="button"
                            onClick={backspace}
                            disabled={lockRemain > 0 || pinInput.length === 0}
                            className="min-h-[44px] flex-1 rounded-xl border border-slate-200 bg-white text-sm font-semibold text-slate-700 transition-all active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-45"
                        >
                            ลบทีละตัว
                        </button>
                        <Button
                            className="min-h-[44px] flex-1"
                            onClick={() => void submit()}
                            disabled={lockRemain > 0 || pinInput.length < SHARE_PIN_MIN_LENGTH || submitting}
                        >
                            เปิดดู
                        </Button>
                    </div>
                </div>
            </Card>
        </div>
    );
};

export default SharePinGate;
