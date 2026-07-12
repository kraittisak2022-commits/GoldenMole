import { useCallback, useEffect, useRef, useState } from 'react';
import { Delete, Shield } from 'lucide-react';
import {
    SHARE_PIN_MAX_LENGTH,
    SHARE_PIN_MIN_LENGTH,
    attemptSharePinUnlock,
    getSharePinLockRemainMs,
    markSharePinUnlocked,
    verifySharePinOnly,
} from '../../utils/shareAuth';
import { SharePreferenceControls, useShareLocale } from './shareI18n';

interface SharePinGateProps {
    token: string;
    pinHash: string | null;
    onUnlocked: () => void;
}

const SharePinGate = ({ token, pinHash, onUnlocked }: SharePinGateProps) => {
    const { t } = useShareLocale();
    const [pinInput, setPinInput] = useState('');
    const [error, setError] = useState<string | null>(null);
    const [lockRemain, setLockRemain] = useState(0);
    const [submitting, setSubmitting] = useState(false);
    const [shake, setShake] = useState(false);
    const verifyingRef = useRef(false);

    useEffect(() => {
        const tick = () => setLockRemain(Math.ceil(getSharePinLockRemainMs(token) / 1000));
        tick();
        const id = window.setInterval(tick, 500);
        return () => window.clearInterval(id);
    }, [token]);

    useEffect(() => {
        if (shake) {
            const id = window.setTimeout(() => setShake(false), 520);
            return () => window.clearTimeout(id);
        }
    }, [shake]);

    const touchFeedback = useCallback(() => {
        if (typeof navigator !== 'undefined' && 'vibrate' in navigator) {
            navigator.vibrate(12);
        }
    }, []);

    const triggerWrong = useCallback(
        (message: string) => {
            setError(message);
            setPinInput('');
            setShake(true);
            touchFeedback();
            if (typeof navigator !== 'undefined' && 'vibrate' in navigator) {
                navigator.vibrate([40, 60, 40]);
            }
        },
        [touchFeedback],
    );

    const tryUnlock = useCallback(
        async (pin: string, registerFailure: boolean) => {
            if (pin.length < SHARE_PIN_MIN_LENGTH || verifyingRef.current || lockRemain > 0) return;
            verifyingRef.current = true;
            setSubmitting(true);
            try {
                if (!registerFailure) {
                    const ok = await verifySharePinOnly(pinHash, pin);
                    if (ok) {
                        markSharePinUnlocked(token);
                        setPinInput('');
                        setError(null);
                        onUnlocked();
                        return;
                    }
                    if (pin.length < SHARE_PIN_MAX_LENGTH) return;
                }
                const result = await attemptSharePinUnlock(token, pinHash, pin);
                if (result.ok) {
                    setPinInput('');
                    setError(null);
                    onUnlocked();
                    return;
                }
                triggerWrong(
                    result.message === 'PIN ถูกล็อกชั่วคราว'
                        ? t('pinLockedShort')
                        : result.message === 'PIN ผิดเกินกำหนด ล็อกชั่วคราว 90 วินาที'
                          ? t('pinWrongMaxLock')
                          : t('pinWrong'),
                );
                if (result.lockRemainMs) {
                    setLockRemain(Math.ceil(result.lockRemainMs / 1000));
                }
            } finally {
                verifyingRef.current = false;
                setSubmitting(false);
            }
        },
        [lockRemain, onUnlocked, pinHash, t, token, triggerWrong],
    );

    useEffect(() => {
        if (pinInput.length < SHARE_PIN_MIN_LENGTH) return;
        void tryUnlock(pinInput, pinInput.length >= SHARE_PIN_MAX_LENGTH);
    }, [pinInput, tryUnlock]);

    useEffect(() => {
        const onKeyDown = (e: KeyboardEvent) => {
            if (lockRemain > 0 || submitting) return;
            if (/^\d$/.test(e.key)) {
                e.preventDefault();
                setPinInput((prev) => (prev.length >= SHARE_PIN_MAX_LENGTH ? prev : `${prev}${e.key}`));
                setError(null);
                return;
            }
            if (e.key === 'Backspace') {
                e.preventDefault();
                setPinInput((prev) => prev.slice(0, -1));
                setError(null);
                return;
            }
            if (e.key === 'Escape') {
                e.preventDefault();
                setPinInput('');
                setError(null);
            }
        };
        window.addEventListener('keydown', onKeyDown);
        return () => window.removeEventListener('keydown', onKeyDown);
    }, [lockRemain, submitting]);

    const appendDigit = useCallback(
        (digit: string) => {
            if (!/^\d$/.test(digit) || lockRemain > 0) return;
            touchFeedback();
            setPinInput((prev) => (prev.length >= SHARE_PIN_MAX_LENGTH ? prev : `${prev}${digit}`));
            setError(null);
        },
        [lockRemain, touchFeedback],
    );

    const backspace = useCallback(() => {
        if (lockRemain > 0) return;
        touchFeedback();
        setPinInput((prev) => prev.slice(0, -1));
        setError(null);
    }, [lockRemain, touchFeedback]);

    const clearInput = useCallback(() => {
        if (lockRemain > 0) return;
        touchFeedback();
        setPinInput('');
        setError(null);
    }, [lockRemain, touchFeedback]);

    return (
        <div className="relative flex min-h-[100dvh] items-center justify-center overflow-hidden bg-gradient-to-br from-slate-100 via-indigo-50 to-violet-100 px-4 py-safe-top pb-safe-bottom dark:from-slate-950 dark:via-slate-900 dark:to-indigo-950">
            <div className="pointer-events-none absolute inset-0 overflow-hidden">
                <div className="absolute -left-20 top-10 h-72 w-72 animate-pulse rounded-full bg-indigo-400/20 blur-3xl dark:bg-indigo-500/10" />
                <div className="absolute -right-16 bottom-10 h-80 w-80 animate-pulse rounded-full bg-violet-400/20 blur-3xl [animation-delay:1.2s] dark:bg-violet-500/10" />
            </div>

            <div className="absolute right-4 top-safe-top z-20 pt-4">
                <SharePreferenceControls />
            </div>

            <div className="relative z-10 w-full max-w-sm">
                <div className="overflow-hidden rounded-[28px] border border-white/60 bg-white/70 shadow-2xl shadow-indigo-900/10 backdrop-blur-xl dark:border-white/10 dark:bg-slate-900/70 dark:shadow-black/40">
                    <div className="relative px-6 pb-5 pt-8 text-center">
                        <div className="mx-auto mb-4 flex h-20 w-20 items-center justify-center rounded-full bg-gradient-to-br from-indigo-500 to-violet-600 shadow-lg shadow-indigo-500/30 ring-4 ring-indigo-200/50 dark:ring-indigo-500/20">
                            <div className="absolute inset-0 animate-ping rounded-full bg-indigo-400/20" />
                            <Shield size={34} className="relative text-white" />
                        </div>
                        <h1 className="text-xl font-extrabold tracking-tight text-slate-900 dark:text-white">{t('pinTitle')}</h1>
                        <p className="mt-1.5 text-sm text-slate-500 dark:text-slate-400">{t('pinSubtitle')}</p>
                    </div>

                    <div className="px-5 pb-5">
                        <div
                            className={`mb-4 rounded-2xl border border-slate-200/80 bg-slate-50/80 px-4 py-4 dark:border-slate-700/60 dark:bg-slate-800/50 ${shake ? 'animate-shake' : ''}`}
                        >
                            <div className="mb-3 flex items-center justify-between">
                                <span className="text-[11px] font-bold uppercase tracking-[0.16em] text-slate-400">PIN</span>
                                <span className="text-[11px] font-medium text-slate-400">
                                    {pinInput.length}/{SHARE_PIN_MAX_LENGTH}
                                </span>
                            </div>
                            <div className="flex items-center justify-center gap-2.5">
                                {Array.from({ length: SHARE_PIN_MAX_LENGTH }).map((_, idx) => {
                                    const filled = idx < pinInput.length;
                                    const active = idx === pinInput.length && pinInput.length < SHARE_PIN_MAX_LENGTH;
                                    return (
                                        <div
                                            key={idx}
                                            className={`flex h-12 w-11 items-center justify-center rounded-2xl border text-xl font-black transition-all duration-200 ${
                                                filled
                                                    ? 'scale-105 border-indigo-400 bg-indigo-500 text-white shadow-lg shadow-indigo-500/30'
                                                    : active
                                                      ? 'border-violet-300 bg-violet-50 text-violet-400 dark:border-violet-500/40 dark:bg-violet-500/10'
                                                      : 'border-slate-200 bg-white text-transparent dark:border-slate-600 dark:bg-slate-900'
                                            }`}
                                        >
                                            {filled ? '•' : ''}
                                        </div>
                                    );
                                })}
                            </div>
                        </div>

                        <p className="mb-3 text-center text-xs font-medium text-slate-500 dark:text-slate-400">{t('pinHint')}</p>

                        {lockRemain > 0 && (
                            <p className="mb-3 rounded-xl border border-rose-300/60 bg-rose-50 px-3 py-2 text-center text-xs font-semibold text-rose-600 dark:border-rose-500/30 dark:bg-rose-500/10 dark:text-rose-300">
                                {t('pinLocked', { seconds: lockRemain })}
                            </p>
                        )}

                        {error && (
                            <p className="mb-3 rounded-xl border border-amber-300/60 bg-amber-50 px-3 py-2 text-center text-xs font-semibold text-amber-700 dark:border-amber-500/30 dark:bg-amber-500/10 dark:text-amber-200">
                                {error}
                            </p>
                        )}

                        <div className="grid touch-manipulation select-none grid-cols-3 gap-2.5">
                            {['1', '2', '3', '4', '5', '6', '7', '8', '9'].map((key) => (
                                <button
                                    key={key}
                                    type="button"
                                    disabled={lockRemain > 0 || submitting}
                                    onClick={() => appendDigit(key)}
                                    className="flex h-14 w-full items-center justify-center rounded-full border border-slate-200/80 bg-white text-xl font-bold text-slate-800 shadow-sm transition-all active:scale-95 hover:border-indigo-200 hover:bg-indigo-50 disabled:cursor-not-allowed disabled:opacity-40 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-100 dark:hover:border-indigo-500/40 dark:hover:bg-indigo-500/10"
                                >
                                    {key}
                                </button>
                            ))}
                            <button
                                type="button"
                                disabled={lockRemain > 0 || submitting}
                                onClick={clearInput}
                                className="flex h-14 items-center justify-center rounded-full border border-slate-200/80 bg-slate-100 text-sm font-bold text-slate-600 transition-all active:scale-95 disabled:cursor-not-allowed disabled:opacity-40 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-300"
                            >
                                {t('clear')}
                            </button>
                            <button
                                type="button"
                                disabled={lockRemain > 0 || submitting}
                                onClick={() => appendDigit('0')}
                                className="flex h-14 items-center justify-center rounded-full border border-slate-200/80 bg-white text-xl font-bold text-slate-800 shadow-sm transition-all active:scale-95 disabled:cursor-not-allowed disabled:opacity-40 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-100"
                            >
                                0
                            </button>
                            <button
                                type="button"
                                disabled={lockRemain > 0 || submitting || pinInput.length === 0}
                                onClick={backspace}
                                className="flex h-14 items-center justify-center rounded-full border border-slate-200/80 bg-slate-100 text-slate-600 transition-all active:scale-95 disabled:cursor-not-allowed disabled:opacity-40 dark:border-slate-600 dark:bg-slate-800 dark:text-slate-300"
                                aria-label={t('backspace')}
                            >
                                <Delete size={20} />
                            </button>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    );
};

export default SharePinGate;
