import { ReactNode } from 'react';
import { Loader2 } from 'lucide-react';

export function Spinner({ label = 'กำลังโหลด', size = 24 }: { label?: string; size?: number }) {
  return (
    <span role="status" className="inline-flex items-center gap-2 text-muted">
      <Loader2 size={size} className="animate-spin text-primary" aria-hidden />
      <span className="sr-only">{label}</span>
    </span>
  );
}

export function EmptyState({ icon, title, body, action }: { icon: ReactNode; title: string; body?: string; action?: ReactNode }) {
  return (
    <div className="mx-auto flex max-w-sm flex-col items-center px-6 py-16 text-center">
      <div className="mb-5 flex h-24 w-24 items-center justify-center rounded-full bg-container text-primary">{icon}</div>
      <h2 className="text-xl font-medium text-ink">{title}</h2>
      {body ? <p className="mt-2 text-sm text-muted">{body}</p> : null}
      {action ? <div className="mt-6">{action}</div> : null}
    </div>
  );
}

export function ErrorState({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return (
    <div role="alert" className="mx-auto max-w-sm px-6 py-16 text-center">
      <p className="text-base text-ink">{message}</p>
      {onRetry ? (
        <button type="button" onClick={onRetry} className="mt-4 min-h-11 cursor-pointer rounded-full px-5 text-sm font-medium text-primary hover:bg-primary/[0.08]">
          ลองใหม่
        </button>
      ) : null}
    </div>
  );
}
