import { AlertCircle, Inbox, Loader2 } from 'lucide-react';
import { ReactNode } from 'react';

export function Loading({ label = 'กำลังโหลด…' }: { label?: string }) {
  return (
    <div className="flex items-center justify-center gap-2 py-12 text-sm text-muted" role="status">
      <Loader2 size={18} className="animate-spin" aria-hidden />
      {label}
    </div>
  );
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
