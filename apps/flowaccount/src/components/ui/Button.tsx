import { ButtonHTMLAttributes, ReactNode } from 'react';

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  children: ReactNode;
  variant?: 'primary' | 'secondary' | 'ghost' | 'danger';
}

const variants: Record<NonNullable<ButtonProps['variant']>, string> = {
  primary:
    'bg-accent text-accent-foreground hover:bg-sky-800 border border-transparent',
  secondary:
    'bg-surface text-ink border border-border hover:bg-slate-50',
  ghost: 'bg-transparent text-muted hover:bg-slate-100 border border-transparent',
  danger:
    'bg-destructive text-destructive-foreground hover:bg-red-700 border border-transparent',
};

export default function Button({
  children,
  variant = 'primary',
  className = '',
  disabled = false,
  type = 'button',
  ...props
}: ButtonProps) {
  return (
    <button
      type={type}
      disabled={disabled}
      className={[
        'inline-flex min-h-11 items-center justify-center gap-2 rounded-DEFAULT px-4 py-2.5 text-sm font-medium transition-colors duration-200 cursor-pointer',
        'disabled:opacity-50 disabled:cursor-not-allowed',
        variants[variant],
        className,
      ].join(' ')}
      {...props}
    >
      {children}
    </button>
  );
}
