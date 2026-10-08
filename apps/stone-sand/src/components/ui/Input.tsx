import { InputHTMLAttributes, forwardRef } from 'react';

interface InputProps extends InputHTMLAttributes<HTMLInputElement> {
  invalid?: boolean;
}

const Input = forwardRef<HTMLInputElement, InputProps>(function Input(
  { className = '', invalid = false, ...props },
  ref,
) {
  return (
    <input
      ref={ref}
      aria-invalid={invalid || undefined}
      className={[
        'w-full min-h-11 rounded border bg-surface px-3 py-2.5 text-base sm:text-sm text-ink placeholder:text-muted transition-colors duration-200',
        invalid ? 'border-destructive focus:border-destructive' : 'border-border focus:border-primary',
        className,
      ].join(' ')}
      {...props}
    />
  );
});

export default Input;
