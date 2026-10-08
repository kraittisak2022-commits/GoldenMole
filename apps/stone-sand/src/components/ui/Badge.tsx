import { ReactNode } from 'react';

export type BadgeTone = 'neutral' | 'success' | 'warning' | 'danger' | 'info';

const tones: Record<BadgeTone, string> = {
  neutral: 'bg-subtle text-slate-700 border-border',
  success: 'bg-success-soft text-emerald-800 border-emerald-200',
  warning: 'bg-warning-soft text-amber-800 border-amber-200',
  danger: 'bg-destructive-soft text-red-700 border-red-200',
  info: 'bg-primary-soft text-primary border-blue-100',
};

export default function Badge({ tone = 'neutral', children }: { tone?: BadgeTone; children: ReactNode }) {
  return (
    <span
      className={`inline-flex items-center gap-1 whitespace-nowrap rounded-full border px-2.5 py-0.5 text-xs font-medium ${tones[tone]}`}
    >
      {children}
    </span>
  );
}
