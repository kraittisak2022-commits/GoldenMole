import { ButtonHTMLAttributes, forwardRef, ReactNode } from 'react';

interface IconButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  label: string;
  children: ReactNode;
  tone?: 'default' | 'onDark';
}

const IconButton = forwardRef<HTMLButtonElement, IconButtonProps>(function IconButton(
  { label, children, tone = 'default', className = '', type = 'button', ...props },
  ref,
) {
  return (
    <button
      ref={ref}
      type={type}
      aria-label={label}
      title={label}
      className={[
        'inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-full transition duration-150 cursor-pointer disabled:cursor-not-allowed disabled:opacity-40',
        tone === 'onDark' ? 'text-white hover:bg-white/15' : 'text-muted hover:bg-ink/[0.08] hover:text-ink',
        className,
      ].join(' ')}
      {...props}
    >
      {children}
    </button>
  );
});

export default IconButton;
