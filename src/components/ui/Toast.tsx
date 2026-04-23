import { useEffect, useState } from 'react';
import { CheckCircle2, XCircle } from 'lucide-react';

const Toast = ({ message, onClose, countdownMs }: { message: string, onClose: () => void, countdownMs?: number }) => {
    const [remainingMs, setRemainingMs] = useState<number>(countdownMs ?? 0);

    useEffect(() => {
        if (!countdownMs || countdownMs <= 0) {
            setRemainingMs(0);
            return;
        }
        const endAt = Date.now() + countdownMs;
        setRemainingMs(countdownMs);
        const timer = window.setInterval(() => {
            const left = Math.max(0, endAt - Date.now());
            setRemainingMs(left);
            if (left <= 0) window.clearInterval(timer);
        }, 200);
        return () => window.clearInterval(timer);
    }, [countdownMs, message]);

    const remainingSec = Math.max(1, Math.ceil(remainingMs / 1000));

    return (
        <div className="fixed bottom-4 right-4 bg-slate-900 dark:bg-slate-800/95 dark:backdrop-blur text-white px-6 py-3 rounded-xl shadow-2xl flex items-center gap-3 animate-slide-up z-[110] border border-slate-700 dark:border-amber-500/20">
            <CheckCircle2 className="text-emerald-400" size={20} />
            <span className="text-sm font-medium">
                {message}
                {countdownMs && countdownMs > 0 ? ` (ปิดใน ${remainingSec} วินาที)` : ''}
            </span>
            <button onClick={onClose} className="ml-2 hover:text-slate-300"><XCircle size={16} /></button>
        </div>
    );
};

export default Toast;
