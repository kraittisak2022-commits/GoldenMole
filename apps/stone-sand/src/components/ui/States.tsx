import { AlertCircle, Inbox } from 'lucide-react';
import { ReactNode } from 'react';
import Skeleton from './Skeleton';

/** Placeholder rows shaped like the lists they stand in for, so the page does not jump when data arrives. */
export function Loading({ label = 'กำลังโหลด…', rows = 3, page = false }: { label?: string; rows?: number; page?: boolean }) {
  const list = (
    <div role="status" className="overflow-hidden rounded border border-border bg-surface">
      <span className="sr-only">{label}</span>
      <ul className="divide-y divide-border">
        {Array.from({ length: rows }, (_, i) => (
          <li key={i} className="flex items-center gap-3 px-4 py-3.5">
            <Skeleton className="h-10 w-10 shrink-0 rounded-full" />
            <div className="flex min-w-0 flex-1 flex-col gap-2">
              <Skeleton className={`h-3.5 ${i % 2 ? 'w-1/2' : 'w-2/3'}`} />
              <Skeleton className="h-3 w-1/3" />
            </div>
            <Skeleton className="h-4 w-16 shrink-0" />
          </li>
        ))}
      </ul>
    </div>
  );
  return page ? <div className="mx-auto w-full max-w-3xl p-4 sm:p-6">{list}</div> : list;
}

export function ErrorBox({ message }: { message: string }) {
  return (
    <div
      role="alert"
      className="flex items-start gap-2 rounded border border-red-200 bg-destructive-soft px-4 py-3 text-sm text-red-700"
    >
      <AlertCircle size={18} className="mt-0.5 shrink-0" aria-hidden />
      <span>{message}</span>
    </div>
  );
}

export function Empty({ title, action }: { title: string; action?: ReactNode }) {
  return (
    <div className="flex flex-col items-center justify-center gap-3 py-12 text-center">
      <Inbox size={28} className="text-slate-300" aria-hidden />
      <p className="text-sm text-muted">{title}</p>
      {action}
    </div>
  );
}
