import { ReactNode } from 'react';

interface ChipProps {
  active: boolean;
  onClick: () => void;
  children: ReactNode;
  count?: number;
}

export default function Chip({ active, onClick, children, count }: ChipProps) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={active}
      className={[
        'inline-flex min-h-10 items-center gap-1.5 whitespace-nowrap rounded-full border px-3.5 text-sm transition-colors duration-200 cursor-pointer',
        active
          ? 'border-primary bg-primary text-primary-foreground'
          : 'border-border bg-surface text-ink hover:bg-subtle',
      ].join(' ')}
    >
      {children}
      {count !== undefined ? (
        <span
          className={[
            'rounded-full px-1.5 text-xs tabular-nums',
            active ? 'bg-white/20' : 'bg-subtle text-muted',
          ].join(' ')}
        >
          {count}
        </span>
      ) : null}
    </button>
  );
}
