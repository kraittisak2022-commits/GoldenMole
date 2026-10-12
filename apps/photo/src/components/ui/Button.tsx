import { ButtonHTMLAttributes, ReactNode } from 'react';

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  children: ReactNode;
  /** filled = main action, tonal = secondary emphasis, outlined / text = low emphasis (Material 3). */
  variant?: 'filled' | 'tonal' | 'outlined' | 'text' | 'danger';
}

const variants: Record<NonNullable<ButtonProps['variant']>, string> = {
  filled: 'bg-primary text-primary-foreground hover:bg-primary-hover hover:shadow-e1',
  tonal: 'bg-primary-soft text-primary-soft-foreground hover:shadow-e1',
  outlined: 'border border-border text-primary hover:bg-primary/[0.08]',
  text: 'text-primary hover:bg-primary/[0.08]',
  danger: 'bg-destructive text-destructive-foreground hover:shadow-e1',
};

export default function Button({ children, variant = 'filled', className = '', type = 'button', ...props }: ButtonProps) {
  return (
    <button
      type={type}
      className={[
        'inline-flex min-h-11 items-center justify-center gap-2 rounded-full px-5 text-sm font-medium transition duration-150 cursor-pointer select-none',
        'disabled:cursor-not-allowed disabled:opacity-40 disabled:shadow-none',
        variants[variant],
        className,
      ].join(' ')}
      {...props}
    >
      {children}
    </button>
  );
}
