import { createContext, ReactNode, useCallback, useContext, useRef, useState } from 'react';

interface ToastState {
  id: number;
  message: string;
}

const ToastContext = createContext<(message: string) => void>(() => undefined);

/** Material snackbar: one message at a time, bottom centre, above the upload tray on phones. */
export function ToastProvider({ children }: { children: ReactNode }) {
  const [toast, setToast] = useState<ToastState | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout>>();

  const show = useCallback((message: string) => {
    clearTimeout(timer.current);
    setToast({ id: Date.now(), message });
    timer.current = setTimeout(() => setToast(null), 3500);
  }, []);

  return (
    <ToastContext.Provider value={show}>
      {children}
      <div aria-live="polite" className="pointer-events-none fixed inset-x-0 bottom-[max(1rem,env(safe-area-inset-bottom))] z-[70] flex justify-center px-4">
        {toast ? (
          <div key={toast.id} role="status" className="fade-in rounded bg-[#313033] px-4 py-3 text-sm text-[#F4EFF4] shadow-e3 dark:bg-[#E6E1E5] dark:text-[#313033]">
            {toast.message}
          </div>
        ) : null}
      </div>
    </ToastContext.Provider>
  );
}

export const useToast = () => useContext(ToastContext);
