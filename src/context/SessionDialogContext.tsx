import { ReactNode, useCallback, useEffect, useMemo, useState } from 'react';
import { SessionDialogContextValue } from './useSessionDialog';
import { SessionDialogContext } from './SessionDialogStore';

type DialogMode = 'alert' | 'confirm';

type DialogQueueItem = {
    id: string;
    mode: DialogMode;
    title: string;
    message: string;
    resolve: (value: boolean) => void;
};

export function SessionDialogProvider({ children }: { children: ReactNode }) {
    const [queue, setQueue] = useState<DialogQueueItem[]>([]);
    const activeDialog = queue[0] || null;

    const dequeue = useCallback((ok: boolean) => {
        setQueue(prev => {
            if (prev.length === 0) return prev;
            const [first, ...rest] = prev;
            first.resolve(ok);
            return rest;
        });
    }, []);

    const alert = useCallback((msg: string, opts?: { title?: string }) => {
        return new Promise<void>((resolve) => {
            const item: DialogQueueItem = {
                id: `${Date.now()}_${Math.random().toString(36).slice(2, 7)}`,
                mode: 'alert',
                title: opts?.title || 'แจ้งเตือน',
                message: msg,
                resolve: () => resolve(),
            };
            setQueue(prev => [...prev, item]);
        });
    }, []);

    const confirm = useCallback((msg: string, opts?: { title?: string }) => {
        return new Promise<boolean>((resolve) => {
            const item: DialogQueueItem = {
                id: `${Date.now()}_${Math.random().toString(36).slice(2, 7)}`,
                mode: 'confirm',
                title: opts?.title || 'ยืนยัน',
                message: msg,
                resolve,
            };
            setQueue(prev => [...prev, item]);
        });
    }, []);

    const value = useMemo(() => ({ alert, confirm }), [alert, confirm]);

    useEffect(() => {
        if (!activeDialog) return;
        const onKey = (e: KeyboardEvent) => {
            if (e.key === 'Escape') {
                e.preventDefault();
                dequeue(false);
            }
        };
        window.addEventListener('keydown', onKey);
        return () => window.removeEventListener('keydown', onKey);
    }, [activeDialog, dequeue]);

    useEffect(() => {
        return () => {
            setQueue(prev => {
                prev.forEach(item => item.resolve(false));
                return [];
            });
        };
    }, []);

    return (
        <SessionDialogContext.Provider value={value}>
            {children}
            {activeDialog && (
                <div
                    className="fixed inset-0 z-[200] flex items-end justify-center bg-black/45 p-3 pb-[max(0.75rem,env(safe-area-inset-bottom))] sm:items-center sm:p-6"
                    role="dialog"
                    aria-modal="true"
                    aria-labelledby="session-dialog-title"
                    onMouseDown={(e) => {
                        if (e.target === e.currentTarget) dequeue(false);
                    }}
                >
                    <div
                        key={activeDialog.id}
                        className="max-h-[min(78dvh,480px)] w-full max-w-md overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-2xl dark:border-white/10 dark:bg-slate-900"
                        onMouseDown={(e) => e.stopPropagation()}
                    >
                        <div className="border-b border-slate-100 px-4 py-3 dark:border-white/10">
                            <h2 id="session-dialog-title" className="text-base font-bold text-slate-900 dark:text-slate-50">
                                {activeDialog.title}
                            </h2>
                        </div>
                        <div className="max-h-[min(52dvh,360px)] overflow-y-auto overscroll-contain px-4 py-3">
                            <p className="whitespace-pre-wrap break-words text-sm leading-relaxed text-slate-700 dark:text-slate-200">{activeDialog.message}</p>
                        </div>
                        <div className="flex justify-end gap-2 border-t border-slate-100 bg-slate-50/80 px-3 py-3 dark:border-white/10 dark:bg-slate-950/40">
                            {activeDialog.mode === 'confirm' && (
                                <button
                                    type="button"
                                    className="min-h-[44px] rounded-xl border border-slate-200 bg-white px-4 text-sm font-semibold text-slate-700 touch-manipulation hover:bg-slate-50 dark:border-white/15 dark:bg-slate-800 dark:text-slate-100 dark:hover:bg-slate-700"
                                    onClick={() => dequeue(false)}
                                >
                                    ยกเลิก
                                </button>
                            )}
                            <button
                                type="button"
                                className="min-h-[44px] rounded-xl bg-slate-900 px-4 text-sm font-semibold text-white touch-manipulation hover:bg-slate-800 dark:bg-white dark:text-slate-900 dark:hover:bg-slate-100"
                                onClick={() => dequeue(true)}
                            >
                                ตกลง
                            </button>
                        </div>
                    </div>
                </div>
            )}
        </SessionDialogContext.Provider>
    );
}
